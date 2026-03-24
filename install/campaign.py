#!/usr/bin/env python3
"""
campaign.py — Batch-Kampagne: Outbound-Calls aus CSV via AMI Originate

Usage:
    python3 campaign.py leads.csv
    python3 campaign.py leads.csv --rate 5 --dry-run
    python3 campaign.py leads.csv --env /opt/ava/.env --output results.csv

CSV-Format (Header-Zeile erwartet):
    name,phone,language,job_title
    Max Mustermann,+4917612345678,de,Lagermitarbeiter
    Amir Bobic,+4917698765432,bs,Fahrer
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import logging
import os
import re
import sys
import telnetlib
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

# Mindest-Python-Version: 3.11
if sys.version_info < (3, 11):
    sys.exit("Python 3.11 oder hoeher erforderlich")

# Optional: tqdm fuer Progress-Bar
try:
    from tqdm import tqdm
    HAS_TQDM = True
except ImportError:
    HAS_TQDM = False

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("campaign")

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
@dataclass
class AmiConfig:
    host: str = "127.0.0.1"
    port: int = 5038
    username: str = ""
    secret: str = ""

    @classmethod
    def from_env_file(cls, env_path: str) -> "AmiConfig":
        """Liest AMI-Konfiguration aus .env Datei (kein os.environ polluting)."""
        cfg = cls()
        env_file = Path(env_path)
        if not env_file.exists():
            raise FileNotFoundError(f".env Datei nicht gefunden: {env_path}")

        with env_file.open() as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                match key:
                    case "ASTERISK_AMI_HOST":   cfg.host = val
                    case "ASTERISK_AMI_PORT":   cfg.port = int(val) if val.isdigit() else 5038
                    case "ASTERISK_AMI_USER":   cfg.username = val
                    case "ASTERISK_AMI_PASS":   cfg.secret = val

        if not cfg.username:
            raise ValueError("ASTERISK_AMI_USER fehlt in .env")
        if not cfg.secret:
            raise ValueError("ASTERISK_AMI_PASS fehlt in .env")
        return cfg


@dataclass
class CampaignConfig:
    rate_per_minute: int = 10
    max_concurrent: int = 5
    max_retries: int = 3
    retry_pause_hours: float = 2.0
    caller_id: str = "Step2Job <+4930123456>"
    context: str = "ava-outbound"
    campaign_id: str = field(default_factory=lambda: f"campaign-{datetime.now().strftime('%Y%m%d%H%M%S')}")

# ---------------------------------------------------------------------------
# Datenmodelle
# ---------------------------------------------------------------------------
@dataclass
class Lead:
    name: str
    phone: str
    language: str = "de"
    job_title: str = ""
    lead_id: str = ""

    def __post_init__(self) -> None:
        if not self.lead_id:
            self.lead_id = f"lead-{int(time.time() * 1000)}"

    def is_valid(self) -> tuple[bool, str]:
        """E.164-Validierung."""
        if not re.match(r"^\+[1-9]\d{6,14}$", self.phone):
            return False, f"Ungueltige Nummer: {self.phone}"
        if not self.name:
            return False, "Name darf nicht leer sein"
        if self.language not in ("de", "bs", "sr"):
            return False, f"Unbekannte Sprache: {self.language}"
        return True, ""


@dataclass
class CallResult:
    lead: Lead
    attempt: int
    status: str          # success | failed | skipped | invalid
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    call_id: str = ""
    error: str = ""

# ---------------------------------------------------------------------------
# AMI-Client
# ---------------------------------------------------------------------------
class AmiClient:
    """Einfacher synchroner AMI-Client via Telnet."""

    def __init__(self, config: AmiConfig, timeout: int = 10) -> None:
        self.config = config
        self.timeout = timeout

    def originate(
        self,
        lead: Lead,
        campaign: CampaignConfig,
        dry_run: bool = False,
    ) -> tuple[bool, str]:
        """
        Startet einen Outbound-Call via AMI Originate.
        Gibt (success, error_message) zurueck.
        """
        if dry_run:
            logger.info("[DRY-RUN] Wuerde anrufen: %s (%s)", lead.phone, lead.name)
            return True, ""

        try:
            tn = telnetlib.Telnet(self.config.host, self.config.port, timeout=self.timeout)

            # Auf AMI-Banner warten
            tn.read_until(b"Asterisk Call Manager", timeout=5)

            # Login
            self._send_action(tn, {
                "Action":   "Login",
                "Username": self.config.username,
                "Secret":   self.config.secret,
            })
            response = tn.read_until(b"\r\n\r\n", timeout=5).decode("utf-8", errors="replace")
            if "Success" not in response:
                tn.close()
                return False, f"AMI Login fehlgeschlagen: {response[:100]}"

            # Originate
            self._send_action(tn, {
                "Action":   "Originate",
                "Channel":  f"PJSIP/{lead.phone.lstrip('+' )}@sipgate",
                "Context":  campaign.context,
                "Exten":    "s",
                "Priority": "1",
                "CallerID": campaign.caller_id,
                "Timeout":  "30000",
                "Async":    "true",
                "Variable": "\r\nVariable: ".join([
                    f"OUTBOUND_NUMBER={lead.phone}",
                    f"LEAD_NAME={lead.name}",
                    f"LEAD_ID={lead.lead_id}",
                    f"LEAD_LANGUAGE={lead.language}",
                    f"CAMPAIGN_ID={campaign.campaign_id}",
                ]),
            })
            orig_response = tn.read_until(b"\r\n\r\n", timeout=8).decode("utf-8", errors="replace")

            # Logout
            self._send_action(tn, {"Action": "Logoff"})
            tn.close()

            if "Response: Success" in orig_response:
                return True, ""
            else:
                error = next(
                    (l for l in orig_response.splitlines() if l.startswith("Message:")),
                    orig_response[:120],
                )
                return False, error

        except ConnectionRefusedError:
            return False, f"AMI nicht erreichbar auf {self.config.host}:{self.config.port}"
        except TimeoutError:
            return False, "AMI Timeout"
        except Exception as exc:  # noqa: BLE001
            return False, f"Unerwarteter Fehler: {exc}"

    @staticmethod
    def _send_action(tn: telnetlib.Telnet, fields: dict[str, str]) -> None:
        """Schreibt eine AMI-Aktion als CRLF-Sequenz."""
        msg = ""
        for key, val in fields.items():
            msg += f"{key}: {val}\r\n"
        msg += "\r\n"
        tn.write(msg.encode("utf-8"))

# ---------------------------------------------------------------------------
# CSV-Verarbeitung
# ---------------------------------------------------------------------------
def load_leads(csv_path: str) -> list[Lead]:
    """Laedt Leads aus CSV. Erwartet: name, phone, language (optional), job_title (optional)."""
    leads: list[Lead] = []
    path = Path(csv_path)
    if not path.exists():
        raise FileNotFoundError(f"CSV nicht gefunden: {csv_path}")

    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError("CSV hat keine Header-Zeile")

        # Pflichtfelder pruefen
        required = {"name", "phone"}
        headers_lower = {h.lower().strip() for h in reader.fieldnames if h}
        missing = required - headers_lower
        if missing:
            raise ValueError(f"CSV fehlt Pflichtfelder: {missing}")

        for i, row in enumerate(reader, start=2):
            # Normalisiere Header zu lowercase
            row_norm = {k.lower().strip(): v.strip() for k, v in row.items() if k}
            lead = Lead(
                name=row_norm.get("name", ""),
                phone=row_norm.get("phone", ""),
                language=row_norm.get("language", "de"),
                job_title=row_norm.get("job_title", row_norm.get("job", "")),
                lead_id=row_norm.get("lead_id", f"csv-{i}"),
            )
            leads.append(lead)

    logger.info("Geladen: %d Leads aus %s", len(leads), csv_path)
    return leads


def save_results(results: list[CallResult], output_path: str) -> None:
    """Schreibt Ergebnisse als CSV."""
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["call_id", "lead_name", "phone", "language", "status", "attempt", "timestamp", "error"])
        for r in results:
            writer.writerow([
                r.call_id,
                r.lead.name,
                r.lead.phone,
                r.lead.language,
                r.status,
                r.attempt,
                r.timestamp,
                r.error,
            ])
    logger.info("Ergebnisse gespeichert: %s", output_path)

# ---------------------------------------------------------------------------
# Kampagnen-Runner
# ---------------------------------------------------------------------------
class CampaignRunner:
    def __init__(
        self,
        ami_config: AmiConfig,
        campaign_config: CampaignConfig,
        dry_run: bool = False,
    ) -> None:
        self.ami = AmiClient(ami_config)
        self.campaign = campaign_config
        self.dry_run = dry_run
        self.results: list[CallResult] = []

    def run(self, leads: list[Lead]) -> list[CallResult]:
        """Fuehrt Kampagne synchron mit Rate-Limiting aus."""
        retry_queue: dict[str, tuple[Lead, int]] = {}  # lead_id -> (Lead, attempt)
        interval = 60.0 / self.campaign.rate_per_minute

        all_leads: list[tuple[Lead, int]] = [(lead, 1) for lead in leads]
        iterator = tqdm(all_leads, desc="Kampagne", unit="call") if HAS_TQDM else all_leads

        for lead, attempt in iterator:
            valid, reason = lead.is_valid()
            if not valid:
                logger.warning("Ueberspringe ungueltige Nummer %s: %s", lead.phone, reason)
                self.results.append(CallResult(
                    lead=lead, attempt=attempt, status="invalid", error=reason
                ))
                continue

            logger.info("[%d] Rufe an: %s (%s) — Versuch %d", len(self.results) + 1, lead.phone, lead.name, attempt)

            success, error = self.ami.originate(lead, self.campaign, self.dry_run)

            result = CallResult(
                lead=lead,
                attempt=attempt,
                status="success" if success else "failed",
                call_id=f"{self.campaign.campaign_id}-{lead.lead_id}-{attempt}",
                error=error,
            )
            self.results.append(result)

            if not success:
                logger.warning("Fehlgeschlagen: %s — %s", lead.phone, error)
                if attempt < self.campaign.max_retries:
                    retry_queue[lead.lead_id] = (lead, attempt + 1)
            else:
                logger.info("Erfolgreich initiiert: %s", lead.phone)

            # Rate-Limiting
            if not self.dry_run:
                time.sleep(interval)

        # Retry-Durchlaeufe
        for attempt_num in range(2, self.campaign.max_retries + 1):
            if not retry_queue:
                break
            logger.info("Retry-Durchlauf %d: %d Leads", attempt_num, len(retry_queue))
            if not self.dry_run:
                logger.info("Warte %.0f Minuten vor Retry...", self.campaign.retry_pause_hours * 60)
                time.sleep(self.campaign.retry_pause_hours * 3600)

            current_retry = dict(retry_queue)
            retry_queue.clear()

            for lead_id, (lead, attempt) in current_retry.items():
                success, error = self.ami.originate(lead, self.campaign, self.dry_run)
                result = CallResult(
                    lead=lead,
                    attempt=attempt,
                    status="success" if success else "failed",
                    call_id=f"{self.campaign.campaign_id}-{lead.lead_id}-{attempt}",
                    error=error,
                )
                self.results.append(result)

                if not success and attempt < self.campaign.max_retries:
                    retry_queue[lead.lead_id] = (lead, attempt + 1)

                if not self.dry_run:
                    time.sleep(interval)

        return self.results

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="AVA Kampagnen-Script — Outbound-Calls aus CSV",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("csv_file", help="Pfad zur Leads-CSV-Datei")
    parser.add_argument(
        "--env", default="/opt/ava/.env",
        help="Pfad zur .env Datei (Standard: /opt/ava/.env)",
    )
    parser.add_argument(
        "--rate", type=int, default=10,
        help="Calls pro Minute (Standard: 10)",
    )
    parser.add_argument(
        "--max-concurrent", type=int, default=5,
        help="Maximale parallele Calls (Standard: 5)",
    )
    parser.add_argument(
        "--retries", type=int, default=3,
        help="Maximale Wiederholungsversuche (Standard: 3)",
    )
    parser.add_argument(
        "--retry-hours", type=float, default=2.0,
        help="Pause zwischen Retries in Stunden (Standard: 2.0)",
    )
    parser.add_argument(
        "--campaign-id", default="",
        help="Kampagnen-ID (Standard: automatisch generiert)",
    )
    parser.add_argument(
        "--output", default="",
        help="Ergebnis-CSV-Datei (Standard: results_TIMESTAMP.csv)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Simulieren ohne echte Calls zu initiieren",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Debug-Ausgabe aktivieren",
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.dry_run:
        logger.info("[DRY-RUN] Modus aktiv — keine echten Calls")

    # AMI-Konfiguration laden
    try:
        ami_cfg = AmiConfig.from_env_file(args.env)
    except (FileNotFoundError, ValueError) as exc:
        logger.error("Konfigurationsfehler: %s", exc)
        sys.exit(1)

    # Kampagnen-Konfiguration
    campaign_cfg = CampaignConfig(
        rate_per_minute=args.rate,
        max_concurrent=args.max_concurrent,
        max_retries=args.retries,
        retry_pause_hours=args.retry_hours,
        campaign_id=args.campaign_id or f"campaign-{datetime.now().strftime('%Y%m%d%H%M%S')}",
    )

    # Leads laden
    try:
        leads = load_leads(args.csv_file)
    except (FileNotFoundError, ValueError) as exc:
        logger.error("CSV-Fehler: %s", exc)
        sys.exit(1)

    if not leads:
        logger.error("Keine Leads in CSV gefunden")
        sys.exit(1)

    # Kampagne starten
    logger.info(
        "Starte Kampagne '%s': %d Leads, %d/min, max %d Retries",
        campaign_cfg.campaign_id, len(leads), campaign_cfg.rate_per_minute, campaign_cfg.max_retries,
    )

    runner = CampaignRunner(ami_cfg, campaign_cfg, dry_run=args.dry_run)
    results = runner.run(leads)

    # Zusammenfassung
    success = sum(1 for r in results if r.status == "success")
    failed  = sum(1 for r in results if r.status == "failed")
    invalid = sum(1 for r in results if r.status == "invalid")

    print("\n" + "=" * 50)
    print(f"  Kampagne abgeschlossen: {campaign_cfg.campaign_id}")
    print(f"  Erfolgreich:  {success}")
    print(f"  Fehlgeschl.:  {failed}")
    print(f"  Ungueltig:    {invalid}")
    print(f"  Gesamt:       {len(results)}")
    print("=" * 50)

    # Ergebnisse speichern
    output_path = args.output or f"results_{campaign_cfg.campaign_id}.csv"
    save_results(results, output_path)
    print(f"\nErgebnisse: {output_path}")

    if failed > 0:
        sys.exit(2)  # Partial failure


if __name__ == "__main__":
    main()

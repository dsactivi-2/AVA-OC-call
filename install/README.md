# AVA + Asterisk + OpenClaw — 1-Click Installer

Automatisierter Installer fuer den AVA AI Voice Agent Stack auf Ubuntu 22.04/24.04 LTS oder Debian 12.

## Voraussetzungen

| Anforderung | Minimum |
|---|---|
| Betriebssystem | Ubuntu 22.04+, Debian 12 |
| RAM | 2 GB (4 GB empfohlen mit Whisper) |
| Freier Speicher | 5 GB auf / |
| Python | 3.11+ (wird automatisch installiert) |
| Rechte | root oder passwordless sudo |
| Netzwerk | Internetzugang (apt, GitHub) |

Zusaetzlich benoetigt:
- OpenClaw laeuft lokal auf Port 18789 mit einem konfigurierten Ava-Agent
- Mindestens ein TTS-API-Key (ElevenLabs empfohlen) oder lokales Whisper

## Quick Start

```bash
# 1. Repository mit Configs sicherstellen
git clone <repo-url> /opt/ava-setup
cd /opt/ava-setup/install

# 2. .env.example kopieren und Passwörter setzen
cp .env.example .env
nano .env   # AVA_ARI_PASSWORD und AVA_AMI_PASSWORD setzen

# 3. Installer starten (interaktiv — fragt nach Zugangsdaten)
sudo ./install.sh
```

Der Installer sammelt alle Zugangsdaten interaktiv und speichert sie NICHT im Log.

## Was installiert wird

| Komponente | Pfad / Service |
|---|---|
| Asterisk PBX | apt-Paket, Configs in /etc/asterisk/ |
| Python 3.11 + venv | /opt/ava/venv/ |
| AVA AI Voice Agent | /opt/ava/ (geklont von GitHub) |
| Konfiguration | /opt/ava/config.yaml, /opt/ava/.env |
| Systemd Service | ava-voice-agent.service |
| Logs | /var/log/ava/, /var/log/ava-install.log |

## Verfuegbare Flags

```bash
sudo ./install.sh                   # Standard-Installation (interaktiv)
sudo ./install.sh --dry-run         # Nur pruefen, KEINE Aenderungen
sudo ./install.sh --skip-asterisk   # Asterisk bereits installiert — nur AVA
sudo ./install.sh --help            # Diese Hilfe
```

## Einzelne Schritte manuell ausfuehren

Die Setup-Schritte koennen einzeln ausgefuehrt werden (z.B. nach Fehler):

```bash
sudo bash setup/00-preflight.sh    # Voraussetzungen pruefen
sudo bash setup/01-system.sh       # apt-Pakete installieren
sudo bash setup/02-asterisk.sh     # Asterisk-Configs deployen
sudo bash setup/03-ava.sh          # AVA installieren + .env schreiben
sudo bash setup/04-services.sh     # Systemd-Service erstellen + starten
sudo bash setup/05-verify.sh       # Vollstaendige Verifikation
```

Hinweis: 03-ava.sh und 04-services.sh benoetigen die ENV-Variablen aus collect_credentials()
(AVA_ARI_SECRET, AVA_AMI_SECRET usw.), die install.sh exportiert. Bei manuellem Aufruf
muessen diese vorher manuell exportiert werden.

## Rollback

```bash
sudo ./rollback.sh              # Interaktiv (fragt nach Bestaetigung)
sudo ./rollback.sh --dry-run    # Nur anzeigen was geloescht wuerde
sudo ./rollback.sh --force      # Ohne Bestaetigung
```

Der Rollback stoppt ava-voice-agent.service, entfernt /opt/ava und stellt die
Asterisk-Backup-Configs wieder her. Asterisk selbst bleibt installiert.

## Troubleshooting

### 1. ava-voice-agent.service startet nicht

```bash
journalctl -u ava-voice-agent -n 50 --no-pager
```

Haeufige Ursachen:
- `main.py not found`: AVA-Repository hat andere Struktur — `ls /opt/ava/` pruefen
- `ModuleNotFoundError`: pip install fehlgeschlagen — `/opt/ava/venv/bin/pip install -r /opt/ava/requirements.txt`
- `Connection refused 8088`: Asterisk ARI nicht gestartet — `systemctl status asterisk`

### 2. Asterisk startet nicht

```bash
journalctl -u asterisk -n 50 --no-pager
asterisk -c    # Interaktive Konsole fuer Debugging
```

Haeufige Ursachen:
- Port 5060 belegt: `ss -ltnp | grep :5060` — anderen SIP-Client stoppen
- Konfigurationsfehler: `asterisk -C /etc/asterisk/asterisk.conf -c`
- Fehlende Module: `asterisk -rx 'module show like app_audiosocket'`

### 3. Python-Version zu alt (< 3.11)

Ubuntu 20.04 liefert Python 3.8. Manuell installieren:

```bash
add-apt-repository ppa:deadsnakes/ppa
apt-get update
apt-get install python3.11 python3.11-venv python3.11-dev
```

### 4. Port 8088 (ARI) nicht erreichbar

```bash
# ARI in Asterisk pruefen
asterisk -rx 'ari show status'
asterisk -rx 'http show status'

# Falls HTTP nicht aktiv: /etc/asterisk/http.conf pruefen
grep -E 'enabled|bindaddr|port' /etc/asterisk/http.conf
```

Sicherstellen dass in `/etc/asterisk/http.conf` steht:
```ini
[general]
enabled = yes
bindaddr = 127.0.0.1
port = 8088
```

### 5. AudioSocket-Verbindung schlaegt fehl (Port 9092 nicht offen)

AVA oeffnet Port 9092 erst wenn der Service laeuft. Pruefen:

```bash
systemctl status ava-voice-agent
ss -ltnp | grep :9092

# Manuell starten fuer Debugging:
sudo -u ava /opt/ava/venv/bin/python /opt/ava/main.py --config /opt/ava/config.yaml
```

## Naechste Schritte nach Installation

```bash
# Status aller Services pruefen
sudo bash setup/05-verify.sh

# AVA Live-Logs beobachten
journalctl -u ava-voice-agent -f

# Testanruf ausloesen (Kampagnen-Script)
../scripts/outbound-call.sh +4917600000000 "Test Lead"

# Konfiguration anpassen
nano /opt/ava/config.yaml
systemctl restart ava-voice-agent
```

## Dateistruktur

```
install/
├── install.sh              # Haupt-Installer (1-Click)
├── rollback.sh             # Deinstallation / Rollback
├── .env.example            # Konfigurationsvorlage
├── README.md               # Diese Datei
└── setup/
    ├── 00-preflight.sh     # Voraussetzungen pruefen
    ├── 01-system.sh        # apt-Pakete installieren
    ├── 02-asterisk.sh      # Asterisk konfigurieren
    ├── 03-ava.sh           # AVA installieren
    ├── 04-services.sh      # Systemd-Service erstellen
    └── 05-verify.sh        # Verifikation
```

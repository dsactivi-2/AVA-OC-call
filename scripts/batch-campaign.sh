#!/usr/bin/env bash
# =========================================================================
# batch-campaign.sh — CSV-basierte Outbound-Kampagne starten
# CSV Format: name,phone,language,job_title
# Verwendung: batch-campaign.sh --csv leads.csv --campaign-id "step2job-001"
#             batch-campaign.sh --csv leads.csv --campaign-id "xxx" --dry-run
#             batch-campaign.sh --csv leads.csv --campaign-id "xxx" --resume
# =========================================================================
set -euo pipefail

# -------------------------------------------------------------------------
# Konfiguration
# -------------------------------------------------------------------------
ENV_FILE="/opt/ava/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

CALL_INTERVAL="${CAMPAIGN_CALL_INTERVAL:-30}"
MAX_CONCURRENT="${CAMPAIGN_MAX_CONCURRENT:-5}"
STATE_DIR="/var/log/ava/campaigns"
OUTBOUND_SCRIPT="/usr/local/bin/outbound-call.sh"
LOG_DIR="/var/log/ava"

# -------------------------------------------------------------------------
# Usage
# -------------------------------------------------------------------------
usage() {
    cat << EOF
Verwendung: $(basename "$0") [OPTIONEN]

Pflicht:
  --csv          Pfad zur CSV-Datei mit Leads
                 Format: name,phone,language,job_title
  --campaign-id  Eindeutige Kampagnen-ID

Optional:
  --interval     Pause zwischen Calls in Sekunden (Standard: ${CALL_INTERVAL})
  --max-concurrent Maximale parallele Calls (Standard: ${MAX_CONCURRENT})
  --dry-run      CSV validieren und ausgeben ohne Calls
  --resume       Kampagne fortsetzen (bereits angerufene Leads ueberspringen)
  --stop-at      Uhrzeit zum automatischen Stopp (Format: HH:MM, z.B. 17:30)
  --start-at     Nicht vor dieser Uhrzeit starten (Format: HH:MM)

CSV-Format (erste Zeile = Header):
  name,phone,language,job_title
  Max Mustermann,+4917612345678,de,Lagermitarbeiter
  Amir Bobic,+4917698765432,bs,Fahrer

Beispiel:
  $(basename "$0") \\
    --csv /home/denis/leads-mai-2024.csv \\
    --campaign-id "step2job-mai-2024" \\
    --interval 45 \\
    --stop-at 18:00

EOF
    exit 1
}

# -------------------------------------------------------------------------
# Argumente parsen
# -------------------------------------------------------------------------
CSV_FILE=""
CAMPAIGN_ID=""
DRY_RUN=false
RESUME=false
STOP_AT=""
START_AT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --csv)           CSV_FILE="$2";     shift 2 ;;
        --campaign-id)   CAMPAIGN_ID="$2";  shift 2 ;;
        --interval)      CALL_INTERVAL="$2"; shift 2 ;;
        --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true;      shift ;;
        --resume)        RESUME=true;       shift ;;
        --stop-at)       STOP_AT="$2";      shift 2 ;;
        --start-at)      START_AT="$2";     shift 2 ;;
        --help|-h)       usage ;;
        *)               echo "Unbekannter Parameter: $1"; usage ;;
    esac
done

# -------------------------------------------------------------------------
# Validierung
# -------------------------------------------------------------------------
if [[ -z "$CSV_FILE" ]]; then
    echo "FEHLER: --csv ist Pflichtfeld" >&2; usage
fi

if [[ -z "$CAMPAIGN_ID" ]]; then
    echo "FEHLER: --campaign-id ist Pflichtfeld" >&2; usage
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "FEHLER: CSV-Datei nicht gefunden: $CSV_FILE" >&2; exit 1
fi

if [[ ! -f "$OUTBOUND_SCRIPT" ]]; then
    echo "FEHLER: outbound-call.sh nicht gefunden: $OUTBOUND_SCRIPT" >&2; exit 1
fi

# -------------------------------------------------------------------------
# Verzeichnisse erstellen
# -------------------------------------------------------------------------
mkdir -p "$STATE_DIR/$CAMPAIGN_ID"
mkdir -p "$LOG_DIR"

STATE_FILE="$STATE_DIR/$CAMPAIGN_ID/state.txt"
LOG_FILE="$LOG_DIR/campaign-${CAMPAIGN_ID}.log"
RESULTS_FILE="$STATE_DIR/$CAMPAIGN_ID/results.csv"

# -------------------------------------------------------------------------
# Logging-Funktion
# -------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

# -------------------------------------------------------------------------
# Zeitcheck-Funktion
# -------------------------------------------------------------------------
check_time_window() {
    local current_time
    current_time=$(date +%H:%M)

    if [[ -n "$START_AT" ]] && [[ "$current_time" < "$START_AT" ]]; then
        log "INFO" "Warte auf Startzeit $START_AT (aktuell: $current_time)"
        while [[ "$(date +%H:%M)" < "$START_AT" ]]; do
            sleep 30
        done
        log "INFO" "Startzeit erreicht, beginne Kampagne"
    fi

    if [[ -n "$STOP_AT" ]] && [[ "$(date +%H:%M)" > "$STOP_AT" ]]; then
        log "INFO" "Stoppzeit $STOP_AT erreicht, beende Kampagne"
        return 1
    fi
    return 0
}

# -------------------------------------------------------------------------
# CSV einlesen und validieren
# -------------------------------------------------------------------------
log "INFO" "Starte Kampagne: $CAMPAIGN_ID"
log "INFO" "CSV-Datei: $CSV_FILE"
log "INFO" "Interval: ${CALL_INTERVAL}s | Max. Concurrent: $MAX_CONCURRENT"

# Header-Zeile lesen und validieren
HEADER=$(head -1 "$CSV_FILE")
if [[ "$HEADER" != "name,phone,language,job_title" ]]; then
    log "ERROR" "Ungueltige CSV-Header: $HEADER"
    log "ERROR" "Erwartet: name,phone,language,job_title"
    exit 1
fi

# Leads zaehlen
TOTAL_LEADS=$(tail -n +2 "$CSV_FILE" | grep -c "." || true)
log "INFO" "Leads in CSV: $TOTAL_LEADS"

# Ergebnis-CSV Header
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "lead_id,name,phone,language,call_time,status,notes" > "$RESULTS_FILE"
fi

# -------------------------------------------------------------------------
# Dry Run
# -------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "=== DRY RUN MODE ==="
    LEAD_NUM=0
    while IFS="," read -r name phone language job_title; do
        LEAD_NUM=$((LEAD_NUM + 1))
        lead_id="lead-$(printf '%04d' $LEAD_NUM)"
        echo "[$LEAD_NUM/$TOTAL_LEADS] $lead_id | $name | $phone | $language | $job_title"
    done < <(tail -n +2 "$CSV_FILE")
    log "INFO" "DRY RUN abgeschlossen. $TOTAL_LEADS Leads gefunden."
    exit 0
fi

# -------------------------------------------------------------------------
# Bereits angerufene Leads laden (fuer --resume)
# -------------------------------------------------------------------------
declare -A CALLED_LEADS
if [[ "$RESUME" == "true" ]] && [[ -f "$STATE_FILE" ]]; then
    log "INFO" "Resume-Modus: Lade bereits angerufene Leads"
    while IFS= read -r called_id; do
        CALLED_LEADS["$called_id"]=1
    done < "$STATE_FILE"
    log "INFO" "Bereits angerufen: ${#CALLED_LEADS[@]} Leads"
fi

# -------------------------------------------------------------------------
# Kampagne starten
# -------------------------------------------------------------------------
ACTIVE_CALLS=0
CALL_COUNT=0
SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

# SIGINT/SIGTERM Handler
trap 'log "INFO" "Kampagne unterbrochen. Angerufen: $CALL_COUNT, Erfolgreich: $SUCCESS_COUNT, Fehler: $ERROR_COUNT"; exit 0' INT TERM

while IFS="," read -r name phone language job_title; do
    # Leerzeichen entfernen
    name=$(echo "$name" | xargs)
    phone=$(echo "$phone" | xargs)
    language=$(echo "$language" | xargs)
    job_title=$(echo "$job_title" | xargs)

    CALL_COUNT=$((CALL_COUNT + 1))
    lead_id="lead-$(printf '%04d' $CALL_COUNT)"

    # Skip wenn bereits angerufen (Resume-Modus)
    if [[ "${CALLED_LEADS[$lead_id]+_}" ]]; then
        log "INFO" "[$CALL_COUNT/$TOTAL_LEADS] SKIP (bereits angerufen): $name"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # Zeitfenster pruefen
    if ! check_time_window; then
        log "INFO" "Zeitfenster beendet, stoppe Kampagne"
        break
    fi

    # Concurrent-Limit abwarten
    while [[ $ACTIVE_CALLS -ge $MAX_CONCURRENT ]]; do
        sleep 5
        # Aktive Calls zaehlen
        ACTIVE_CALLS=$(asterisk -rx "core show calls" 2>/dev/null | grep -c "active call" || echo "0")
        ACTIVE_CALLS=$(echo "$ACTIVE_CALLS" | grep -oP '^\d+' || echo "0")
    done

    log "INFO" "[$CALL_COUNT/$TOTAL_LEADS] Rufe an: $name ($phone) | Sprache: $language | Job: $job_title"

    # Outbound-Call starten
    CALL_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if "$OUTBOUND_SCRIPT" \
        --number "$phone" \
        --lead-name "$name" \
        --language "$language" \
        --campaign-id "$CAMPAIGN_ID" \
        --lead-id "$lead_id" \
        --job-title "$job_title" >> "$LOG_FILE" 2>&1; then

        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo "$lead_id" >> "$STATE_FILE"
        echo "$lead_id,$name,$phone,$language,$CALL_START,initiated," >> "$RESULTS_FILE"
        log "INFO" "Call initiiert: $lead_id ($name)"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo "$lead_id,$name,$phone,$language,$CALL_START,error," >> "$RESULTS_FILE"
        log "ERROR" "Call fehlgeschlagen: $lead_id ($name, $phone)"
    fi

    # Pause zwischen Calls
    if [[ $CALL_COUNT -lt $TOTAL_LEADS ]]; then
        log "INFO" "Warte ${CALL_INTERVAL}s vor naechstem Call..."
        sleep "$CALL_INTERVAL"
    fi

done < <(tail -n +2 "$CSV_FILE")

# -------------------------------------------------------------------------
# Zusammenfassung
# -------------------------------------------------------------------------
log "INFO" "========================================"
log "INFO" "KAMPAGNE ABGESCHLOSSEN: $CAMPAIGN_ID"
log "INFO" "Gesamt:      $TOTAL_LEADS Leads"
log "INFO" "Initiiert:   $SUCCESS_COUNT"
log "INFO" "Uebersprungen: $SKIP_COUNT"
log "INFO" "Fehler:      $ERROR_COUNT"
log "INFO" "Ergebnisse:  $RESULTS_FILE"
log "INFO" "Logs:        $LOG_FILE"
log "INFO" "========================================"

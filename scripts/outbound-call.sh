#!/usr/bin/env bash
# =========================================================================
# outbound-call.sh — Einzelnen Outbound-Call via Asterisk AMI initiieren
# Verwendung: outbound-call.sh --number "+49176..." --lead-name "Max Mustermann" \
#                               --language de --campaign-id "step2job-001" \
#                               --lead-id "lead-123"
# =========================================================================
# HINWEIS: Dieses Script verwendet 'nc -q 2' (GNU netcat / netcat-traditional).
# Nur auf Linux verfuegbar. Auf macOS: 'brew install netcat' oder '-q 2' durch '-w 2' ersetzen.
# Zielumgebung: Linux-Server (Hetzner, Ubuntu/Debian).
# =========================================================================
set -euo pipefail

# -------------------------------------------------------------------------
# Konfiguration (aus .env laden wenn vorhanden)
# -------------------------------------------------------------------------
ENV_FILE="/opt/ava/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    set -a
    source "$ENV_FILE"
    set +a
fi

AMI_HOST="${ASTERISK_AMI_HOST:-127.0.0.1}"
AMI_PORT="${ASTERISK_AMI_PORT:-5038}"
AMI_USER="${ASTERISK_AMI_USER:-ava-campaign}"
AMI_PASS="${ASTERISK_AMI_PASSWORD:-campaign-secret-2024}"
SIPGATE_TRUNK="${SIPGATE_TRUNK:-SIP/sipgate}"
OUTBOUND_CONTEXT="ava-outbound"
OUTBOUND_EXTEN="s"
OUTBOUND_PRIORITY="1"
CALL_TIMEOUT="60"

# -------------------------------------------------------------------------
# Usage
# -------------------------------------------------------------------------
usage() {
    cat << EOF
Verwendung: $(basename "$0") [OPTIONEN]

Pflicht:
  --number       Rufnummer des Leads (E.164 Format: +49176...)
  --lead-name    Name des Leads

Optional:
  --language     Sprache: de (Standard) | bs | sr
  --campaign-id  Kampagnen-ID (Standard: manual)
  --lead-id      Lead-ID aus CRM (Standard: unbekannt)
  --job-title    Job-Titel fuer Gespraechskontext
  --dry-run      Befehl ausgeben ohne auszufuehren

Beispiel:
  $(basename "$0") --number "+4917612345678" --lead-name "Max Mustermann" \\
                   --language de --campaign-id "step2job-mai-2024" \\
                   --lead-id "lead-001" --job-title "Lagermitarbeiter"
EOF
    exit 1
}

# -------------------------------------------------------------------------
# Argumente parsen
# -------------------------------------------------------------------------
NUMBER=""
LEAD_NAME=""
LANGUAGE="de"
CAMPAIGN_ID="manual"
LEAD_ID="unknown"
JOB_TITLE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --number)       NUMBER="$2";      shift 2 ;;
        --lead-name)    LEAD_NAME="$2";   shift 2 ;;
        --language)     LANGUAGE="$2";    shift 2 ;;
        --campaign-id)  CAMPAIGN_ID="$2"; shift 2 ;;
        --lead-id)      LEAD_ID="$2";     shift 2 ;;
        --job-title)    JOB_TITLE="$2";   shift 2 ;;
        --dry-run)      DRY_RUN=true;     shift ;;
        --help|-h)      usage ;;
        *)              echo "Unbekannter Parameter: $1"; usage ;;
    esac
done

# Validierung
if [[ -z "$NUMBER" ]]; then
    echo "FEHLER: --number ist Pflichtfeld" >&2
    usage
fi

if [[ -z "$LEAD_NAME" ]]; then
    echo "FEHLER: --lead-name ist Pflichtfeld" >&2
    usage
fi

# Rufnummer-Format pruefen (muss mit + beginnen oder rein numerisch sein)
if [[ ! "$NUMBER" =~ ^\+?[0-9]{6,15}$ ]]; then
    echo "FEHLER: Ungueltige Rufnummer: $NUMBER (Beispiel: +4917612345678)" >&2
    exit 1
fi

# -------------------------------------------------------------------------
# Timestamp und Unique Call ID
# -------------------------------------------------------------------------
CALL_ID="call-$(date +%Y%m%d%H%M%S)-${LEAD_ID}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=== AVA Outbound Call ==="
echo "Zeit:        $TIMESTAMP"
echo "Nummer:      $NUMBER"
echo "Lead:        $LEAD_NAME ($LEAD_ID)"
echo "Sprache:     $LANGUAGE"
echo "Kampagne:    $CAMPAIGN_ID"
echo "Job:         ${JOB_TITLE:-nicht angegeben}"
echo "Call-ID:     $CALL_ID"
echo ""

# -------------------------------------------------------------------------
# AMI Originate Command via Netcat
# -------------------------------------------------------------------------
AMI_COMMAND=$(cat << EOF
Action: Login
Username: ${AMI_USER}
Secret: ${AMI_PASS}

Action: Originate
Channel: PJSIP/${NUMBER}@sipgate
Context: ${OUTBOUND_CONTEXT}
Exten: ${OUTBOUND_EXTEN}
Priority: ${OUTBOUND_PRIORITY}
Timeout: ${CALL_TIMEOUT}000
CallerID: Step2Job <+49XXXXXXXXXX>
Variable: CAMPAIGN_ID=${CAMPAIGN_ID}
Variable: LEAD_ID=${LEAD_ID}
Variable: LEAD_NAME=${LEAD_NAME}
Variable: LEAD_LANGUAGE=${LANGUAGE}
Variable: JOB_TITLE=${JOB_TITLE}
Variable: OUTBOUND_NUMBER=${NUMBER}
Variable: CALL_ID=${CALL_ID}
ActionID: ${CALL_ID}
Async: yes

Action: Logoff

EOF
)

if [[ "$DRY_RUN" == "true" ]]; then
    echo "--- DRY RUN: AMI Command ---"
    echo "$AMI_COMMAND"
    echo "--- Ende DRY RUN ---"
    exit 0
fi

# AMI Command senden
RESPONSE=$(echo "$AMI_COMMAND" | nc -q 2 "$AMI_HOST" "$AMI_PORT" 2>/dev/null || true)

# Response pruefen
if echo "$RESPONSE" | grep -q "Response: Success"; then
    echo "SUCCESS: Call initiiert (Call-ID: $CALL_ID)"
    echo "Beobachten: asterisk -rx 'channel show all'"
    exit 0
elif echo "$RESPONSE" | grep -q "Response: Error"; then
    ERROR_MSG=$(echo "$RESPONSE" | grep "Message:" | head -1 | cut -d: -f2- | xargs)
    echo "FEHLER: AMI Response Error: ${ERROR_MSG}" >&2
    exit 1
else
    echo "WARNUNG: Unbekannte AMI Response - Call moeglicherweise initiiert"
    echo "Pruefen: asterisk -rx 'core show calls'"
    exit 0
fi

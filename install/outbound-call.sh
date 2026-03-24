#!/usr/bin/env bash
# =============================================================================
# outbound-call.sh — Einzelnen Outbound-Call via AMI Originate starten
# Usage: ./outbound-call.sh <Nummer> <LeadName> [--campaign-id ID] [--language de]
# =============================================================================
set -euo pipefail

readonly AVA_ENV_FILE="/opt/ava/.env"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Defaults
PHONE_NUMBER=""
LEAD_NAME=""
CAMPAIGN_ID="manual-$(date +%Y%m%d%H%M%S)"
LEAD_LANGUAGE="de"
LEAD_ID="$(date +%s)"

usage() {
    echo "Usage: ${0} <+49...Nummer> <LeadName> [OPTIONEN]"
    echo ""
    echo "Optionen:"
    echo "  --campaign-id ID   Kampagnen-ID (Standard: manual-TIMESTAMP)"
    echo "  --language CODE    Sprache: de oder bs (Standard: de)"
    echo "  --lead-id ID       Lead-ID (Standard: UNIX-Timestamp)"
    echo "  --help             Diese Hilfe"
    echo ""
    echo "Beispiel:"
    echo "  ${0} +4917612345678 'Max Mustermann'"
    echo "  ${0} +4917612345678 'Amir Bobic' --language bs --campaign-id job-2024-q1"
    echo ""
    echo "Voraussetzungen:"
    echo "  - Datei ${AVA_ENV_FILE} muss ASTERISK_AMI_HOST, ASTERISK_AMI_PORT,"
    echo "    ASTERISK_AMI_USER, ASTERISK_AMI_PASS enthalten"
    exit 0
}

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# Argument-Parsing
if [[ $# -lt 2 ]]; then
    usage
fi

PHONE_NUMBER="$1"
LEAD_NAME="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --language)    LEAD_LANGUAGE="$2"; shift 2 ;;
        --lead-id)     LEAD_ID="$2"; shift 2 ;;
        --help|-h)     usage ;;
        *) die "Unbekanntes Argument: $1" ;;
    esac
done

# --- Validierung: E.164-Format ---
if [[ ! "${PHONE_NUMBER}" =~ ^\+[1-9][0-9]{6,14}$ ]]; then
    die "Ungueltige Nummer '${PHONE_NUMBER}'. E.164-Format erwartet, z.B. +4917612345678"
fi

# --- Sprache validieren ---
if [[ "${LEAD_LANGUAGE}" != "de" && "${LEAD_LANGUAGE}" != "bs" && "${LEAD_LANGUAGE}" != "sr" ]]; then
    warn "Unbekannte Sprache '${LEAD_LANGUAGE}' — nutze 'de'"
    LEAD_LANGUAGE="de"
fi

# --- Konfiguration aus .env laden ---
if [[ ! -f "${AVA_ENV_FILE}" ]]; then
    die ".env nicht gefunden: ${AVA_ENV_FILE}. Wurde der Installer ausgefuehrt?"
fi

# Nur benoetigte Werte laden — kein source (wuerde alle Werte in aktuelle Shell importieren)
get_env() {
    local key="$1"
    grep "^${key}=" "${AVA_ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true
}

AMI_HOST="$(get_env ASTERISK_AMI_HOST)"
AMI_PORT="$(get_env ASTERISK_AMI_PORT)"
AMI_USER="$(get_env ASTERISK_AMI_USER)"
AMI_PASS="$(get_env ASTERISK_AMI_PASS)"

AMI_HOST="${AMI_HOST:-127.0.0.1}"
AMI_PORT="${AMI_PORT:-5038}"

if [[ -z "${AMI_USER}" ]]; then
    die "ASTERISK_AMI_USER nicht in ${AVA_ENV_FILE} konfiguriert"
fi
if [[ -z "${AMI_PASS}" ]]; then
    die "ASTERISK_AMI_PASS nicht in ${AVA_ENV_FILE} konfiguriert"
fi

# --- AMI-Erreichbarkeit pruefen ---
if ! nc -z "${AMI_HOST}" "${AMI_PORT}" 2>/dev/null; then
    die "AMI nicht erreichbar auf ${AMI_HOST}:${AMI_PORT}. Laeuft Asterisk?"
fi

# --- Outbound-Call via AMI Originate ---
info "Initiiere Call zu ${PHONE_NUMBER} (${LEAD_NAME})..."
info "Kampagne: ${CAMPAIGN_ID} | Sprache: ${LEAD_LANGUAGE}"

# AMI Originate via Telnet-Protokoll
# Format: Newline-getrennte Header, doppelter Newline = Ende der Aktion
AMI_RESPONSE="$(
{
    sleep 1
    printf 'Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n' \
        "${AMI_USER}" "${AMI_PASS}"
    sleep 1
    printf 'Action: Originate\r\n'
    printf 'Channel: PJSIP/%s@sipgate\r\n' "${PHONE_NUMBER#+}"
    printf 'Context: ava-outbound\r\n'
    printf 'Exten: s\r\n'
    printf 'Priority: 1\r\n'
    printf 'CallerID: Step2Job <+4930123456>\r\n'
    printf 'Timeout: 30000\r\n'
    printf 'Variable: OUTBOUND_NUMBER=%s\r\n' "${PHONE_NUMBER}"
    printf 'Variable: LEAD_NAME=%s\r\n' "${LEAD_NAME}"
    printf 'Variable: LEAD_ID=%s\r\n' "${LEAD_ID}"
    printf 'Variable: LEAD_LANGUAGE=%s\r\n' "${LEAD_LANGUAGE}"
    printf 'Variable: CAMPAIGN_ID=%s\r\n' "${CAMPAIGN_ID}"
    printf 'Async: true\r\n'
    printf '\r\n'
    sleep 2
    printf 'Action: Logoff\r\n\r\n'
    sleep 1
} | nc -w 5 "${AMI_HOST}" "${AMI_PORT}" 2>/dev/null || true
)"

# Ergebnis auswerten
if echo "${AMI_RESPONSE}" | grep -q "Response: Success"; then
    echo ""
    echo -e "${GREEN}Call initiiert!${NC}"
    echo ""
    echo "  Nummer:     ${PHONE_NUMBER}"
    echo "  Lead:       ${LEAD_NAME}"
    echo "  Kampagne:   ${CAMPAIGN_ID}"
    echo "  Sprache:    ${LEAD_LANGUAGE}"
    echo ""
    echo "Beobachten:"
    echo "  asterisk -rx 'core show channels'"
    echo "  journalctl -u ava-voice-agent -f"
elif echo "${AMI_RESPONSE}" | grep -q "Error\|failed\|Authentication failed"; then
    ERROR_MSG="$(echo "${AMI_RESPONSE}" | grep -i "message:" | head -1 || echo 'Unbekannter Fehler')"
    die "AMI-Fehler: ${ERROR_MSG}"
else
    warn "Keine eindeutige Bestaetigung vom AMI erhalten."
    warn "Asterisk-Logs pruefen: asterisk -rx 'core show channels'"
fi

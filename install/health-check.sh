#!/usr/bin/env bash
# =============================================================================
# health-check.sh — Kompakter Health-Check fuer den AVA-Stack
# =============================================================================
set -euo pipefail

readonly AVA_ENV_FILE="/opt/ava/.env"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

PASS=0
FAIL=0
WARN=0

row() {
    local status="$1"
    local component="$2"
    local detail="$3"
    case "${status}" in
        ok)   printf "  ${GREEN}%-6s${NC} %-30s %s\n" "[OK]"   "${component}" "${detail}"; PASS=$(( PASS + 1 )) ;;
        fail) printf "  ${RED}%-6s${NC} %-30s %s\n"   "[FAIL]" "${component}" "${detail}"; FAIL=$(( FAIL + 1 )) ;;
        warn) printf "  ${YELLOW}%-6s${NC} %-30s %s\n"  "[WARN]" "${component}" "${detail}"; WARN=$(( WARN + 1 )) ;;
    esac
}

# Wert aus .env lesen ohne source
get_env() {
    local key="$1"
    grep "^${key}=" "${AVA_ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true
}

echo ""
echo -e "${CYAN}${BOLD}=== AVA Stack Health Check — $(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
echo ""
printf "  %-6s %-30s %s\n" "Status" "Komponente" "Detail"
printf "  %s\n" "------------------------------------------------------------"

# --- Services ---
if systemctl is-active --quiet asterisk 2>/dev/null; then
    UPTIME="$(systemctl show asterisk --property=ActiveEnterTimestamp --value 2>/dev/null | awk '{print $2, $3}' || echo 'n/a')"
    row ok "asterisk.service" "aktiv seit ${UPTIME}"
else
    row fail "asterisk.service" "nicht aktiv — systemctl start asterisk"
fi

if systemctl is-active --quiet ava-voice-agent 2>/dev/null; then
    LAST_LOG="$(journalctl -u ava-voice-agent -n 1 --no-pager --output=short 2>/dev/null | tail -1 | cut -c1-60 || echo 'n/a')"
    row ok "ava-voice-agent.service" "${LAST_LOG}"
else
    row fail "ava-voice-agent.service" "nicht aktiv — journalctl -u ava-voice-agent -n 30"
fi

# --- Ports ---
if ss -tlnp 2>/dev/null | grep -q ":5038 "; then
    row ok "Port 5038 (AMI)" "offen"
else
    row fail "Port 5038 (AMI)" "geschlossen — Asterisk Manager deaktiviert?"
fi

if ss -tlnp 2>/dev/null | grep -q ":8088 "; then
    row ok "Port 8088 (ARI)" "offen"
else
    row fail "Port 8088 (ARI)" "geschlossen — ari.conf pruefen"
fi

if ss -tlnp 2>/dev/null | grep -q ":9092 "; then
    row ok "Port 9092 (AudioSocket)" "offen"
else
    row warn "Port 9092 (AudioSocket)" "geschlossen — AVA gestartet?"
fi

# --- ARI HTTP ---
ARI_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:8088/ari/api-docs" 2>/dev/null || echo 000)"
if [[ "${ARI_CODE}" == "200" || "${ARI_CODE}" == "401" ]]; then
    row ok "ARI HTTP" "erreichbar (HTTP ${ARI_CODE})"
else
    row fail "ARI HTTP" "nicht erreichbar (HTTP ${ARI_CODE})"
fi

# --- OpenClaw ---
OPENCLAW_URL="$(get_env OPENCLAW_API_URL)"
if [[ -n "${OPENCLAW_URL}" ]]; then
    OC_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${OPENCLAW_URL}/models" 2>/dev/null || echo 000)"
    if [[ "${OC_CODE}" =~ ^[23] || "${OC_CODE}" == "401" ]]; then
        row ok "OpenClaw API" "erreichbar (HTTP ${OC_CODE}) — ${OPENCLAW_URL}"
    else
        row warn "OpenClaw API" "nicht erreichbar (HTTP ${OC_CODE}) — ${OPENCLAW_URL}"
    fi
else
    row warn "OpenClaw API" "OPENCLAW_API_URL nicht in .env konfiguriert"
fi

# --- Asterisk-Module ---
for module in app_audiosocket app_amd res_ari; do
    if asterisk -rx "module show like ${module}" 2>/dev/null | grep -q "Running"; then
        row ok "${module}" "Running"
    else
        row fail "${module}" "nicht geladen — asterisk -rx 'module load ${module}.so'"
    fi
done

# --- Aktive Channels ---
CHANNEL_COUNT="$(asterisk -rx 'core show channels count' 2>/dev/null | grep -oP '^\d+' || echo 0)"
row ok "Asterisk Channels" "${CHANNEL_COUNT} aktiv"

# --- SIP-Trunk Sipgate ---
SIP_REGISTERED="$(asterisk -rx 'pjsip show registrations' 2>/dev/null | grep -i sipgate | grep -i "Registered" || true)"
if [[ -n "${SIP_REGISTERED}" ]]; then
    row ok "SIP-Trunk Sipgate" "registriert"
else
    # Alternativer Check
    SIP_STATUS="$(asterisk -rx 'pjsip show contacts' 2>/dev/null | grep -i sipgate | head -1 || true)"
    if [[ -n "${SIP_STATUS}" ]]; then
        row warn "SIP-Trunk Sipgate" "Status unklar — manuell pruefen: asterisk -rx 'pjsip show contacts'"
    else
        row warn "SIP-Trunk Sipgate" "keine Sipgate-Registrierung gefunden"
    fi
fi

# --- Zusammenfassung ---
echo ""
printf "  %s\n" "------------------------------------------------------------"
printf "  ${GREEN}OK: %-3s${NC}  ${YELLOW}WARN: %-3s${NC}  ${RED}FAIL: %-3s${NC}\n" "${PASS}" "${WARN}" "${FAIL}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo -e "  ${RED}Stack nicht vollstaendig betriebsbereit.${NC}"
    exit 1
elif [[ "${WARN}" -gt 0 ]]; then
    echo -e "  ${YELLOW}Stack betriebsbereit mit Warnungen.${NC}"
else
    echo -e "  ${GREEN}Stack vollstaendig betriebsbereit.${NC}"
fi
echo ""

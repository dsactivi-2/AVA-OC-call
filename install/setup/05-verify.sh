#!/usr/bin/env bash
# =============================================================================
# 05-verify.sh — Vollstaendige Installations-Verifikation
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly AVA_DIR="/opt/ava"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

PASS=0
WARN=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; PASS=$(( PASS + 1 )); echo "$(date '+%Y-%m-%d %H:%M:%S') [VERIFY-OK] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; WARN=$(( WARN + 1 )); echo "$(date '+%Y-%m-%d %H:%M:%S') [VERIFY-WARN] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $*"; FAIL=$(( FAIL + 1 )); echo "$(date '+%Y-%m-%d %H:%M:%S') [VERIFY-FAIL] $*" >> "${LOG_FILE}" 2>/dev/null || true; }

check_service() {
    local name="$1"
    if systemctl is-active --quiet "${name}" 2>/dev/null; then
        ok "Service aktiv: ${name}"
    else
        fail "Service nicht aktiv: ${name} — pruefen mit: journalctl -u ${name} -n 20"
    fi
}

check_port() {
    local port="$1"
    local desc="$2"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        ok "Port ${port} (${desc}): offen"
    else
        fail "Port ${port} (${desc}): nicht erreichbar"
    fi
}

check_http() {
    local url="$1"
    local desc="$2"
    local http_code
    http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${url}" 2>/dev/null || echo 000)"
    if [[ "${http_code}" =~ ^[23] ]]; then
        ok "HTTP ${desc}: erreichbar (HTTP ${http_code})"
    elif [[ "${http_code}" == "401" ]]; then
        ok "HTTP ${desc}: erreichbar (HTTP 401 — Auth erforderlich, das ist korrekt)"
    else
        fail "HTTP ${desc}: nicht erreichbar (HTTP ${http_code}) — URL: ${url}"
    fi
}

echo ""
echo "========================================"
echo "  Installations-Verifikation"
echo "========================================"
echo ""

# --- Services ---
echo "Services:"
check_service "asterisk"
check_service "ava-voice-agent"

# --- Ports ---
echo ""
echo "Ports:"
check_port 5038 "AMI"
check_port 8088 "ARI"
check_port 9092 "AudioSocket"

# --- HTTP-Endpunkte ---
echo ""
echo "HTTP-Endpunkte:"
check_http "http://127.0.0.1:8088/ari/api-docs" "ARI"

# OpenClaw — URL aus .env lesen
OPENCLAW_URL=""
if [[ -f "${AVA_DIR}/.env" ]]; then
    OPENCLAW_URL="$(grep '^OPENCLAW_API_URL=' "${AVA_DIR}/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
fi
if [[ -n "${OPENCLAW_URL}" ]]; then
    check_http "${OPENCLAW_URL}/models" "OpenClaw /v1/models"
else
    warn "OpenClaw URL nicht konfiguriert — .env pruefen"
fi

# --- Asterisk-Module ---
echo ""
echo "Asterisk-Module:"

check_asterisk_module() {
    local module="$1"
    if asterisk -rx "module show like ${module}" 2>/dev/null | grep -q "Running"; then
        ok "Asterisk-Modul: ${module} (Running)"
    else
        fail "Asterisk-Modul: ${module} nicht geladen — asterisk -rx 'module load ${module}.so'"
    fi
}

check_asterisk_module "app_audiosocket"
check_asterisk_module "res_ari"
check_asterisk_module "app_amd"

# --- Dialplan ---
echo ""
echo "Dialplan:"
if asterisk -rx "dialplan show ava-outbound" 2>/dev/null | grep -q "ava-outbound"; then
    ok "Dialplan: [ava-outbound] vorhanden"
else
    fail "Dialplan: [ava-outbound] nicht gefunden — extensions.conf reload pruefen"
fi

if asterisk -rx "dialplan show ava-inbound" 2>/dev/null | grep -q "ava-inbound"; then
    ok "Dialplan: [ava-inbound] vorhanden"
else
    warn "Dialplan: [ava-inbound] nicht gefunden"
fi

# --- Dateien ---
echo ""
echo "Dateien:"
for f in "${AVA_DIR}/.env" "${AVA_DIR}/config.yaml" "/etc/asterisk/ari.conf" "/etc/asterisk/amd.conf"; do
    if [[ -f "${f}" ]]; then
        ok "Datei: ${f}"
    else
        fail "Datei fehlt: ${f}"
    fi
done

# .env auf Pflichtfelder pruefen
if [[ -f "${AVA_DIR}/.env" ]]; then
    for key in OPENCLAW_API_URL ASTERISK_ARI_USER ASTERISK_AMI_USER; do
        if grep -q "^${key}=" "${AVA_DIR}/.env" 2>/dev/null; then
            ok ".env: ${key} gesetzt"
        else
            warn ".env: ${key} fehlt"
        fi
    done
fi

# --- AVA-Logs ---
echo ""
echo "AVA-Logs:"
if [[ -f "/var/log/ava/agent.log" ]]; then
    LAST_LINE="$(tail -1 /var/log/ava/agent.log 2>/dev/null || true)"
    ok "Log-Datei: /var/log/ava/agent.log (letzter Eintrag: ${LAST_LINE:0:80})"
else
    warn "Log-Datei /var/log/ava/agent.log noch nicht vorhanden (normal nach Erstinstallation)"
fi

# --- Ergebnis-Zusammenfassung ---
echo ""
echo "========================================"
echo "  Ergebnis"
echo "========================================"
echo -e "  ${GREEN}OK:${NC}   ${PASS}"
echo -e "  ${YELLOW}WARN:${NC} ${WARN}"
echo -e "  ${RED}FAIL:${NC} ${FAIL}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo -e "${RED}Verifikation nicht bestanden: ${FAIL} Fehler.${NC}"
    echo "Log: ${LOG_FILE}"
    exit 1
elif [[ "${WARN}" -gt 0 ]]; then
    echo -e "${YELLOW}Verifikation mit Warnungen abgeschlossen.${NC}"
    echo "System ist betriebsbereit, aber einige Punkte sollten geprueft werden."
else
    echo -e "${GREEN}Alle Checks bestanden. System ist bereit.${NC}"
fi

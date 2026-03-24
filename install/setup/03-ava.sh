#!/usr/bin/env bash
# =============================================================================
# 03-ava.sh — AVA AI Voice Agent installieren und konfigurieren
# Erwartet folgende ENV-Variablen (gesetzt von install.sh collect_credentials):
#   AVA_ARI_SECRET, AVA_AMI_SECRET, AVA_OPENCLAW_URL, AVA_OPENCLAW_MODEL
#   AVA_ELEVENLABS_KEY, AVA_DEEPGRAM_KEY, AVA_AZURE_KEY, AVA_AZURE_REGION
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly AVA_DIR="/opt/ava"
readonly AVA_REPO="https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk.git"
readonly AVA_USER="ava"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AVA_CONFIGS_SRC="$(cd "${SCRIPT_DIR}/../../ava-configs" && pwd)"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [AVA] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo "=== AVA AI Voice Agent installieren ==="
echo ""

# Sicherstellen dass python3.11 vorhanden ist
if ! command -v python3.11 &>/dev/null; then
    die "python3.11 nicht gefunden. Zuerst 01-system.sh ausfuehren."
fi

# --- System-User 'ava' anlegen (idempotent) ---
if id "${AVA_USER}" &>/dev/null; then
    log_ok "System-User '${AVA_USER}': bereits vorhanden"
else
    log_info "System-User '${AVA_USER}' anlegen..."
    useradd --system --shell /bin/false --home-dir "${AVA_DIR}" --create-home "${AVA_USER}"
    log_ok "System-User '${AVA_USER}': angelegt"
fi

# --- AVA-Repository klonen oder aktualisieren ---
if [[ -d "${AVA_DIR}/.git" ]]; then
    log_info "AVA-Repository bereits vorhanden — aktualisiere..."
    git -C "${AVA_DIR}" pull --ff-only 2>/dev/null && log_ok "git pull: OK" || log_warn "git pull fehlgeschlagen — manuell pruefen"
else
    log_info "Klone AVA-Repository..."
    git clone --depth=1 "${AVA_REPO}" "${AVA_DIR}" || die "git clone fehlgeschlagen: ${AVA_REPO}"
    log_ok "Repository geklont nach: ${AVA_DIR}"
fi

# Basis-Struktur pruefen
if [[ ! -f "${AVA_DIR}/requirements.txt" ]]; then
    log_warn "requirements.txt nicht gefunden — Repository-Struktur hat sich moeglicherweise geaendert"
    log_warn "Manuell pruefen: ls ${AVA_DIR}/"
fi

# --- Python venv anlegen ---
log_info "Python Virtual Environment anlegen..."
if [[ -d "${AVA_DIR}/venv" ]]; then
    log_ok "venv: bereits vorhanden"
else
    python3.11 -m venv "${AVA_DIR}/venv"
    log_ok "venv: angelegt"
fi

# --- Dependencies installieren ---
log_info "Python-Dependencies installieren..."
"${AVA_DIR}/venv/bin/pip" install --upgrade pip -q
if [[ -f "${AVA_DIR}/requirements.txt" ]]; then
    "${AVA_DIR}/venv/bin/pip" install -r "${AVA_DIR}/requirements.txt" -q
    log_ok "requirements.txt: installiert"
else
    log_warn "requirements.txt fehlt — Dependencies nicht installiert"
fi

# Basis-Imports testen
if "${AVA_DIR}/venv/bin/python" -c "import asyncio; import aiohttp" 2>/dev/null; then
    log_ok "Python-Imports: asyncio, aiohttp OK"
else
    log_warn "Python-Imports fehlgeschlagen — Dependencies pruefen"
fi

# --- config.yaml deployen ---
log_info "AVA config.yaml deployen..."
if [[ ! -d "${AVA_DIR}/config" ]]; then
    mkdir -p "${AVA_DIR}/config"
fi

if [[ -f "${AVA_CONFIGS_SRC}/config.yaml" ]]; then
    if [[ -f "${AVA_DIR}/config/ai-agent.yaml" ]]; then
        cp "${AVA_DIR}/config/ai-agent.yaml" "${AVA_DIR}/config/ai-agent.yaml.bak.$(date +%Y%m%d)"
        log_info "Backup: config/ai-agent.yaml"
    fi
    cp "${AVA_CONFIGS_SRC}/config.yaml" "${AVA_DIR}/config/ai-agent.yaml"
    log_ok "config/ai-agent.yaml: deployed"

    # Auch als config.yaml im Wurzelverzeichnis ablegen (fuer direkten Start)
    cp "${AVA_CONFIGS_SRC}/config.yaml" "${AVA_DIR}/config.yaml"
    log_ok "config.yaml: deployed"
else
    log_warn "Blueprint config.yaml nicht gefunden: ${AVA_CONFIGS_SRC}/config.yaml"
fi

# --- .env-Datei schreiben (aus ENV-Variablen, kein Plaintext im Script) ---
log_info ".env-Datei schreiben..."
ENV_FILE="${AVA_DIR}/.env"

# Backup falls bereits vorhanden
if [[ -f "${ENV_FILE}" ]]; then
    cp "${ENV_FILE}" "${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup: .env"
fi

# ENV-Werte aus dem Installer uebernehmen (werden via export uebergeben)
# Fehlende Werte als Leerstring belassen — spaeter manuell befuellbar
{
    echo "# AVA AI Voice Agent — Konfiguration"
    echo "# Generiert: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# NIEMALS in Git committen!"
    echo ""
    echo "# OpenClaw LLM Backend"
    echo "OPENCLAW_API_URL=${AVA_OPENCLAW_URL:-http://127.0.0.1:18789/v1}"
    echo "OPENCLAW_MODEL=${AVA_OPENCLAW_MODEL:-ava}"
    echo "OPENCLAW_API_KEY="
    echo ""
    echo "# Asterisk ARI"
    echo "ASTERISK_ARI_URL=http://127.0.0.1:8088"
    echo "ASTERISK_ARI_USER=ava-bot"
    # Secret-Wert aus ENV — wird nicht als Literal ins Script geschrieben
    printf 'ASTERISK_ARI_PASS=%s\n' "${AVA_ARI_SECRET:-}"
    echo ""
    echo "# Asterisk AMI"
    echo "ASTERISK_AMI_HOST=127.0.0.1"
    echo "ASTERISK_AMI_PORT=5038"
    echo "ASTERISK_AMI_USER=ava-campaign"
    printf 'ASTERISK_AMI_PASS=%s\n' "${AVA_AMI_SECRET:-}"
    echo ""
    echo "# Speech-to-Text"
    echo "DEEPGRAM_API_KEY=${AVA_DEEPGRAM_KEY:-}"
    echo ""
    echo "# Text-to-Speech"
    echo "ELEVENLABS_API_KEY=${AVA_ELEVENLABS_KEY:-}"
    echo "AZURE_SPEECH_KEY=${AVA_AZURE_KEY:-}"
    echo "AZURE_SPEECH_REGION=${AVA_AZURE_REGION:-westeurope}"
    echo ""
    echo "# Kampagne"
    echo "CAMPAIGN_CALL_INTERVAL=30"
    echo "CAMPAIGN_MAX_CONCURRENT=5"
    echo "CAMPAIGN_RETRY_HOURS=2"
    echo "CAMPAIGN_MAX_RETRIES=3"
    echo ""
    echo "# Logging"
    echo "LOG_LEVEL=INFO"
    echo "LOG_FILE=/var/log/ava/agent.log"
} > "${ENV_FILE}"

chmod 600 "${ENV_FILE}"
chown "${AVA_USER}:${AVA_USER}" "${ENV_FILE}" 2>/dev/null || true
log_ok ".env: geschrieben (Zugangsdaten gesetzt)"

# --- Verzeichnis-Berechtigungen ---
log_info "Verzeichnis-Berechtigungen setzen..."
chown -R "${AVA_USER}:${AVA_USER}" "${AVA_DIR}"
chmod 750 "${AVA_DIR}"
log_ok "Berechtigungen: ${AVA_DIR} gehoert '${AVA_USER}'"

# --- main.py suchen ---
if [[ -f "${AVA_DIR}/main.py" ]]; then
    log_ok "main.py: gefunden"
else
    log_warn "main.py nicht gefunden — Einstiegspunkt koennte abweichen"
    log_warn "Tatsaechliche Struktur: $(ls "${AVA_DIR}/" 2>/dev/null | tr '\n' ' ')"
fi

echo ""
echo -e "${GREEN}AVA AI Voice Agent erfolgreich installiert.${NC}"
echo "Installation: ${AVA_DIR}"
echo "Konfiguration: ${AVA_DIR}/config.yaml"
echo "Env-Datei: ${AVA_DIR}/.env"

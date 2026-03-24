#!/usr/bin/env bash
# =============================================================================
# 02-asterisk.sh — Asterisk-Konfiguration deployen
# Kopiert Blueprint-Configs, sichert Originals, laedt Asterisk neu
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIGS_SRC="$(cd "${SCRIPT_DIR}/../../asterisk-configs" && pwd)"
readonly ASTERISK_CONF_DIR="/etc/asterisk"
readonly BACKUP_DIR="/etc/asterisk/backups/$(date '+%Y%m%d_%H%M%S')"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [ASTERISK] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo "=== Asterisk konfigurieren ==="
echo ""

# Pruefen ob Asterisk laeuft
if ! command -v asterisk &>/dev/null; then
    die "Asterisk nicht gefunden. Zuerst 01-system.sh ausfuehren."
fi

# Blueprint-Quell-Verzeichnis pruefen
if [[ ! -d "${CONFIGS_SRC}" ]]; then
    die "Blueprint-Verzeichnis nicht gefunden: ${CONFIGS_SRC}"
fi

# Backup-Verzeichnis erstellen
log_info "Backup existierender Configs nach: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# --- Hilfsfunktion: Config deployen ---
deploy_config() {
    local filename="$1"
    local src="${CONFIGS_SRC}/${filename}"
    local dst="${ASTERISK_CONF_DIR}/${filename}"

    if [[ ! -f "${src}" ]]; then
        die "Blueprint-Datei fehlt: ${src}"
    fi

    # Backup nur wenn Original existiert
    if [[ -f "${dst}" ]]; then
        cp "${dst}" "${BACKUP_DIR}/${filename}.bak"
        log_info "Backup: ${filename} → ${BACKUP_DIR}/${filename}.bak"
    fi

    cp "${src}" "${dst}"
    chmod 640 "${dst}"
    chown root:asterisk "${dst}" 2>/dev/null || chown root:root "${dst}"
    log_ok "Deployed: ${filename}"
}

# --- ari.conf: ARI-Endpunkt fuer AVA ---
log_info "--- ari.conf ---"
deploy_config "ari.conf"

# Sicherstellen dass [general] enabled = yes gesetzt ist
if ! grep -q "^enabled *= *yes" "${ASTERISK_CONF_DIR}/ari.conf"; then
    log_warn "ari.conf: 'enabled = yes' nicht gefunden — manuell pruefen"
fi

# --- extensions.conf: AVA-Contexts ergaenzen ---
log_info "--- extensions.conf ---"
if [[ -f "${ASTERISK_CONF_DIR}/extensions.conf" ]]; then
    # Backup
    cp "${ASTERISK_CONF_DIR}/extensions.conf" "${BACKUP_DIR}/extensions.conf.bak"
    log_info "Backup: extensions.conf"

    # AVA-Contexts nur ergaenzen wenn noch nicht vorhanden
    if grep -q "\[ava-outbound\]" "${ASTERISK_CONF_DIR}/extensions.conf"; then
        log_ok "extensions.conf: [ava-outbound] bereits vorhanden — ueberspringe"
    else
        echo "" >> "${ASTERISK_CONF_DIR}/extensions.conf"
        echo "; === AVA AI Callcenter Contexts (automatisch ergaenzt) ===" >> "${ASTERISK_CONF_DIR}/extensions.conf"
        cat "${CONFIGS_SRC}/extensions.conf" >> "${ASTERISK_CONF_DIR}/extensions.conf"
        log_ok "extensions.conf: AVA-Contexts ergaenzt"
    fi
else
    # Keine extensions.conf vorhanden — neue anlegen
    cp "${CONFIGS_SRC}/extensions.conf" "${ASTERISK_CONF_DIR}/extensions.conf"
    chmod 640 "${ASTERISK_CONF_DIR}/extensions.conf"
    log_ok "extensions.conf: neu angelegt"
fi

# --- amd.conf: Answering Machine Detection ---
log_info "--- amd.conf ---"
deploy_config "amd.conf"

# --- manager.conf: AMI-User ergaenzen ---
log_info "--- manager.conf ---"
if [[ -f "${ASTERISK_CONF_DIR}/manager.conf" ]]; then
    # Backup
    cp "${ASTERISK_CONF_DIR}/manager.conf" "${BACKUP_DIR}/manager.conf.bak"
    log_info "Backup: manager.conf"

    # AMI global aktivieren wenn noch nicht vorhanden
    if ! grep -q "^\[general\]" "${ASTERISK_CONF_DIR}/manager.conf"; then
        cat >> "${ASTERISK_CONF_DIR}/manager.conf" << 'GENERAL_SECTION'

[general]
enabled = yes
port = 5038
bindaddr = 127.0.0.1
GENERAL_SECTION
        log_ok "manager.conf: [general] Sektion ergaenzt"
    fi

    # AVA-User nur ergaenzen wenn noch nicht vorhanden
    if grep -q "\[ava-campaign\]" "${ASTERISK_CONF_DIR}/manager.conf"; then
        log_ok "manager.conf: [ava-campaign] bereits vorhanden — ueberspringe"
    else
        echo "" >> "${ASTERISK_CONF_DIR}/manager.conf"
        echo "; === AVA AMI-User (automatisch ergaenzt) ===" >> "${ASTERISK_CONF_DIR}/manager.conf"
        cat "${CONFIGS_SRC}/manager.conf" >> "${ASTERISK_CONF_DIR}/manager.conf"
        log_ok "manager.conf: AVA-User ergaenzt"
    fi
else
    cp "${CONFIGS_SRC}/manager.conf" "${ASTERISK_CONF_DIR}/manager.conf"
    chmod 640 "${ASTERISK_CONF_DIR}/manager.conf"
    log_ok "manager.conf: neu angelegt"
fi

# --- Asterisk-Module pruefen und laden ---
echo ""
log_info "--- Asterisk-Module pruefen ---"

# Asterisk starten falls nicht aktiv
if ! systemctl is-active --quiet asterisk 2>/dev/null; then
    log_info "Asterisk wird gestartet..."
    systemctl start asterisk
    sleep 3
fi

check_module() {
    local module="$1"
    local result
    result="$(asterisk -rx "module show like ${module}" 2>/dev/null || echo "")"
    if echo "${result}" | grep -q "Running"; then
        log_ok "Modul geladen: ${module}"
    else
        log_warn "Modul nicht geladen: ${module} — lade nach..."
        asterisk -rx "module load ${module}.so" 2>/dev/null || log_warn "${module}: Laden fehlgeschlagen — manuell pruefen"
    fi
}

check_module "app_audiosocket"
check_module "res_ari"
check_module "app_amd"

# --- Konfiguration neu laden ---
echo ""
log_info "Asterisk Konfiguration neu laden..."
asterisk -rx "core reload" 2>/dev/null && log_ok "core reload: OK"
sleep 2

# --- ARI-Erreichbarkeit pruefen ---
log_info "ARI-Erreichbarkeit pruefen (Port 8088)..."
if curl -sf --max-time 5 "http://127.0.0.1:8088/ari/api-docs" > /dev/null 2>&1; then
    log_ok "ARI: erreichbar auf Port 8088"
else
    log_warn "ARI: nicht erreichbar — eventuell noch startend. Nach AVA-Installation erneut pruefen."
fi

# --- Dialplan pruefen ---
log_info "Dialplan pruefen..."
if asterisk -rx "dialplan show ava-outbound" 2>/dev/null | grep -q "ava-outbound"; then
    log_ok "Dialplan: [ava-outbound] Context gefunden"
else
    log_warn "Dialplan: [ava-outbound] nicht gefunden — Reload abwarten oder manuell pruefen"
fi

echo ""
echo -e "${GREEN}Asterisk-Konfiguration abgeschlossen.${NC}"
echo "Backup-Verzeichnis: ${BACKUP_DIR}"

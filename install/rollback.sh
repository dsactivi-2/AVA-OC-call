#!/usr/bin/env bash
# =============================================================================
# rollback.sh — AVA-Stack vollstaendig zuruecksetzen
# Stoppt Services, stellt Backup-Configs wieder her, entfernt AVA
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly AVA_DIR="/opt/ava"
readonly AVA_USER="ava"
readonly SERVICE_NAME="ava-voice-agent"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly ASTERISK_CONF_DIR="/etc/asterisk"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

DRY_RUN=false
FORCE=false

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [ROLLBACK] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

run() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        eval "$@"
    fi
}

# Argument-Parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --help|-h)
            echo "Usage: ${0} [--dry-run] [--force]"
            echo ""
            echo "  --dry-run   Nur anzeigen was zurueckgesetzt wuerde"
            echo "  --force     Ohne Bestaetigung ausfuehren"
            exit 0
            ;;
        *) die "Unbekanntes Argument: $1" ;;
    esac
    shift
done

echo -e "${RED}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              AVA-Stack ROLLBACK                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Folgendes wird entfernt/zurueckgesetzt:"
echo "  - Service: ${SERVICE_NAME}"
echo "  - Verzeichnis: ${AVA_DIR}"
echo "  - Systemd-Unit: ${SERVICE_FILE}"
echo "  - Asterisk-Configs: aus letztem Backup wiederhergestellt"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "DRY-RUN Modus — keine Aenderungen"
fi

if [[ "${FORCE}" == "false" && "${DRY_RUN}" == "false" ]]; then
    read -rp "Wirklich zuruecksetzen? [ja/NEIN]: " confirm
    if [[ "${confirm}" != "ja" ]]; then
        echo "Abgebrochen."
        exit 0
    fi
fi

# --- 1. AVA-Service stoppen und deaktivieren ---
log_info "AVA-Service stoppen..."
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    run systemctl stop "${SERVICE_NAME}"
    log_ok "Service gestoppt: ${SERVICE_NAME}"
else
    log_warn "Service war nicht aktiv: ${SERVICE_NAME}"
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    run systemctl disable "${SERVICE_NAME}"
    log_ok "Service deaktiviert: ${SERVICE_NAME}"
fi

# --- 2. Service-Datei entfernen ---
if [[ -f "${SERVICE_FILE}" ]]; then
    run rm -f "${SERVICE_FILE}"
    log_ok "Service-Datei entfernt: ${SERVICE_FILE}"
fi

run systemctl daemon-reload

# --- 3. Asterisk-Configs aus Backup wiederherstellen ---
log_info "Suche neuestes Backup..."
LATEST_BACKUP="$(ls -dt "${ASTERISK_CONF_DIR}/backups/"*/ 2>/dev/null | head -1 || true)"

if [[ -n "${LATEST_BACKUP}" ]]; then
    log_info "Backup gefunden: ${LATEST_BACKUP}"
    for bakfile in "${LATEST_BACKUP}"*.bak; do
        if [[ -f "${bakfile}" ]]; then
            original="${ASTERISK_CONF_DIR}/$(basename "${bakfile}" .bak)"
            run cp "${bakfile}" "${original}"
            log_ok "Wiederhergestellt: ${original}"
        fi
    done

    # Asterisk neu laden nach Wiederherstellung
    if systemctl is-active --quiet asterisk 2>/dev/null; then
        run asterisk -rx "core reload"
        log_ok "Asterisk neu geladen"
    fi
else
    log_warn "Kein Backup-Verzeichnis gefunden: ${ASTERISK_CONF_DIR}/backups/"
    log_warn "Asterisk-Configs manuell pruefen"
fi

# --- 4. AVA-Verzeichnis entfernen ---
if [[ -d "${AVA_DIR}" ]]; then
    run rm -rf "${AVA_DIR}"
    log_ok "Verzeichnis entfernt: ${AVA_DIR}"
else
    log_warn "Verzeichnis nicht vorhanden: ${AVA_DIR}"
fi

# --- 5. AVA-Log-Verzeichnis entfernen (optional) ---
if [[ -d "/var/log/ava" ]]; then
    log_info "AVA-Logs unter /var/log/ava bleiben erhalten (manuell entfernen: rm -rf /var/log/ava)"
fi

# --- 6. System-User entfernen (optional) ---
if id "${AVA_USER}" &>/dev/null; then
    log_info "System-User '${AVA_USER}' bleibt erhalten (manuell entfernen: userdel ${AVA_USER})"
fi

# --- 7. Verifikation ---
echo ""
echo "=== Verifikation ==="
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    log_warn "Service laeuft noch: ${SERVICE_NAME}"
else
    log_ok "Service nicht aktiv: ${SERVICE_NAME}"
fi

if [[ -d "${AVA_DIR}" ]]; then
    log_warn "Verzeichnis noch vorhanden: ${AVA_DIR}"
else
    log_ok "Verzeichnis entfernt: ${AVA_DIR}"
fi

if [[ -f "${SERVICE_FILE}" ]]; then
    log_warn "Service-Datei noch vorhanden: ${SERVICE_FILE}"
else
    log_ok "Service-Datei entfernt: ${SERVICE_FILE}"
fi

echo ""
echo -e "${GREEN}Rollback abgeschlossen.${NC}"
echo "Asterisk laeuft weiterhin (nur AVA entfernt)."

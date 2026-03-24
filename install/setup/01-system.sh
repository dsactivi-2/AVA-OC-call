#!/usr/bin/env bash
# =============================================================================
# 01-system.sh — System-Pakete installieren
# Asterisk, Python 3.11, git, uuid-runtime, netcat-traditional, jq
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [SYS] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo "=== System-Pakete installieren ==="
echo ""

# Idempotenz: Pruefen ob Paket bereits installiert
pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

# Paket installieren (idempotent)
install_pkg() {
    local pkg="$1"
    if pkg_installed "${pkg}"; then
        log_ok "${pkg}: bereits installiert"
    else
        log_info "Installiere: ${pkg}"
        apt-get install -y --no-install-recommends "${pkg}"
        log_ok "${pkg}: installiert"
    fi
}

# --- apt aktualisieren ---
log_info "apt update..."
apt-get update -qq

# --- Asterisk ---
echo ""
log_info "--- Asterisk ---"
install_pkg "asterisk"
install_pkg "asterisk-modules"

# Asterisk-Version pruefen
ASTERISK_VERSION="$(asterisk -V 2>/dev/null | awk '{print $2}' || echo 'unbekannt')"
log_ok "Asterisk Version: ${ASTERISK_VERSION}"

# Mindest-Version pruefen (>= 18)
MAJOR_VERSION="$(echo "${ASTERISK_VERSION}" | cut -d'.' -f1)"
if [[ "${MAJOR_VERSION}" -lt 18 ]]; then
    die "Asterisk ${ASTERISK_VERSION} zu alt — benoetigt >= 18.x"
fi

# --- uuid-runtime (fuer uuidgen im Dialplan) ---
echo ""
log_info "--- uuid-runtime ---"
install_pkg "uuid-runtime"
UUIDGEN_OK="$(uuidgen | grep -cE '^[0-9a-f-]{36}$' || echo 0)"
if [[ "${UUIDGEN_OK}" -eq 1 ]]; then
    log_ok "uuidgen: funktioniert"
else
    die "uuidgen gibt kein gueltiges UUID-Format aus"
fi

# --- Python 3.11 ---
echo ""
log_info "--- Python 3.11 ---"
install_pkg "python3.11"
install_pkg "python3.11-venv"
install_pkg "python3-pip"
install_pkg "python3-venv"

PYTHON_VERSION="$(python3.11 --version 2>&1 | awk '{print $2}')"
log_ok "Python Version: ${PYTHON_VERSION}"

# --- Weitere Tools ---
echo ""
log_info "--- Werkzeuge ---"
install_pkg "git"
install_pkg "curl"
install_pkg "jq"

# netcat-traditional (fuer Port-Tests in health-check.sh)
if ! pkg_installed "netcat-traditional" && ! pkg_installed "netcat-openbsd"; then
    install_pkg "netcat-traditional"
else
    log_ok "netcat: bereits vorhanden"
fi

# --- Verzeichnisse anlegen ---
echo ""
log_info "Verzeichnisse anlegen..."
mkdir -p /var/log/ava
mkdir -p /var/lib/asterisk/sounds/ava
mkdir -p /var/log/asterisk/recordings
chmod 755 /var/log/ava
chown -R asterisk:asterisk /var/log/asterisk/recordings 2>/dev/null || true
log_ok "Verzeichnisse: OK"

echo ""
echo -e "${GREEN}System-Pakete erfolgreich installiert.${NC}"

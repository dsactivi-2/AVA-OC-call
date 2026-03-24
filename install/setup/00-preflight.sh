#!/usr/bin/env bash
# =============================================================================
# 00-preflight.sh — System-Voraussetzungen pruefen
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

PREFLIGHT_ERRORS=0

log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [PREFLIGHT-OK] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [PREFLIGHT-WARN] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [PREFLIGHT-FAIL] $*" >> "${LOG_FILE}" 2>/dev/null || true; PREFLIGHT_ERRORS=$(( PREFLIGHT_ERRORS + 1 )); }

echo ""
echo "=== Preflight-Checks ==="
echo ""

# --- 1. OS-Check ---
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_fail "Kein /etc/os-release gefunden — unbekanntes OS"
        return
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    local os_id="${ID:-unknown}"
    local os_version="${VERSION_ID:-0}"

    case "${os_id}" in
        ubuntu)
            # Major-Version extrahieren
            local major
            major="${os_version%%.*}"
            if [[ "${major}" -ge 22 ]]; then
                log_ok "OS: Ubuntu ${os_version} (unterstuetzt)"
            else
                log_fail "OS: Ubuntu ${os_version} — benoetigt >= 22.04"
            fi
            ;;
        debian)
            local major
            major="${os_version%%.*}"
            if [[ "${major}" -ge 12 ]]; then
                log_ok "OS: Debian ${os_version} (unterstuetzt)"
            else
                log_fail "OS: Debian ${os_version} — benoetigt >= 12"
            fi
            ;;
        *)
            log_warn "OS: ${os_id} ${os_version} — nicht offiziell unterstuetzt. Installation auf eigenes Risiko."
            ;;
    esac
}

# --- 2. Root/Sudo-Check ---
check_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_ok "Berechtigungen: Root"
    elif sudo -n true 2>/dev/null; then
        log_ok "Berechtigungen: sudo (passwortlos verfuegbar)"
    else
        log_fail "Berechtigungen: Root oder sudo erforderlich. Starte mit: sudo ${0}"
    fi
}

# --- 3. RAM-Check (mindestens 2 GB frei) ---
check_ram() {
    local mem_free_kb
    mem_free_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    local mem_free_mb=$(( mem_free_kb / 1024 ))
    if [[ "${mem_free_mb}" -ge 2048 ]]; then
        log_ok "RAM: ${mem_free_mb} MB frei (>= 2048 MB benoetigt)"
    elif [[ "${mem_free_mb}" -ge 1024 ]]; then
        log_warn "RAM: ${mem_free_mb} MB frei — empfohlen sind 2048 MB. Eventuell Probleme mit Whisper."
    else
        log_fail "RAM: ${mem_free_mb} MB frei — mindestens 2048 MB benoetigt"
    fi
}

# --- 4. Disk-Check (mindestens 5 GB frei auf /opt) ---
check_disk() {
    local disk_free_kb
    disk_free_kb="$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
    local disk_free_gb=$(( disk_free_kb / 1024 / 1024 ))
    if [[ "${disk_free_gb}" -ge 5 ]]; then
        log_ok "Disk: ${disk_free_gb} GB frei auf /opt (>= 5 GB benoetigt)"
    else
        log_fail "Disk: ${disk_free_gb} GB frei auf /opt — mindestens 5 GB benoetigt"
    fi
}

# --- 5. Netzwerk-Check ---
check_network() {
    # apt-Repository erreichbar?
    if curl -sf --max-time 5 "http://archive.ubuntu.com/" > /dev/null 2>&1 \
    || curl -sf --max-time 5 "http://deb.debian.org/" > /dev/null 2>&1; then
        log_ok "Netzwerk: apt-Repository erreichbar"
    else
        log_warn "Netzwerk: apt-Repository nicht erreichbar — offline-Installation moeglicherweise nicht moeglich"
    fi

    # GitHub erreichbar?
    if curl -sf --max-time 5 "https://github.com" > /dev/null 2>&1; then
        log_ok "Netzwerk: GitHub erreichbar"
    else
        log_fail "Netzwerk: GitHub nicht erreichbar — AVA-Repository kann nicht geklont werden"
    fi
}

# --- 6. Port-Check (Ports muessen frei sein) ---
check_ports() {
    local ports=(5038 8088 9092 5060)
    local names=("AMI" "ARI" "AudioSocket" "SIP")

    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local name="${names[$i]}"
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            log_warn "Port ${port} (${name}): bereits belegt — pruefen ob anderer Dienst laeuft"
        else
            log_ok "Port ${port} (${name}): frei"
        fi
    done
}

# --- 7. Pflicht-Kommandos ---
check_commands() {
    local cmds=(curl git python3 systemctl)
    for cmd in "${cmds[@]}"; do
        if command -v "${cmd}" &>/dev/null; then
            log_ok "Kommando verfuegbar: ${cmd}"
        else
            log_warn "Kommando fehlt: ${cmd} — wird spaeter installiert"
        fi
    done
}

# --- Checks ausfuehren ---
check_os
check_root
check_ram
check_disk
check_network
check_ports
check_commands

echo ""
if [[ "${PREFLIGHT_ERRORS}" -gt 0 ]]; then
    echo -e "${RED}Preflight fehlgeschlagen: ${PREFLIGHT_ERRORS} kritische(r) Fehler.${NC}"
    echo "Bitte die Fehler beheben und erneut starten."
    exit 1
else
    echo -e "${GREEN}Alle Preflight-Checks bestanden.${NC}"
fi

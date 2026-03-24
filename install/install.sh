#!/usr/bin/env bash
# =============================================================================
# install.sh — AVA + Asterisk + OpenClaw 1-Click Installer
# Zielumgebung: Ubuntu 22.04/24.04 LTS oder Debian 12
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Konstanten
# -----------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/ava-install.log"
readonly AVA_DIR="/opt/ava"
readonly AVA_REPO="https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk.git"
readonly AVA_USER="ava"
readonly ASTERISK_CONFIGS_SRC="${SCRIPT_DIR}/../asterisk-configs"
readonly AVA_CONFIGS_SRC="${SCRIPT_DIR}/../ava-configs"

# Farben
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Flags (Defaults)
DRY_RUN=false
SKIP_ASTERISK=false
SHOW_HELP=false

# Credential-Slots (werden nur im Speicher gehalten, nie geloggt)
AVA_ARI_SECRET=""
AVA_AMI_SECRET=""
AVA_OPENCLAW_URL=""
AVA_OPENCLAW_MODEL=""
AVA_ELEVENLABS_KEY=""
AVA_DEEPGRAM_KEY=""
AVA_AZURE_KEY=""
AVA_AZURE_REGION=""

# -----------------------------------------------------------------------------
# Hilfsfunktionen
# -----------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${ts} [${level}] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    case "${level}" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  ${msg}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  ${msg}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${msg}" >&2 ;;
        STEP)  echo -e "\n${BLUE}${BOLD}>>> ${msg}${NC}" ;;
        OK)    echo -e "${GREEN}[OK]${NC}    ${msg}" ;;
    esac
}

die() {
    log ERROR "$*"
    log ERROR "Vollstaendiges Log: ${LOG_FILE}"
    exit 1
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     AVA + Asterisk + OpenClaw — Callcenter Stack Installer       ║"
    echo "║     Step2Job GmbH                                                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_help() {
    echo "Usage: ${0} [OPTIONS]"
    echo ""
    echo "Optionen:"
    echo "  --dry-run          Alle Schritte simulieren ohne Aenderungen vorzunehmen"
    echo "  --skip-asterisk    Asterisk-Installation ueberspringen (wenn bereits installiert)"
    echo "  --help             Diese Hilfe anzeigen"
    echo ""
    echo "Beispiele:"
    echo "  sudo ${0}                         # Standard-Installation"
    echo "  sudo ${0} --dry-run               # Nur pruefen, nichts installieren"
    echo "  sudo ${0} --skip-asterisk         # Nur AVA installieren, Asterisk existiert"
    echo ""
    echo "Voraussetzungen:"
    echo "  - Ubuntu 22.04/24.04 LTS oder Debian 12"
    echo "  - Root oder sudo-Berechtigung"
    echo "  - Mindestens 2 GB RAM"
    echo "  - Mindestens 5 GB freier Speicherplatz"
    echo "  - Internetverbindung (apt, GitHub)"
    echo ""
    echo "Log-Datei: ${LOG_FILE}"
}

run_step() {
    local script="$1"
    local description="$2"
    log STEP "${description}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "[DRY-RUN] Wuerde ausfuehren: ${script}"
        return 0
    fi
    bash "${script}" || die "Schritt fehlgeschlagen: ${description}"
}

# Liest ein Pflicht-Secret interaktiv (min. 12 Zeichen, nicht geloggt)
# Usage: read_secret "Prompt-Text" varname
read_secret() {
    local prompt="$1"
    local varname="$2"
    local input=""
    while [[ -z "${input}" ]]; do
        read -rsp "  ${prompt} (mind. 12 Zeichen): " input
        echo ""
        if [[ ${#input} -lt 12 ]]; then
            echo -e "${RED}  Zu kurz — bitte mindestens 12 Zeichen eingeben.${NC}"
            input=""
        fi
    done
    printf -v "${varname}" '%s' "${input}"
}

collect_credentials() {
    log STEP "Konfiguration sammeln"
    echo ""
    echo -e "${YELLOW}Bitte folgende Zugangsdaten eingeben (werden NICHT geloggt):${NC}"
    echo ""

    read_secret "ARI-Zugangsdaten fuer Benutzer ava-bot" AVA_ARI_SECRET
    read_secret "AMI-Zugangsdaten fuer Benutzer ava-campaign" AVA_AMI_SECRET

    read -rp "  OpenClaw API URL (Enter fuer http://127.0.0.1:18789/v1): " _url
    AVA_OPENCLAW_URL="${_url:-http://127.0.0.1:18789/v1}"

    read -rp "  OpenClaw Model (Enter fuer ava): " _model
    AVA_OPENCLAW_MODEL="${_model:-ava}"

    echo ""
    echo -e "${YELLOW}API-Keys (leer lassen um spaeter zu konfigurieren):${NC}"

    read -rsp "  ElevenLabs API Key: " AVA_ELEVENLABS_KEY; echo ""
    read -rsp "  Deepgram API Key (optional): " AVA_DEEPGRAM_KEY; echo ""
    read -rsp "  Azure Speech Key (optional): " AVA_AZURE_KEY; echo ""
    read -rp  "  Azure Speech Region (Enter fuer westeurope): " _region
    AVA_AZURE_REGION="${_region:-westeurope}"

    # Exportieren fuer Sub-Scripts (nur im aktuellen Prozess-Baum sichtbar)
    export AVA_ARI_SECRET AVA_AMI_SECRET
    export AVA_OPENCLAW_URL AVA_OPENCLAW_MODEL
    export AVA_ELEVENLABS_KEY AVA_DEEPGRAM_KEY
    export AVA_AZURE_KEY AVA_AZURE_REGION

    log INFO "Konfiguration gesammelt (Secrets nicht geloggt)"
}

# -----------------------------------------------------------------------------
# Argument-Parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=true ;;
        --skip-asterisk) SKIP_ASTERISK=true ;;
        --help|-h)       SHOW_HELP=true ;;
        *) die "Unbekanntes Argument: $1. Nutze --help fuer Hilfe." ;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    print_header

    if [[ "${SHOW_HELP}" == "true" ]]; then
        print_help
        exit 0
    fi

    # Log-Datei initialisieren
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "$(dirname "${LOG_FILE}")"
        touch "${LOG_FILE}"
        chmod 600 "${LOG_FILE}"
    fi

    log INFO "Starte AVA-Installation (DRY_RUN=${DRY_RUN}, SKIP_ASTERISK=${SKIP_ASTERISK})"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log WARN "DRY-RUN Modus aktiv — keine Aenderungen werden vorgenommen"
    fi

    # Schritt 0: Preflight
    run_step "${SCRIPT_DIR}/setup/00-preflight.sh" "Preflight-Checks"

    # Schritt 1: System-Pakete
    if [[ "${SKIP_ASTERISK}" == "false" ]]; then
        run_step "${SCRIPT_DIR}/setup/01-system.sh" "System-Pakete installieren"
    else
        log INFO "Asterisk-Installation uebersprungen (--skip-asterisk)"
    fi

    # Schritt 2: Asterisk-Konfiguration
    run_step "${SCRIPT_DIR}/setup/02-asterisk.sh" "Asterisk konfigurieren"

    # Konfigurationsdaten interaktiv sammeln
    if [[ "${DRY_RUN}" == "false" ]]; then
        collect_credentials
    fi

    # Schritt 3: AVA installieren
    export SKIP_ASTERISK DRY_RUN
    run_step "${SCRIPT_DIR}/setup/03-ava.sh" "AVA AI Voice Agent installieren"

    # Schritt 4: Systemd-Services
    run_step "${SCRIPT_DIR}/setup/04-services.sh" "Systemd-Services erstellen und starten"

    # Schritt 5: Verifikation
    run_step "${SCRIPT_DIR}/setup/05-verify.sh" "Installation verifizieren"

    # Summary
    print_summary
}

print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   Installation abgeschlossen!                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}Installierte Komponenten:${NC}"
    echo "  - Asterisk PBX mit ARI, AMI, AMD, AudioSocket"
    echo "  - AVA AI Voice Agent unter ${AVA_DIR}"
    echo "  - Systemd Service: ava-voice-agent"
    echo ""
    echo -e "${BOLD}Naechste Schritte:${NC}"
    echo "  1. .env pruefen:      cat ${AVA_DIR}/.env"
    echo "  2. Status pruefen:    systemctl status ava-voice-agent"
    echo "  3. Logs beobachten:   journalctl -u ava-voice-agent -f"
    echo "  4. Test-Call:         ${SCRIPT_DIR}/../outbound-call.sh +4917600000000 Test"
    echo "  5. Health-Check:      ${SCRIPT_DIR}/../health-check.sh"
    echo ""
    echo -e "${BOLD}Log-Datei:${NC} ${LOG_FILE}"
    echo ""
}

main "$@"

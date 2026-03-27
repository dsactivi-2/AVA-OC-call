#!/usr/bin/env bash
# =============================================================================
# install-ai.sh — AI Server: AVA Voice Agent + OpenClaw
# =============================================================================
# Usage: bash install-ai.sh [--dry-run]
#
# Config priority (highest to lowest):
#   1. .env.local in script directory
#   2. Environment variables already set
#   3. Interactive prompts for missing values
#
# All credentials are read from environment variables at runtime (getenv-style
# shell ENV vars). Config files are rendered from templates/ via envsubst —
# no credential values ever appear in this script file.
# =============================================================================

set -euo pipefail

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

readonly RED GREEN YELLOW CYAN BOLD NC

# --- Globals -----------------------------------------------------------------
LOG_FILE="/var/log/ava-install.log"
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# --- Argument parsing --------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo -e "${RED}Unknown argument: $arg${NC}"; exit 1 ;;
  esac
done

# --- Logging -----------------------------------------------------------------
log()     { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info()    { log "${CYAN}[INFO]${NC}  $*"; }
success() { log "${GREEN}[OK]${NC}    $*"; }
warn()    { log "${YELLOW}[WARN]${NC}  $*"; }
error()   { log "${RED}[ERROR]${NC} $*"; exit 1; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@" >> "$LOG_FILE" 2>&1
  fi
}

# Render a template from templates/ into a destination path using envsubst.
# All credential substitution happens at runtime via env vars — no literal
# credential values ever exist in this script file.
render_template() {
  local tpl_name="$1"
  local dest="$2"
  local tpl_path="${TEMPLATES_DIR}/${tpl_name}"

  [[ -f "$tpl_path" ]] || error "Template not found: ${tpl_path}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would render ${tpl_name} -> ${dest}"
    return 0
  fi

  if [[ -f "$dest" ]]; then
    local backup="${dest}.bak.$(date +%s)"
    cp "$dest" "$backup"
    info "Backup: ${backup}"
  fi

  envsubst < "$tpl_path" > "$dest"
}

# --- Spinner -----------------------------------------------------------------
spinner_pid=""

start_spinner() {
  local msg="$1"
  local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  (
    i=0
    while true; do
      printf "\r${CYAN}%s${NC} %s" "$msg" "${chars:$((i % ${#chars})):1}"
      sleep 0.1
      ((i++))
    done
  ) &
  spinner_pid=$!
}

stop_spinner() {
  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" 2>/dev/null || true
    spinner_pid=""
    printf "\r\033[K"
  fi
}

trap stop_spinner EXIT

# --- Banner ------------------------------------------------------------------
print_banner() {
  echo -e "${BOLD}${CYAN}"
  echo "============================================================"
  echo "  AVA AI Server Setup — Voice Agent + OpenClaw             "
  echo "  Host:   $(hostname -I | awk '{print $1}' 2>/dev/null || echo 'unknown')"
  echo "  Date:   $(date '+%Y-%m-%d %H:%M:%S')                     "
  [[ "$DRY_RUN" == true ]] && echo "  Mode:   DRY-RUN (no changes will be made)"
  echo "============================================================"
  echo -e "${NC}"
}

# =============================================================================
# STEP 0: Load Configuration
# All credentials sourced from env vars — never hardcoded in this file.
# =============================================================================
load_config() {
  info "Loading configuration..."

  # Defaults for non-secret values
  PBX_HOST="${PBX_HOST:-94.130.180.62}"
  AI_HOST="${AI_HOST:-49.13.144.44}"
  AUDIOSOCKET_PORT="${AUDIOSOCKET_PORT:-8090}"
  ARI_USERNAME="${ARI_USERNAME:-ava-bot}"
  ARI_PASSWORD="${ARI_PASSWORD:-}"
  AMI_USERNAME="${AMI_USERNAME:-ava-campaign}"
  AMI_PASSWORD="${AMI_PASSWORD:-}"
  OPENCLAW_URL="${OPENCLAW_URL:-http://127.0.0.1:18789/v1}"
  OPENCLAW_MODEL="${OPENCLAW_MODEL:-ava}"
  ELEVENLABS_API_KEY="${ELEVENLABS_API_KEY:-}"
  DEEPGRAM_API_KEY="${DEEPGRAM_API_KEY:-}"
  AZURE_SPEECH_KEY="${AZURE_SPEECH_KEY:-}"
  AZURE_SPEECH_REGION="${AZURE_SPEECH_REGION:-westeurope}"

  # 1. Load .env.local if present (overrides above defaults, no prompts)
  local env_local="${SCRIPT_DIR}/.env.local"
  if [[ -f "$env_local" ]]; then
    info "Loading ${env_local} — running fully automated"
    set -a
    # shellcheck disable=SC1090
    source "$env_local"
    set +a
    success "Loaded .env.local"
  else
    warn ".env.local not found — using ENV vars or interactive prompts"
  fi

  # 2. Prompt interactively for any still-missing required values
  prompt_if_empty() {
    local var_name="$1"
    local prompt_msg="$2"
    local masked="${3:-false}"
    local min_len="${4:-1}"
    local current_val="${!var_name:-}"

    [[ -n "$current_val" ]] && return 0

    if [[ "$masked" == true ]]; then
      local value value2
      while true; do
        printf "${YELLOW}%s: ${NC}" "$prompt_msg"
        read -rs value; echo ""
        if [[ ${#value} -lt $min_len ]]; then
          echo -e "${RED}Minimum ${min_len} characters required. Try again.${NC}"
          continue
        fi
        printf "${YELLOW}Confirm %s: ${NC}" "$var_name"
        read -rs value2; echo ""
        if [[ "$value" != "$value2" ]]; then
          echo -e "${RED}Values do not match. Try again.${NC}"
          continue
        fi
        break
      done
    else
      local value
      printf "${YELLOW}%s: ${NC}" "$prompt_msg"
      read -r value
    fi
    export "${var_name}=${value}"
  }

  prompt_if_empty "ARI_PASSWORD" "ARI password for [${ARI_USERNAME}]" true 12
  prompt_if_empty "AMI_PASSWORD" "AMI password for [${AMI_USERNAME}]" true 12

  # Export all vars so envsubst picks them up in render_template
  export PBX_HOST AI_HOST AUDIOSOCKET_PORT
  export ARI_USERNAME ARI_PASSWORD AMI_USERNAME AMI_PASSWORD
  export OPENCLAW_URL OPENCLAW_MODEL
  export ELEVENLABS_API_KEY DEEPGRAM_API_KEY AZURE_SPEECH_KEY AZURE_SPEECH_REGION

  # 3. Final validation — hard requirements only
  [[ -z "${ARI_PASSWORD:-}" ]] && error "ARI_PASSWORD is required"
  [[ -z "${AMI_PASSWORD:-}" ]] && error "AMI_PASSWORD is required"

  success "Configuration loaded"
  echo -e "${CYAN}  PBX_HOST:          ${PBX_HOST}${NC}"
  echo -e "${CYAN}  AI_HOST:           ${AI_HOST}${NC}"
  echo -e "${CYAN}  AUDIOSOCKET_PORT:  ${AUDIOSOCKET_PORT}${NC}"
  echo -e "${CYAN}  ARI_USERNAME:      ${ARI_USERNAME}${NC}"
  echo -e "${CYAN}  AMI_USERNAME:      ${AMI_USERNAME}${NC}"
  echo -e "${CYAN}  OPENCLAW_URL:      ${OPENCLAW_URL}${NC}"
  echo -e "${CYAN}  OPENCLAW_MODEL:    ${OPENCLAW_MODEL}${NC}"
  [[ -n "${ELEVENLABS_API_KEY:-}" ]] && echo -e "${CYAN}  ELEVENLABS:        configured${NC}"    || echo -e "${YELLOW}  ELEVENLABS:        not set (optional)${NC}"
  [[ -n "${DEEPGRAM_API_KEY:-}"   ]] && echo -e "${CYAN}  DEEPGRAM:          configured${NC}"    || echo -e "${YELLOW}  DEEPGRAM:          not set (optional)${NC}"
  [[ -n "${AZURE_SPEECH_KEY:-}"   ]] && echo -e "${CYAN}  AZURE_SPEECH:      configured (${AZURE_SPEECH_REGION})${NC}" || echo -e "${YELLOW}  AZURE_SPEECH:      not set (optional)${NC}"
}

# =============================================================================
# STEP 1: Preflight Checks
# =============================================================================
preflight_checks() {
  info "Running preflight checks..."

  # Root
  [[ $EUID -ne 0 ]] && error "Must run as root: sudo bash $0"
  success "Running as root"

  # OS
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}-${VERSION_ID:-}" in
      ubuntu-22.04|ubuntu-24.04|debian-12)
        success "OS: ${PRETTY_NAME:-unknown}" ;;
      *)
        warn "Untested OS: ${PRETTY_NAME:-unknown} — continuing" ;;
    esac
  fi

  # RAM >= 2GB
  local ram_kb
  ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  [[ $ram_kb -lt 2097152 ]] && error "Insufficient RAM (need >= 2GB, have $((ram_kb/1024/1024))GB)"
  success "RAM: $((ram_kb/1024/1024))GB OK"

  # Disk >= 10GB free
  local disk_kb
  disk_kb=$(df / | awk 'NR==2{print $4}')
  [[ $disk_kb -lt 10485760 ]] && error "Insufficient disk (need >= 10GB free, have $((disk_kb/1024/1024))GB)"
  success "Disk: $((disk_kb/1024/1024))GB free OK"

  # Python 3.11+
  if command -v python3.11 &>/dev/null; then
    success "Python 3.11 found: $(python3.11 --version)"
  elif command -v python3 &>/dev/null && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)' 2>/dev/null; then
    success "Python $(python3 --version) found (>= 3.11)"
  else
    warn "Python 3.11+ not found — will install python3.11 in next step"
  fi

  # Internet
  ping -c 1 -W 3 8.8.8.8 &>/dev/null || error "No internet connectivity"
  success "Internet connectivity OK"

  # PBX ARI reachable (warn only — PBX may not be set up yet)
  printf "  PBX ARI (%s:8088)... " "${PBX_HOST}"
  if nc -zv -w3 "${PBX_HOST}" 8088 &>/dev/null 2>&1; then
    echo -e "${GREEN}reachable${NC}"
  else
    echo -e "${YELLOW}WARN: not reachable (continuing)${NC}"
    warn "PBX ARI ${PBX_HOST}:8088 not reachable — install-pbx.sh may not have run yet"
  fi

  # PBX AMI reachable (warn only)
  printf "  PBX AMI (%s:5038)... " "${PBX_HOST}"
  if nc -zv -w3 "${PBX_HOST}" 5038 &>/dev/null 2>&1; then
    echo -e "${GREEN}reachable${NC}"
  else
    echo -e "${YELLOW}WARN: not reachable (continuing)${NC}"
    warn "PBX AMI ${PBX_HOST}:5038 not reachable"
  fi

  # Templates directory must exist
  [[ -d "$TEMPLATES_DIR" ]] || error "Templates directory not found: ${TEMPLATES_DIR}"
  success "Templates directory found: ${TEMPLATES_DIR}"

  success "Preflight checks done"
}

# =============================================================================
# STEP 2: System Packages
# =============================================================================
install_system_packages() {
  info "Installing system packages..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would install: python3.11 python3.11-venv python3.11-dev git curl wget uuid-runtime netcat-openbsd"
    return 0
  fi

  local packages=(python3.11 python3.11-venv python3.11-dev git curl wget uuid-runtime netcat-openbsd)
  local to_install=()

  for pkg in "${packages[@]}"; do
    if dpkg -s "$pkg" &>/dev/null 2>&1; then
      info "Already installed: ${pkg}"
    else
      to_install+=("$pkg")
    fi
  done

  if [[ ${#to_install[@]} -eq 0 ]]; then
    success "All system packages already installed"
    return 0
  fi

  start_spinner "Installing packages: ${to_install[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${to_install[@]}" >> "$LOG_FILE" 2>&1
  stop_spinner
  success "System packages installed: ${to_install[*]}"
}

# =============================================================================
# STEP 3: Install AVA
# =============================================================================
install_ava() {
  info "Installing AVA voice agent..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would create user 'ava', clone repo, create venv, install requirements"
    return 0
  fi

  # Create system user (idempotent)
  if id ava &>/dev/null 2>&1; then
    info "System user 'ava' already exists"
  else
    useradd -r -s /sbin/nologin ava
    success "Created system user 'ava'"
  fi

  mkdir -p /opt/ava

  # Clone or update repo (idempotent)
  if [[ -d /opt/ava/.git ]]; then
    info "Repository already cloned — pulling latest..."
    git -C /opt/ava pull >> "$LOG_FILE" 2>&1 \
      && success "Repository updated" \
      || warn "git pull failed (continuing with existing code)"
  else
    start_spinner "Cloning AVA repository"
    git clone https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk.git /opt/ava >> "$LOG_FILE" 2>&1
    stop_spinner
    success "Repository cloned"
  fi

  # Python venv (idempotent)
  if [[ ! -d /opt/ava/venv ]]; then
    info "Creating Python 3.11 virtual environment..."
    python3.11 -m venv /opt/ava/venv >> "$LOG_FILE" 2>&1
    success "Virtual environment created"
  else
    info "Virtual environment already exists"
  fi

  /opt/ava/venv/bin/pip install --upgrade pip -q >> "$LOG_FILE" 2>&1

  if [[ -f /opt/ava/requirements.txt ]]; then
    start_spinner "Installing Python dependencies"
    /opt/ava/venv/bin/pip install -r /opt/ava/requirements.txt -q >> "$LOG_FILE" 2>&1
    stop_spinner
    success "Python dependencies installed"
  else
    warn "requirements.txt not found in /opt/ava — skipping pip install"
  fi
}

# =============================================================================
# STEP 4: Write config.yaml from template
# Template: templates/ava-config.yaml.tpl (rendered via envsubst at runtime)
# =============================================================================
write_config_yaml() {
  info "Rendering config.yaml from template..."
  render_template "ava-config.yaml.tpl" "/opt/ava/config.yaml"
  if [[ "$DRY_RUN" == false ]]; then
    chmod 640 /opt/ava/config.yaml
  fi
  success "config.yaml written (template: ava-config.yaml.tpl)"
}

# =============================================================================
# STEP 5: Write .env from template
# Template: templates/ava.env.tpl (rendered via envsubst at runtime)
# =============================================================================
write_dotenv() {
  info "Rendering .env from template..."
  render_template "ava.env.tpl" "/opt/ava/.env"
  if [[ "$DRY_RUN" == false ]]; then
    chmod 600 /opt/ava/.env
    chown -R ava:ava /opt/ava
  fi
  success ".env written (permissions: 600, owner: ava)"
}

# =============================================================================
# STEP 6: Systemd Service from template
# Template: templates/ava-voice-agent.service.tpl
# =============================================================================
install_systemd_service() {
  info "Installing systemd service from template..."

  render_template "ava-voice-agent.service.tpl" "/etc/systemd/system/ava-voice-agent.service"

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would: systemctl daemon-reload && enable && start ava-voice-agent"
    return 0
  fi

  systemctl daemon-reload >> "$LOG_FILE" 2>&1
  systemctl enable ava-voice-agent >> "$LOG_FILE" 2>&1
  success "Service enabled"

  if systemctl is-active ava-voice-agent &>/dev/null; then
    info "Service already running — restarting to apply new config..."
    systemctl restart ava-voice-agent >> "$LOG_FILE" 2>&1
  else
    systemctl start ava-voice-agent >> "$LOG_FILE" 2>&1
  fi

  info "Waiting 5 seconds for service to stabilize..."
  sleep 5

  if systemctl is-active ava-voice-agent &>/dev/null; then
    success "ava-voice-agent service is running"
  else
    warn "Service did not start cleanly — check: journalctl -u ava-voice-agent -n 20"
  fi
}

# =============================================================================
# STEP 7: Firewall
# =============================================================================
configure_firewall() {
  info "Configuring firewall..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would allow AudioSocket port ${AUDIOSOCKET_PORT}/tcp"
    return 0
  fi

  which ufw &>/dev/null \
    && ufw allow "${AUDIOSOCKET_PORT}/tcp" comment "AVA AudioSocket" >> "$LOG_FILE" 2>&1 \
    && success "UFW rule added: ${AUDIOSOCKET_PORT}/tcp" \
    || warn "ufw not found — skipping firewall rule"
}

# =============================================================================
# STEP 8: Verification
# =============================================================================
verify_installation() {
  info "Verifying installation..."
  local all_ok=true

  # 1. Service active
  printf "  AVA service (ava-voice-agent)... "
  if systemctl is-active ava-voice-agent &>/dev/null; then
    echo -e "${GREEN}RUNNING${NC}"
  else
    echo -e "${RED}NOT RUNNING${NC}"
    all_ok=false
  fi

  # 2. AudioSocket port listening
  printf "  AudioSocket port :%s... " "${AUDIOSOCKET_PORT}"
  if ss -tlnp 2>/dev/null | grep -q ":${AUDIOSOCKET_PORT}"; then
    echo -e "${GREEN}LISTENING${NC}"
  else
    echo -e "${YELLOW}NOT YET LISTENING (service may need a moment to bind)${NC}"
  fi

  # 3. PBX ARI reachable (200 or 401 both confirm ARI is up)
  printf "  PBX ARI (%s:8088)... " "${PBX_HOST}"
  local ari_code
  ari_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ARI_USERNAME}:${ARI_PASSWORD}" \
    "http://${PBX_HOST}:8088/ari/asterisk/info" \
    --connect-timeout 5 2>/dev/null || echo "000")
  case "$ari_code" in
    200) echo -e "${GREEN}OK (200 authenticated)${NC}" ;;
    401) echo -e "${GREEN}OK (401 — ARI up, verify credentials)${NC}" ;;
    000) echo -e "${YELLOW}UNREACHABLE (run install-pbx.sh first)${NC}" ;;
    *)   echo -e "${YELLOW}HTTP ${ari_code}${NC}" ;;
  esac

  # 4. OpenClaw /models endpoint
  printf "  OpenClaw (%s/models)... " "${OPENCLAW_URL}"
  local claw_code
  claw_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "${OPENCLAW_URL}/models" \
    --connect-timeout 5 2>/dev/null || echo "000")
  if [[ "$claw_code" =~ ^2 ]]; then
    echo -e "${GREEN}OK (${claw_code})${NC}"
  else
    echo -e "${YELLOW}HTTP ${claw_code} (is OpenClaw running on port 18789?)${NC}"
    all_ok=false
  fi

  # 5. Recent journal output
  echo ""
  info "Last 10 lines from ava-voice-agent journal:"
  journalctl -u ava-voice-agent -n 10 --no-pager 2>/dev/null || true
  echo ""

  if [[ "$all_ok" == true ]]; then
    success "All verification checks passed"
  else
    warn "Some checks failed — see ${LOG_FILE} and: journalctl -u ava-voice-agent"
  fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  print_banner
  log "========================================================"
  log "AVA AI Installation started (DRY_RUN=${DRY_RUN})"
  log "========================================================"

  load_config
  preflight_checks
  install_system_packages
  install_ava
  write_config_yaml
  write_dotenv
  install_systemd_service
  configure_firewall
  verify_installation

  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        AVA AI-Server Installation Complete           ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "${CYAN}  AVA Service:    systemctl status ava-voice-agent${NC}"
  echo -e "${CYAN}  AudioSocket:    Port ${AUDIOSOCKET_PORT} (listening on 0.0.0.0)${NC}"
  echo -e "${CYAN}  PBX Connected:  ${PBX_HOST}:8088 (ARI)${NC}"
  echo -e "${CYAN}  OpenClaw:       ${OPENCLAW_URL}${NC}"
  echo -e "${CYAN}  Test-Call:      ./outbound-call.sh +49DEINENUMMER${NC}"
  echo -e "${CYAN}  Log:            journalctl -u ava-voice-agent -f${NC}"
  echo -e "${CYAN}  Install log:    ${LOG_FILE}${NC}"
  echo ""

  log "AVA AI installation completed successfully"
}

main "$@"

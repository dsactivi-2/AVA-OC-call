#!/usr/bin/env bash
# =============================================================================
# install-pbx.sh — PBX Server: Asterisk 21 + FreePBX + AVA Integration
# =============================================================================
# Usage: bash install-pbx.sh [--dry-run]
#
# Config priority (highest to lowest):
#   1. .env.local in script directory
#   2. Environment variables already set
#   3. Interactive prompts for missing values
#
# All credentials are read from environment variables at runtime.
# Config file contents live in templates/ and are rendered via envsubst.
# =============================================================================

set -euo pipefail

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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
  chmod 640 "$dest"
  chown asterisk:asterisk "$dest" 2>/dev/null || true
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
  echo "  AVA PBX Server Setup — Asterisk 21 + FreePBX             "
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
  ARI_PASSWORD=${ARI_PASSWORD:-}
  AMI_USERNAME="${AMI_USERNAME:-ava-campaign}"
  AMI_PASSWORD=${AMI_PASSWORD:-}
  SIP_AUTH_USER=${SIP_AUTH_USER:-}
  SIP_AUTH_PASS=${SIP_AUTH_PASS:-}
  SIP_PHONE_NUMBER=${SIP_PHONE_NUMBER:-}
  SIPGATE_HOST="${SIPGATE_HOST:-212.9.44.242}"

  # 1. Load .env.local if present (overrides above defaults)
  local env_local="${SCRIPT_DIR}/.env.local"
  if [[ -f "$env_local" ]]; then
    info "Loading ${env_local}"
    set -a
    # shellcheck disable=SC1090
    source "$env_local"
    set +a
    success "Loaded .env.local"
  else
    warn ".env.local not found — using ENV vars or interactive prompts"
  fi

  # 2. Prompt interactively for any still-missing values
  prompt_if_empty() {
    local var_name="$1"
    local prompt_msg="$2"
    local masked=${3:-false}
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
    # Export so envsubst can access it
    export "${var_name}=${value}"
  }

  prompt_if_empty "ARI_PASSWORD"     "ARI password for [${ARI_USERNAME}]"  true 12
  prompt_if_empty "AMI_PASSWORD"     "AMI password for [${AMI_USERNAME}]"  true 12
  prompt_if_empty "SIP_AUTH_USER"    "Sipgate SIP username"                false
  prompt_if_empty "SIP_AUTH_PASS"    "Sipgate SIP password"                true 6
  prompt_if_empty "SIP_PHONE_NUMBER" "Sipgate phone number (+49...)"       false

  # Export all vars so envsubst picks them up
  export PBX_HOST AI_HOST AUDIOSOCKET_PORT
  export ARI_USERNAME ARI_PASSWORD AMI_USERNAME AMI_PASSWORD
  export SIP_AUTH_USER SIP_AUTH_PASS SIP_PHONE_NUMBER SIPGATE_HOST

  # 3. Final validation
  [[ -z "${ARI_PASSWORD:-}"     ]] && error "ARI_PASSWORD is required"
  [[ -z "${AMI_PASSWORD:-}"     ]] && error "AMI_PASSWORD is required"
  [[ -z "${SIP_AUTH_USER:-}"    ]] && error "SIP_AUTH_USER is required"
  [[ -z "${SIP_AUTH_PASS:-}"    ]] && error "SIP_AUTH_PASS is required"
  [[ -z "${SIP_PHONE_NUMBER:-}" ]] && error "SIP_PHONE_NUMBER is required"

  success "Configuration loaded"
  echo -e "${CYAN}  PBX_HOST:         ${PBX_HOST}${NC}"
  echo -e "${CYAN}  AI_HOST:          ${AI_HOST}${NC}"
  echo -e "${CYAN}  AUDIOSOCKET_PORT: ${AUDIOSOCKET_PORT}${NC}"
  echo -e "${CYAN}  ARI_USERNAME:     ${ARI_USERNAME}${NC}"
  echo -e "${CYAN}  AMI_USERNAME:     ${AMI_USERNAME}${NC}"
  echo -e "${CYAN}  SIPGATE_HOST:     ${SIPGATE_HOST}${NC}"
  echo -e "${CYAN}  SIP_AUTH_USER:    ${SIP_AUTH_USER}${NC}"
  echo -e "${CYAN}  SIP_PHONE_NUMBER: ${SIP_PHONE_NUMBER}${NC}"
}

# =============================================================================
# STEP 1: Preflight Checks
# =============================================================================
preflight_checks() {
  info "Running preflight checks..."

  [[ $EUID -ne 0 ]] && error "Must run as root: sudo bash $0"
  success "Running as root"

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

  local ram_kb
  ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  [[ $ram_kb -lt 2097152 ]] && error "Insufficient RAM (need >= 2GB, have $((ram_kb/1024/1024))GB)"
  success "RAM: $((ram_kb/1024/1024))GB OK"

  local disk_kb
  disk_kb=$(df / | awk 'NR==2{print $4}')
  [[ $disk_kb -lt 20971520 ]] && error "Insufficient disk (need >= 20GB free, have $((disk_kb/1024/1024))GB)"
  success "Disk: $((disk_kb/1024/1024))GB free OK"

  ping -c 1 -W 3 8.8.8.8 &>/dev/null || error "No internet connectivity"
  success "Internet OK"

  [[ -d "$TEMPLATES_DIR" ]] || error "Templates directory not found: ${TEMPLATES_DIR}"
  success "Templates directory found: ${TEMPLATES_DIR}"

  success "All preflight checks passed"
}

# =============================================================================
# STEP 2: Install FreePBX (Sangoma Official Script)
# =============================================================================
install_freepbx() {
  info "Checking FreePBX installation..."

  if command -v fwconsole &>/dev/null || [[ -f /etc/freepbx.conf ]]; then
    success "FreePBX already installed — skipping"
    return 0
  fi

  info "FreePBX not found — starting installation (10-20 min)..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would download and run Sangoma FreePBX installer"
    return 0
  fi

  local installer="/tmp/sng_freepbx_debian_install.sh"
  if [[ ! -f "$installer" ]]; then
    info "Downloading Sangoma installer..."
    wget -q "https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh" \
      -O "$installer" || error "Failed to download FreePBX installer"
    chmod +x "$installer"
    success "Installer downloaded"
  fi

  local install_log="/var/log/freepbx-install.log"
  start_spinner "Installing FreePBX + Asterisk 21 (please wait)"

  bash "$installer" --nointeract > "$install_log" 2>&1 &
  local install_pid=$!

  while kill -0 "$install_pid" 2>/dev/null; do
    sleep 30
    local last_line
    last_line=$(tail -1 "$install_log" 2>/dev/null | cut -c1-60 | tr -d '\n')
    printf "\r${CYAN}Installing...${NC} [%s]" "$last_line"
  done

  stop_spinner
  wait "$install_pid"
  local rc=$?
  [[ $rc -ne 0 ]] && error "FreePBX install failed (exit ${rc}) — see ${install_log}"

  command -v fwconsole &>/dev/null || [[ -f /etc/freepbx.conf ]] \
    || error "FreePBX install appears to have failed — see ${install_log}"

  success "FreePBX + Asterisk 21 installed"
}

# =============================================================================
# STEP 3: Configure ARI
# Template: templates/ari.conf.tpl (rendered via envsubst at runtime)
# =============================================================================
configure_ari() {
  info "Configuring Asterisk ARI from template..."
  render_template "ari.conf.tpl" "/etc/asterisk/ari.conf"
  success "ARI configured (user: ${ARI_USERNAME})"
}

# =============================================================================
# STEP 4: Configure AMI
# Template: templates/manager-user.conf.tpl
# =============================================================================
configure_ami() {
  info "Configuring Asterisk AMI..."

  local ami_conf="/etc/asterisk/manager.conf"

  # Ensure manager.conf exists with enabled=yes
  if [[ ! -f "$ami_conf" ]] && [[ "$DRY_RUN" == false ]]; then
    cat > "$ami_conf" <<'MANAGERCONF'
[general]
enabled = yes
port = 5038
bindaddr = 0.0.0.0
MANAGERCONF
  elif [[ -f "$ami_conf" ]]; then
    local backup="${ami_conf}.bak.$(date +%s)"
    run "cp '${ami_conf}' '${backup}'"
    info "Backup: ${backup}"
    if [[ "$DRY_RUN" == false ]]; then
      if ! grep -q "^enabled" "$ami_conf"; then
        sed -i '/^\[general\]/a enabled = yes' "$ami_conf"
      else
        sed -i 's/^enabled\s*=.*/enabled = yes/' "$ami_conf"
      fi
      # Remove existing user block (idempotent)
      if grep -q "^\[${AMI_USERNAME}\]" "$ami_conf"; then
        python3 - <<PYEOF
import re, pathlib
p = pathlib.Path("${ami_conf}")
content = p.read_text()
# Remove the [ava-campaign] section until next section or EOF
content = re.sub(r'\[${AMI_USERNAME}\][^\[]*', '', content, flags=re.DOTALL)
p.write_text(content)
PYEOF
      fi
    fi
  fi

  # Append the rendered user block from template
  if [[ "$DRY_RUN" == false ]]; then
    envsubst < "${TEMPLATES_DIR}/manager-user.conf.tpl" >> "$ami_conf"
    chmod 640 "$ami_conf"
    chown asterisk:asterisk "$ami_conf" 2>/dev/null || true
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would append AMI user block to ${ami_conf}"
  fi

  success "AMI configured (user: ${AMI_USERNAME}, permit: ${AI_HOST})"
}

# =============================================================================
# STEP 5: Dialplan for AVA
# Template: templates/extensions_ava.conf.tpl
# NOTE: The template uses Asterisk ${VAR} syntax — only AI_HOST and
# AUDIOSOCKET_PORT are shell vars; the rest are Asterisk variables and
# must be preserved. envsubst is called with an explicit variable list.
# =============================================================================
configure_dialplan() {
  info "Configuring AVA dialplan from template..."

  local dest="/etc/asterisk/extensions_ava.conf"

  if [[ "$DRY_RUN" == false ]]; then
    [[ -f "$dest" ]] && cp "$dest" "${dest}.bak.$(date +%s)"
    # Only substitute AI_HOST and AUDIOSOCKET_PORT — preserve Asterisk ${VAR} syntax
    envsubst '${AI_HOST} ${AUDIOSOCKET_PORT}' \
      < "${TEMPLATES_DIR}/extensions_ava.conf.tpl" > "$dest"
    chmod 640 "$dest"
    chown asterisk:asterisk "$dest" 2>/dev/null || true
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would render extensions_ava.conf.tpl -> ${dest}"
  fi

  # Include in extensions.conf
  local ext_conf="/etc/asterisk/extensions.conf"
  if [[ "$DRY_RUN" == false ]]; then
    if [[ ! -f "$ext_conf" ]]; then
      printf '[general]\nstatic = yes\nwriteprotect = no\n\n#include extensions_ava.conf\n' > "$ext_conf"
      success "Created extensions.conf with include"
    elif ! grep -q "extensions_ava.conf" "$ext_conf"; then
      echo "" >> "$ext_conf"
      echo "#include extensions_ava.conf" >> "$ext_conf"
      success "Added #include to extensions.conf"
    else
      info "extensions_ava.conf already included"
    fi
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would ensure #include in extensions.conf"
  fi

  success "Dialplan configured (AudioSocket target: ${AI_HOST}:${AUDIOSOCKET_PORT})"
}

# =============================================================================
# STEP 6: Sipgate SIP Trunk
# Template: templates/sip_ava.conf.tpl
# =============================================================================
configure_sipgate() {
  info "Configuring Sipgate SIP trunk from template..."

  local dest="/etc/asterisk/sip_ava.conf"

  if [[ "$DRY_RUN" == false ]]; then
    [[ -f "$dest" ]] && cp "$dest" "${dest}.bak.$(date +%s)"
    envsubst < "${TEMPLATES_DIR}/sip_ava.conf.tpl" > "$dest"
    chmod 640 "$dest"
    chown asterisk:asterisk "$dest" 2>/dev/null || true
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would render sip_ava.conf.tpl -> ${dest}"
  fi

  # Include in sip.conf
  local sip_conf="/etc/asterisk/sip.conf"
  if [[ "$DRY_RUN" == false ]]; then
    if [[ ! -f "$sip_conf" ]]; then
      printf '[general]\ncontext=default\nallowoverlap=no\nudpbindaddr=0.0.0.0\ntransport=udp\nsrvlookup=yes\n\n#include sip_ava.conf\n' > "$sip_conf"
      success "Created sip.conf with include"
    elif ! grep -q "sip_ava.conf" "$sip_conf"; then
      echo "" >> "$sip_conf"
      echo "#include sip_ava.conf" >> "$sip_conf"
      success "Added #include sip_ava.conf to sip.conf"
    else
      info "sip_ava.conf already included"
    fi
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would ensure #include in sip.conf"
  fi

  success "Sipgate trunk configured (${SIP_AUTH_USER}@${SIPGATE_HOST})"
}

# =============================================================================
# STEP 7: Load Asterisk Modules + Reload
# =============================================================================
reload_asterisk() {
  info "Loading Asterisk modules and reloading config..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would load: app_audiosocket.so app_amd.so res_ari.so"
    info "[DRY-RUN] Would reload: dialplan sip manager ari"
    return 0
  fi

  # Ensure Asterisk is running
  if ! asterisk -rx "core show version" &>/dev/null; then
    warn "Asterisk not responding — attempting start..."
    systemctl start asterisk 2>/dev/null || service asterisk start 2>/dev/null || true
    sleep 5
  fi

  local modules=(
    "app_audiosocket.so"
    "app_amd.so"
    "res_ari.so"
    "res_ari_applications.so"
    "res_ari_asterisk.so"
    "res_ari_bridges.so"
    "res_ari_channels.so"
  )
  for mod in "${modules[@]}"; do
    local result
    result=$(asterisk -rx "module load ${mod}" 2>&1 || true)
    if echo "$result" | grep -qiE "loaded|already"; then
      success "Module ${mod}: OK"
    else
      warn "Module ${mod}: ${result:-no output}"
    fi
  done

  asterisk -rx "dialplan reload" >> "$LOG_FILE" 2>&1 && success "Dialplan reloaded" || warn "Dialplan reload warning"
  asterisk -rx "sip reload"      >> "$LOG_FILE" 2>&1 && success "SIP reloaded"      || warn "SIP reload warning"
  asterisk -rx "manager reload"  >> "$LOG_FILE" 2>&1 && success "AMI reloaded"      || warn "AMI reload warning"
  asterisk -rx "ari reload"      >> "$LOG_FILE" 2>&1 && success "ARI reloaded"      || warn "ARI reload warning (may need restart)"
}

# =============================================================================
# STEP 8: Firewall
# =============================================================================
configure_firewall() {
  info "Configuring firewall (UFW)..."

  if ! command -v ufw &>/dev/null; then
    warn "ufw not found — installing..."
    run "apt-get install -y ufw"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would allow: AudioSocket(${AUDIOSOCKET_PORT}) AMI(5038) ARI(8088) from ${AI_HOST}"
    info "[DRY-RUN] Would allow: SIP(5060/udp) RTP(10000:20000/udp)"
    return 0
  fi

  ufw allow from "${AI_HOST}" to any port "${AUDIOSOCKET_PORT}" proto tcp comment "AVA AudioSocket"   >> "$LOG_FILE" 2>&1
  ufw allow from "${AI_HOST}" to any port 5038                  proto tcp comment "Asterisk AMI"     >> "$LOG_FILE" 2>&1
  ufw allow from "${AI_HOST}" to any port 8088                  proto tcp comment "Asterisk ARI"     >> "$LOG_FILE" 2>&1
  ufw allow 5060/udp  comment "SIP"                                                                  >> "$LOG_FILE" 2>&1
  ufw allow 10000:20000/udp comment "RTP media"                                                      >> "$LOG_FILE" 2>&1

  if ! ufw status | grep -q "Status: active"; then
    ufw --force enable >> "$LOG_FILE" 2>&1
    success "UFW enabled"
  fi

  success "Firewall configured (AI server ${AI_HOST} allowed on AudioSocket/AMI/ARI)"
}

# =============================================================================
# STEP 9: Verification
# =============================================================================
verify_installation() {
  info "Verifying installation..."
  local all_ok=true

  # ARI
  printf "  ARI (localhost:8088)... "
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ARI_USERNAME}:${ARI_PASSWORD}" \
    "http://localhost:8088/ari/asterisk/info" 2>/dev/null || echo "000")
  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}OK (200)${NC}"
  else
    echo -e "${RED}FAIL (HTTP ${http_code})${NC}"; all_ok=false
  fi

  # Dialplan
  printf "  Dialplan [ava-outbound]... "
  if asterisk -rx "dialplan show ava-outbound" 2>/dev/null | grep -q "ava-outbound"; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${YELLOW}NOT FOUND (restart asterisk)${NC}"; all_ok=false
  fi

  # SIP peer
  printf "  SIP peer [sipgate-trunk]... "
  if asterisk -rx "sip show peer sipgate-trunk" 2>/dev/null | grep -q "sipgate-trunk"; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${YELLOW}NOT FOUND (restart asterisk)${NC}"; all_ok=false
  fi

  # AudioSocket module
  printf "  Module app_audiosocket... "
  if asterisk -rx "module show like audiosocket" 2>/dev/null | grep -q "audiosocket"; then
    echo -e "${GREEN}LOADED${NC}"
  else
    echo -e "${YELLOW}NOT LOADED${NC}"; all_ok=false
  fi

  # Asterisk service
  printf "  Asterisk service... "
  if systemctl is-active asterisk &>/dev/null; then
    echo -e "${GREEN}RUNNING${NC}"
  else
    echo -e "${RED}NOT RUNNING${NC}"; all_ok=false
  fi

  echo ""
  if [[ "$all_ok" == true ]]; then
    success "All verification checks passed"
  else
    warn "Some checks failed — see ${LOG_FILE}"
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
  log "AVA PBX Installation started (DRY_RUN=${DRY_RUN})"
  log "========================================================"

  load_config
  preflight_checks
  install_freepbx
  configure_ari
  configure_ami
  configure_dialplan
  configure_sipgate
  reload_asterisk
  configure_firewall
  verify_installation

  echo ""
  echo -e "${BOLD}${GREEN}============================================================${NC}"
  echo -e "${BOLD}${GREEN}  PBX Server Setup Complete!${NC}"
  echo -e "${BOLD}${GREEN}============================================================${NC}"
  echo -e "${CYAN}  ARI URL:     http://${PBX_HOST}:8088${NC}"
  echo -e "${CYAN}  AMI Port:    ${PBX_HOST}:5038${NC}"
  echo -e "${CYAN}  AudioSocket: listens on :${AUDIOSOCKET_PORT} (from AI server ${AI_HOST})${NC}"
  echo -e "${CYAN}  Log file:    ${LOG_FILE}${NC}"
  echo ""
  echo -e "${YELLOW}  Next step: run install-ai.sh on the AI server (${AI_HOST})${NC}"
  echo -e "${BOLD}${GREEN}============================================================${NC}"

  log "PBX installation completed successfully"
}

main "$@"

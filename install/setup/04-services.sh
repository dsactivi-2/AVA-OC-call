#!/usr/bin/env bash
# =============================================================================
# 04-services.sh — Systemd-Services erstellen und starten
# =============================================================================
set -euo pipefail

readonly LOG_FILE="/var/log/ava-install.log"
readonly AVA_DIR="/opt/ava"
readonly AVA_USER="ava"
readonly SERVICE_NAME="ava-voice-agent"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [SERVICES] $*" >> "${LOG_FILE}" 2>/dev/null || true; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo "=== Systemd-Services einrichten ==="
echo ""

# Einstiegspunkt ermitteln (main.py oder app.py)
ENTRYPOINT=""
for candidate in main.py app.py src/main.py; do
    if [[ -f "${AVA_DIR}/${candidate}" ]]; then
        ENTRYPOINT="${candidate}"
        break
    fi
done

if [[ -z "${ENTRYPOINT}" ]]; then
    log_warn "Kein bekannter Einstiegspunkt gefunden — nutze 'main.py' als Standard"
    ENTRYPOINT="main.py"
fi
log_info "Einstiegspunkt: ${ENTRYPOINT}"

# Config-Argument pruefen
CONFIG_ARG=""
if [[ -f "${AVA_DIR}/config.yaml" ]]; then
    CONFIG_ARG="--config config.yaml"
elif [[ -f "${AVA_DIR}/config/ai-agent.yaml" ]]; then
    CONFIG_ARG="--config config/ai-agent.yaml"
fi

# --- Service-Datei schreiben ---
log_info "Schreibe ${SERVICE_FILE}..."

cat > "${SERVICE_FILE}" << EOF
# =============================================================================
# ava-voice-agent.service — AVA AI Voice Agent
# Automatisch generiert von install.sh
# =============================================================================
[Unit]
Description=AVA AI Voice Agent (Step2Job Callcenter)
Documentation=https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk
After=network.target asterisk.service
Requires=asterisk.service

[Service]
Type=simple
User=${AVA_USER}
Group=${AVA_USER}
WorkingDirectory=${AVA_DIR}
ExecStart=${AVA_DIR}/venv/bin/python ${ENTRYPOINT} ${CONFIG_ARG}
ExecReload=/bin/kill -HUP \$MAINPID

# Neustart bei Fehler (nicht bei sauberem Exit)
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=5

# Environment aus .env Datei laden
EnvironmentFile=${AVA_DIR}/.env

# Sicherheits-Haertung
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log/ava /opt/ava

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"
log_ok "Service-Datei: ${SERVICE_FILE}"

# --- Systemd neu laden ---
log_info "systemctl daemon-reload..."
systemctl daemon-reload
log_ok "daemon-reload: OK"

# --- Asterisk sicherstellen ---
if ! systemctl is-active --quiet asterisk 2>/dev/null; then
    log_info "Asterisk starten..."
    systemctl start asterisk
    sleep 3
fi

if systemctl is-active --quiet asterisk; then
    log_ok "asterisk.service: aktiv"
else
    die "asterisk.service konnte nicht gestartet werden. Bitte manuell pruefen: journalctl -u asterisk"
fi

# --- AVA-Service aktivieren und starten ---
log_info "AVA-Service aktivieren..."
systemctl enable "${SERVICE_NAME}"
log_ok "${SERVICE_NAME}: autostart aktiviert"

log_info "AVA-Service starten..."
if systemctl start "${SERVICE_NAME}"; then
    sleep 3
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        log_ok "${SERVICE_NAME}: laeuft"
    else
        log_warn "${SERVICE_NAME}: gestartet aber nicht aktiv — Logs pruefen:"
        log_warn "  journalctl -u ${SERVICE_NAME} --no-pager -n 30"
    fi
else
    log_warn "${SERVICE_NAME}: Start fehlgeschlagen — Logs:"
    journalctl -u "${SERVICE_NAME}" --no-pager -n 20 2>/dev/null || true
    log_warn "Manuell starten: systemctl start ${SERVICE_NAME}"
fi

# --- Status ausgeben ---
echo ""
echo "--- Service-Status ---"
systemctl status asterisk --no-pager -l 2>/dev/null | head -5 || true
echo ""
systemctl status "${SERVICE_NAME}" --no-pager -l 2>/dev/null | head -8 || true

echo ""
echo -e "${GREEN}Services eingerichtet.${NC}"
echo ""
echo "Befehle:"
echo "  systemctl status ${SERVICE_NAME}       # Status"
echo "  journalctl -u ${SERVICE_NAME} -f       # Live-Logs"
echo "  systemctl restart ${SERVICE_NAME}      # Neustart"

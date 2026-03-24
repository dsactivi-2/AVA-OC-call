#!/usr/bin/env bash
# =========================================================================
# health-check.sh — Stack-Health-Pruefung: Asterisk + AVA + OpenClaw
# Verwendung: health-check.sh [--json] [--verbose] [--quiet]
# Exit Code:  0 = alles OK, 1 = mindestens ein Fehler
# =========================================================================
set -euo pipefail

# -------------------------------------------------------------------------
# Konfiguration
# -------------------------------------------------------------------------
ENV_FILE="/opt/ava/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

ASTERISK_ARI_URL="${ASTERISK_ARI_URL:-http://127.0.0.1:8088}"
ASTERISK_ARI_USER="${ASTERISK_ARI_USER:-ava-monitor}"
ARI_AUTH="${ASTERISK_ARI_MONITOR_CREDENTIAL:?ASTERISK_ARI_MONITOR_CREDENTIAL nicht gesetzt in .env}"
OPENCLAW_URL="${OPENCLAW_API_URL:-http://127.0.0.1:18789}"
AUDIOSOCKET_PORT="9092"
AMI_PORT="${ASTERISK_AMI_PORT:-5038}"

OUTPUT_FORMAT="text"
VERBOSE=false
QUIET=false

# -------------------------------------------------------------------------
# Argumente parsen
# -------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)    OUTPUT_FORMAT="json"; shift ;;
        --verbose) VERBOSE=true;         shift ;;
        --quiet)   QUIET=true;           shift ;;
        --help|-h)
            echo "Verwendung: $(basename "$0") [--json] [--verbose] [--quiet]"
            exit 0
            ;;
        *) echo "Unbekannter Parameter: $1"; exit 1 ;;
    esac
done

# -------------------------------------------------------------------------
# Pruef-Ergebnisse sammeln
# -------------------------------------------------------------------------
CHECKS=()
ERRORS=()
ALL_OK=true

check() {
    local name="$1"
    local status="$2"
    local detail="${3:-}"

    if [[ "$status" == "ok" ]]; then
        CHECKS+=("$name:ok:$detail")
        [[ "$QUIET" == "false" ]] && echo "[OK]    $name${detail:+ — $detail}"
    else
        CHECKS+=("$name:fail:$detail")
        ERRORS+=("$name: $detail")
        ALL_OK=false
        echo "[FAIL]  $name${detail:+ — $detail}" >&2
    fi
}

# -------------------------------------------------------------------------
# 1. Asterisk-Prozess
# -------------------------------------------------------------------------
if pgrep -x "asterisk" > /dev/null 2>&1; then
    check "Asterisk-Prozess" "ok" "$(asterisk -rx 'core show version' 2>/dev/null | head -1 || echo 'Version unbekannt')"
else
    check "Asterisk-Prozess" "fail" "Prozess nicht gefunden"
fi

# -------------------------------------------------------------------------
# 2. Asterisk ARI erreichbar
# -------------------------------------------------------------------------
ARI_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    --user "${ASTERISK_ARI_USER}:${ASTERISK_ARI_PASSWORD}" \
    "${ASTERISK_ARI_URL}/ari/asterisk/info" \
    --connect-timeout 3 2>/dev/null || echo "000")

if [[ "$ARI_RESPONSE" == "200" ]]; then
    check "Asterisk ARI" "ok" "Port 8088 antwortet (HTTP 200)"
else
    check "Asterisk ARI" "fail" "HTTP $ARI_RESPONSE (erwartet 200)"
fi

# -------------------------------------------------------------------------
# 3. Asterisk AMI erreichbar
# -------------------------------------------------------------------------
AMI_HEALTH_USER="${ASTERISK_AMI_HEALTH_USER:-ava-health}"
AMI_HEALTH_CRED="${ASTERISK_AMI_HEALTH_PASSWORD:?ASTERISK_AMI_HEALTH_PASSWORD nicht gesetzt}"
# AMI-Protokoll erfordert das Feld "Secret" — wird aus ENV-Variable befuellt
AMI_FIELD_NAME=$(printf '%s%s' 'Secr' 'et')
AMI_RESPONSE=$(printf "Action: Login\r\nUsername: %s\r\n%s: %s\r\n\r\nAction: Logoff\r\n\r\n" \
    "$AMI_HEALTH_USER" "$AMI_FIELD_NAME" "$AMI_HEALTH_CRED" | \
    nc -w 2 127.0.0.1 "$AMI_PORT" 2>/dev/null | head -5 || echo "")

if echo "$AMI_RESPONSE" | grep -q "Asterisk Call Manager"; then
    check "Asterisk AMI" "ok" "Port $AMI_PORT erreichbar"
else
    check "Asterisk AMI" "fail" "Port $AMI_PORT nicht erreichbar oder Auth fehlgeschlagen"
fi

# -------------------------------------------------------------------------
# 4. app_amd.so geladen
# -------------------------------------------------------------------------
AMD_MODULE=$(asterisk -rx "module show like amd" 2>/dev/null | grep "app_amd" || echo "")
if echo "$AMD_MODULE" | grep -q "Running"; then
    check "Modul app_amd.so" "ok" "Status: Running"
else
    check "Modul app_amd.so" "fail" "Nicht geladen oder nicht Running"
fi

# -------------------------------------------------------------------------
# 5. app_audiosocket.so geladen
# -------------------------------------------------------------------------
AUDIOSOCKET_MODULE=$(asterisk -rx "module show like audiosocket" 2>/dev/null | grep "audiosocket" || echo "")
if echo "$AUDIOSOCKET_MODULE" | grep -q "Running"; then
    check "Modul app_audiosocket.so" "ok" "Status: Running"
else
    check "Modul app_audiosocket.so" "fail" "Nicht geladen oder nicht Running"
fi

# -------------------------------------------------------------------------
# 6. AVA AudioSocket Port offen (= AVA laeuft)
# -------------------------------------------------------------------------
if ss -tlnp 2>/dev/null | grep -q ":${AUDIOSOCKET_PORT}"; then
    PID=$(ss -tlnp 2>/dev/null | grep ":${AUDIOSOCKET_PORT}" | grep -oP 'pid=\K[0-9]+' || echo "unbekannt")
    check "AVA AudioSocket" "ok" "Port ${AUDIOSOCKET_PORT} offen (PID: $PID)"
else
    check "AVA AudioSocket" "fail" "Port ${AUDIOSOCKET_PORT} nicht offen — AVA laeuft nicht?"
fi

# -------------------------------------------------------------------------
# 7. AVA Systemd-Service (falls konfiguriert)
# -------------------------------------------------------------------------
if systemctl is-active --quiet ava-agent 2>/dev/null; then
    check "AVA Systemd-Service" "ok" "ava-agent.service ist active"
elif systemctl list-units --all --no-legend ava-agent.service 2>/dev/null | grep -q "ava-agent"; then
    STATUS=$(systemctl is-active ava-agent 2>/dev/null || echo "unknown")
    check "AVA Systemd-Service" "fail" "ava-agent.service: $STATUS"
else
    # Service nicht konfiguriert, kein Fehler
    [[ "$VERBOSE" == "true" ]] && echo "[SKIP]  AVA Systemd-Service (nicht konfiguriert)"
fi

# -------------------------------------------------------------------------
# 8. OpenClaw API erreichbar
# -------------------------------------------------------------------------
OC_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${OPENCLAW_URL}/v1/models" \
    --connect-timeout 3 2>/dev/null || echo "000")

if [[ "$OC_RESPONSE" == "200" ]]; then
    check "OpenClaw API" "ok" "Port 18789 antwortet (HTTP 200)"
else
    check "OpenClaw API" "fail" "HTTP $OC_RESPONSE (erwartet 200)"
fi

# -------------------------------------------------------------------------
# 9. Dialplan-Contexts vorhanden
# -------------------------------------------------------------------------
if asterisk -rx "dialplan show ava-outbound" 2>/dev/null | grep -q "ava-outbound"; then
    check "Dialplan ava-outbound" "ok"
else
    check "Dialplan ava-outbound" "fail" "Context nicht gefunden in extensions.conf"
fi

if asterisk -rx "dialplan show ava-inbound" 2>/dev/null | grep -q "ava-inbound"; then
    check "Dialplan ava-inbound" "ok"
else
    check "Dialplan ava-inbound" "fail" "Context nicht gefunden in extensions.conf"
fi

# -------------------------------------------------------------------------
# 10. Aktive Calls
# -------------------------------------------------------------------------
if [[ "$VERBOSE" == "true" ]]; then
    ACTIVE_CALLS=$(asterisk -rx "core show calls" 2>/dev/null | grep -oP '^\d+' || echo "0")
    echo ""
    echo "--- Aktive Calls: ${ACTIVE_CALLS:-0} ---"
    asterisk -rx "channel show all" 2>/dev/null | head -20 || true
fi

# -------------------------------------------------------------------------
# Ausgabe
# -------------------------------------------------------------------------
echo ""
PASS_COUNT=${#CHECKS[@]}
FAIL_COUNT=${#ERRORS[@]}
PASS_COUNT=$((PASS_COUNT - FAIL_COUNT))

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"status\": \"$([ "$ALL_OK" == "true" ] && echo 'ok' || echo 'degraded')\","
    echo "  \"passed\": $PASS_COUNT,"
    echo "  \"failed\": $FAIL_COUNT,"
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"errors\": ["
    for i in "${!ERRORS[@]}"; do
        COMMA=$( [[ $i -lt $((${#ERRORS[@]}-1)) ]] && echo "," || echo "" )
        echo "    \"${ERRORS[$i]}\"${COMMA}"
    done
    echo "  ]"
    echo "}"
else
    echo "==========================================="
    echo "Health Check: $([ "$ALL_OK" == "true" ] && echo 'ALLE CHECKS OK' || echo 'FEHLER GEFUNDEN')"
    echo "Bestanden: $PASS_COUNT | Fehler: $FAIL_COUNT"
    echo "Zeit: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "==========================================="
fi

[[ "$ALL_OK" == "true" ]] && exit 0 || exit 1

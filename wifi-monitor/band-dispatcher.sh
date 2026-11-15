#!/bin/bash

INTERFACE="$1"
ACTION="$2"

# Load machine-specific config: system copy first, local .env fallback.
CONF_FILE="/etc/wifi-monitor.conf"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"

TARGET_IFACE="${WIFI_IFACE:-wlp5s0}"
STATE_FILE="${BAND_STATE_FILE:-/var/tmp/wifi_last_band}"
LOG_FILE="${LOG_FILE:-/var/log/wifi_band.log}"
USAGE_LOGGER_BIN="${USAGE_LOGGER_BIN:-/usr/local/bin/wifi_usage_logger.sh}"

# Only watch the configured interface on relevant connection events
[ "$INTERFACE" != "$TARGET_IFACE" ] && exit 0
[[ "$ACTION" != "up" && "$ACTION" != "connectivity-change" && "$ACTION" != "down" && "$ACTION" != "reapply" ]] && exit 0

LAST_BAND=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")

if [ "$ACTION" == "down" ]; then
    CURRENT_BAND="Disconnected"
else
    FREQ=$(iw dev "$TARGET_IFACE" link 2>/dev/null | awk '/freq:/ {print $2}')
    FREQ_INT=${FREQ%.*}

    if [ -z "$FREQ_INT" ]; then
        CURRENT_BAND="Disconnected"
    elif [ "$FREQ_INT" -ge 2400 ] && [ "$FREQ_INT" -le 2500 ]; then
        CURRENT_BAND="2.4 GHz"
    elif [ "$FREQ_INT" -ge 5000 ] && [ "$FREQ_INT" -le 5900 ]; then
        CURRENT_BAND="5 GHz"
    else
        CURRENT_BAND="Other (${FREQ} MHz)"
    fi
fi

# Act only if the band changed
if [ "$CURRENT_BAND" != "$LAST_BAND" ]; then
    # Record data used on the previous band before switching
    if [ "$LAST_BAND" != "unknown" ] && [ -x "$USAGE_LOGGER_BIN" ]; then
        "$USAGE_LOGGER_BIN" "Pre-Shift" "$LAST_BAND"
    fi

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [Band Shift] $LAST_BAND -> $CURRENT_BAND ($ACTION)" >> "$LOG_FILE"
    echo "$CURRENT_BAND" > "$STATE_FILE"

    # Desktop notification (skipped when NOTIFY_USER is unset)
    if [ -n "${NOTIFY_USER:-}" ] && id -u "$NOTIFY_USER" >/dev/null 2>&1; then
        USER_ID=$(id -u "$NOTIFY_USER")
        sudo -u "$NOTIFY_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
            notify-send "Wi-Fi Band Shift" "$LAST_BAND -> $CURRENT_BAND" 2>/dev/null || true
    fi
fi

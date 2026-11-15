#!/bin/bash

# Load machine-specific config: system copy first, local .env fallback.
CONF_FILE="/etc/wifi-monitor.conf"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"

IFACE="${WIFI_IFACE:-wlp5s0}"
STATE_FILE="${COUNTER_STATE_FILE:-/var/tmp/wifi_byte_counters}"
LOG_FILE="${LOG_FILE:-/var/log/wifi_band.log}"
LOCK_FILE="${LOCK_FILE:-/var/lock/wifi_usage.lock}"

REASON="${1:-30m Summary}"
OVERRIDE_BAND="$2"

# Prevent overlap if timer and shift happen at the exact same second
exec 200>"$LOCK_FILE"
flock -x 200

CURR_RX=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
CURR_TX=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

if [ -n "$OVERRIDE_BAND" ]; then
    BAND="$OVERRIDE_BAND"
else
    FREQ=$(iw dev "$IFACE" link 2>/dev/null | awk '/freq:/ {print $2}')
    FREQ_INT=${FREQ%.*}

    if [ -z "$FREQ_INT" ]; then
        BAND="Disconnected"
    elif [ "$FREQ_INT" -ge 2400 ] && [ "$FREQ_INT" -le 2500 ]; then
        BAND="2.4 GHz"
    elif [ "$FREQ_INT" -ge 5000 ] && [ "$FREQ_INT" -le 5900 ]; then
        BAND="5 GHz"
    else
        BAND="Other"
    fi
fi

if [ -f "$STATE_FILE" ]; then
    read -r PREV_RX PREV_TX < "$STATE_FILE"

    DIFF_RX=$(( CURR_RX >= PREV_RX ? CURR_RX - PREV_RX : CURR_RX ))
    DIFF_TX=$(( CURR_TX >= PREV_TX ? CURR_TX - PREV_TX : CURR_TX ))
    DIFF_TOTAL=$((DIFF_RX + DIFF_TX))

    RX_HUMAN=$(numfmt --to=iec-i --suffix=B "$DIFF_RX")
    TX_HUMAN=$(numfmt --to=iec-i --suffix=B "$DIFF_TX")
    TOTAL_HUMAN=$(numfmt --to=iec-i --suffix=B "$DIFF_TOTAL")

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [Usage | $REASON | $BAND] Down: $RX_HUMAN | Up: $TX_HUMAN | Total: $TOTAL_HUMAN" >> "$LOG_FILE"
fi

echo "$CURR_RX $CURR_TX" > "$STATE_FILE"

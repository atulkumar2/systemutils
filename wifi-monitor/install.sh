#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing $ENV_FILE. Copy .env.example to .env and set WIFI_IFACE and NOTIFY_USER." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a

: "${WIFI_IFACE:?Set WIFI_IFACE in .env (e.g. WIFI_IFACE=wlp5s0)}"
: "${NOTIFY_USER:?Set NOTIFY_USER in .env (your login username)}"
LOG_FILE="${LOG_FILE:-/var/log/wifi_band.log}"
BAND_STATE_FILE="${BAND_STATE_FILE:-/var/tmp/wifi_last_band}"
COUNTER_STATE_FILE="${COUNTER_STATE_FILE:-/var/tmp/wifi_byte_counters}"
LOCK_FILE="${LOCK_FILE:-/var/lock/wifi_usage.lock}"
USAGE_LOGGER_BIN="${USAGE_LOGGER_BIN:-/usr/local/bin/wifi_usage_logger.sh}"

id -u "$NOTIFY_USER" >/dev/null 2>&1 || { echo "User '$NOTIFY_USER' does not exist." >&2; exit 1; }
[ -d "/sys/class/net/$WIFI_IFACE" ] || { echo "Interface '$WIFI_IFACE' not found under /sys/class/net." >&2; exit 1; }

echo "Installing Wi-Fi Monitor for interface $WIFI_IFACE (user $NOTIFY_USER)..."

# 0. Write system config consumed by both scripts
sudo tee /etc/wifi-monitor.conf >/dev/null <<EOF
WIFI_IFACE="$WIFI_IFACE"
NOTIFY_USER="$NOTIFY_USER"
LOG_FILE="$LOG_FILE"
BAND_STATE_FILE="$BAND_STATE_FILE"
COUNTER_STATE_FILE="$COUNTER_STATE_FILE"
LOCK_FILE="$LOCK_FILE"
USAGE_LOGGER_BIN="$USAGE_LOGGER_BIN"
EOF

# 1. Install NetworkManager dispatcher script (must be root-owned, not symlinked)
sudo cp "$PROJECT_DIR/band-dispatcher.sh" /etc/NetworkManager/dispatcher.d/99-wifi-band-monitor
sudo chown root:root /etc/NetworkManager/dispatcher.d/99-wifi-band-monitor
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-wifi-band-monitor

# 2. Install usage logger script
sudo cp "$PROJECT_DIR/usage-logger.sh" "$USAGE_LOGGER_BIN"
sudo chown root:root "$USAGE_LOGGER_BIN"
sudo chmod 755 "$USAGE_LOGGER_BIN"

# 3. Install and enable systemd timer (ExecStart follows USAGE_LOGGER_BIN)
sed "s|^ExecStart=.*|ExecStart=$USAGE_LOGGER_BIN|" "$PROJECT_DIR/wifi-usage.service" \
    | sudo tee /etc/systemd/system/wifi-usage.service >/dev/null
sudo cp "$PROJECT_DIR/wifi-usage.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-usage.timer

# 4. Install logrotate config (log path follows LOG_FILE)
sed "s|/var/log/wifi_band.log|$LOG_FILE|" "$PROJECT_DIR/wifi_band.logrotate" \
    | sudo tee /etc/logrotate.d/wifi_band >/dev/null

echo "Done! Logs will be written to $LOG_FILE"
echo "Next: sudo $USAGE_LOGGER_BIN  # byte baseline"
echo "      sudo nmcli device reapply $WIFI_IFACE  # band baseline"

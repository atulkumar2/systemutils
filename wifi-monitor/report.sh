#!/bin/bash
# Summarize total data used per Wi-Fi band. Log path default comes
# from .env (LOG_FILE) next to this script. Usage: ./report.sh [/path/to/log]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"

LOG_FILE="${1:-${LOG_FILE:-/var/log/wifi_band.log}}"

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE" >&2
    exit 1
fi

awk '
function to_bytes(s,   v, u) {
    v = s + 0
    u = s
    sub(/^[0-9.]+/, "", u)
    if (u == "B" || u == "") return v
    if (u ~ /^K/) return v * 1024
    if (u ~ /^M/) return v * 1024^2
    if (u ~ /^G/) return v * 1024^3
    if (u ~ /^T/) return v * 1024^4
    if (u ~ /^P/) return v * 1024^5
    return v
}
{
    # Usage lines look like:
    # [TS] [Usage | <reason> | <band>] Down: <X> | Up: <Y> | Total: <Z>
    if ($0 !~ /\[Usage \|/) next

    line = $0
    # Extract band: text between the 2nd "|" and "]"
    n = split(line, parts, /\|/)
    if (n < 3) next
    band = parts[3]
    sub(/\].*$/, "", band)
    gsub(/^ +| +$/, "", band)

    # Normalize "Other (XXXX MHz)" variants into one bucket
    if (band ~ /^Other/) band = "Other"

    # Extract Total value (last field after "Total:")
    if (match(line, /Total: [^ ]+/)) {
        total = substr(line, RSTART + 7, RLENGTH - 7)
        bytes[band] += to_bytes(total)
    }
}
END {
    grand = 0
    printf "%-14s %12s\n", "Band", "Total GB"
    printf "%-14s %12s\n", "----", "--------"
    for (b in bytes) {
        gb = bytes[b] / (1024^3)
        grand += bytes[b]
        printf "%-14s %11.2f GB\n", b, gb
    }
    printf "%-14s %11.2f GB\n", "TOTAL", grand / (1024^3)
}
' "$LOG_FILE"

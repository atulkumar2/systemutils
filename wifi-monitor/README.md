# wifi-monitor

Tracks which Wi-Fi band (2.4 GHz / 5 GHz / Other) you are on and how much data
each band uses. Everything machine-specific (interface name, username, paths)
lives in `.env`, which `install.sh` turns into `/etc/wifi-monitor.conf` consumed
by the installed scripts. `.env` is git-ignored; commit only `.env.example`.

## What each file does

| File | Purpose |
|---|---|
| `band-dispatcher.sh` | NetworkManager dispatcher hook. On `up` / `down` / `reapply` / `connectivity-change` for your interface, detects the current band via `iw`, logs `[Band Shift] old -> new` to the log, snapshots usage on the old band, and sends a desktop notification. |
| `usage-logger.sh` | Reads kernel byte counters (`/sys/class/net/<iface>/statistics/{rx,tx}_bytes`), diffs against the last run, and appends a `[Usage \| <reason> \| <band>] Down/Up/Total` line. Called every 30 min by the timer and once per band shift (`Pre-Shift`). |
| `wifi-usage.service` / `wifi-usage.timer` | systemd oneshot + timer that runs the logger every 30 minutes. |
| `wifi_band.logrotate` | Keeps the log small (weekly rotate, keep 8, compress). |
| `report.sh` | Parses `[Usage ...]` lines and prints total GB per band plus a grand total. |
| `install.sh` | Reads `.env`, validates user/interface, writes `/etc/wifi-monitor.conf`, installs the dispatcher, logger, service, timer, and logrotate config. |
| `.env.example` | Template for required/optional settings. Copy to `.env`. |

## Setup

```sh
cd wifi-monitor
cp .env.example .env
# edit .env: WIFI_IFACE (e.g. wlp5s0), NOTIFY_USER (your login), paths if needed
./install.sh
source .env
sudo "$USAGE_LOGGER_BIN"            # sets initial byte baseline
sudo nmcli device reapply "$WIFI_IFACE"  # sets initial band baseline
```

## Daily use

```sh
./report.sh              # totals per band from $LOG_FILE
./report.sh /path/to/log # parse a rotated copy instead
```

## Log format (`/var/log/wifi_band.log` by default)

```text
[TS] [Band Shift] 5 GHz -> 2.4 GHz (reapply)
[TS] [Usage | 30m Summary | 5 GHz] Down: 1.5GiB | Up: 200MiB | Total: 1.7GiB
[TS] [Usage | Pre-Shift | 5 GHz] Down: 100MiB | Up: 50MiB | Total: 150MiB
```

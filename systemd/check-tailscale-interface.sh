#!/bin/bash
# Check Tailscale interface presence and log if missing
# Place on VM as /usr/local/bin/check-tailscale-interface.sh and make executable

LOGFILE="/var/log/check-tailscale-interface.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

if ip link show tailscale0 >/dev/null 2>&1; then
  echo "$DATE - tailscale0 OK" >> "$LOGFILE"
  exit 0
else
  echo "$DATE - tailscale0 MISSING" | tee -a "$LOGFILE" | systemd-cat -t check-tailscale -p warning
  # Optionally attempt to restart tailscaled
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart tailscaled 2>> "$LOGFILE" || true
    echo "$DATE - attempted restart of tailscaled" >> "$LOGFILE"
  fi
  exit 2
fi

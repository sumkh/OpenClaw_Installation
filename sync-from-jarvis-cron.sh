#!/bin/bash
##############################################################################
# sync-from-jarvis-cron.sh
# Purpose: Periodically pull config updates from JARVIS repo and restart if changed
# Usage: Run manually or install as cron job (e.g., 0 2 * * * /opt/openclaw/sync-from-jarvis-cron.sh)
# Note: Requires SSH keys configured for git pull and docker-compose available
##############################################################################

set -euo pipefail

REPO_DIR="/opt/openclaw"
LOG_FILE="/var/log/openclaw/sync-from-jarvis.log"
HOOK_SCRIPT="/opt/openclaw/scripts/post-sync-hook.sh"

# ensure log dir exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

if [[ ! -d "$REPO_DIR" ]]; then
  log "✗ Error: $REPO_DIR not found"
  exit 1
fi

cd "$REPO_DIR" || exit 1

log "Starting JARVIS sync..."

# Fetch and pull from origin
if ! git fetch origin main 2>&1 | tee -a "$LOG_FILE"; then
  log "✗ git fetch failed"
  exit 1
fi

# Check for updates
if git diff HEAD origin/main --quiet; then
  log "✓ No updates available from JARVIS"
  exit 0
fi

log "Updates available. Pulling from JARVIS..."

if ! git pull origin main 2>&1 | tee -a "$LOG_FILE"; then
  log "✗ git pull failed"
  exit 1
fi

log "✓ Successfully pulled updates from JARVIS"

# Optional: Run post-sync hook to restart if config changed
if [[ -x "$HOOK_SCRIPT" ]]; then
  log "Running post-sync-hook..."
  "$HOOK_SCRIPT" 2>&1 | tee -a "$LOG_FILE" || log "⚠ post-sync-hook exited with non-zero status"
else
  log "⚠ post-sync-hook not found or not executable at $HOOK_SCRIPT"
fi

log "JARVIS sync complete"

exit 0

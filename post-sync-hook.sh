#!/bin/bash
##############################################################################
# post-sync-hook.sh
# Purpose: Run after git pull from JARVIS; restart OpenClaw if config changed
# Usage: Called by sync-from-jarvis-cron.sh or other post-pull hooks
# Note: Compares HEAD~1 to HEAD; if config/ differs, restarts docker-compose
##############################################################################

set -euo pipefail

REPO_DIR="/opt/openclaw"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

cd "$REPO_DIR" || exit 1

# Check if config changed between last two commits
if git diff HEAD~1 HEAD --quiet -- config/ 2>/dev/null; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [post-sync-hook] No config changes detected. Skipping restart."
  exit 0
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [post-sync-hook] Config changes detected. Restarting OpenClaw..."

if ! command -v docker-compose >/dev/null 2>&1; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [post-sync-hook] docker-compose not found. Skipping restart." >&2
  exit 1
fi

pushd "$REPO_DIR/docker" >/dev/null

if docker-compose restart; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [post-sync-hook] ✓ OpenClaw restarted successfully"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [post-sync-hook] ✗ Failed to restart OpenClaw" >&2
  exit 1
fi

popd >/dev/null

exit 0

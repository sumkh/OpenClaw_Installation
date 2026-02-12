#!/bin/bash
##############################################################################
# setup-github-sync.sh
# Purpose: Initialize Git for `/opt/openclaw` and configure sync with JARVIS repo
# Usage: sudo ./setup-github-sync.sh [--remote git@github.com:sumkh/JARVIS.git]
# Note: Pushes `/opt/openclaw/config` to JARVIS repo. Ensure SSH keys are configured.
# For pulling updates from JARVIS to VM, use scripts/sync-from-jarvis-cron.sh
##############################################################################

set -euo pipefail

REPO_DIR="/opt/openclaw"
REMOTE_URL="git@github.com:sumkh/JARVIS.git"

usage() { cat <<EOF
Usage: sudo $0 [--remote <git-remote-url>] [--user openclaw]

Default remote: git@github.com:sumkh/JARVIS.git (pushes /opt/openclaw/config to JARVIS)

Examples:
  sudo $0
  sudo $0 --remote git@github.com:sumkh/JARVIS.git --user openclaw
  sudo $0 --remote git@github.com:you/your-config.git --user openclaw
EOF
}

if [[ ${#@} -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || true
fi

# parse args (all optional; defaults provided)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE_URL="$2"; shift 2;;
    --user) USERNAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "${USERNAME:-}" ]]; then
  USERNAME="openclaw"
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

if [[ ! -d "$REPO_DIR" ]]; then
  mkdir -p "$REPO_DIR"
  chown "$USERNAME:$USERNAME" "$REPO_DIR" || true
fi

cd "$REPO_DIR"

if [[ ! -d .git ]]; then
  sudo -u "$USERNAME" git init || git init
fi

# Create .gitignore if missing
if [[ ! -f .gitignore ]]; then
  cat > .gitignore <<'EOF'
# Ignore secrets
/opt/openclaw/secrets/
*.key
*.pem
.env
EOF
fi

# Add remote if not present
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REMOTE_URL" || true
fi

# Stage relevant configuration
git add -A config/ docker/ scripts/*.sh .gitignore || true

if git diff --staged --quiet; then
  echo "No changes to commit"
else
  git commit -m "chore: sync OpenClaw configuration $(date -u +%Y%m%dT%H%M%SZ)" || true
fi

echo "Attempting to push /opt/openclaw/config to JARVIS repo: $REMOTE_URL"
# Attempt push (assumes SSH key or credential is configured)
if git push -u origin main 2>&1; then
  echo "✓ Push succeeded!"
else
  PUSH_RESULT=$?
  if git push -u origin master 2>&1; then
    echo "✓ Push succeeded (to master branch)"
  else
    echo "✗ Push failed — ensure remote branch exists and SSH keys are set up" >&2
    exit $PUSH_RESULT
  fi
fi

echo ""
echo "✓ Git sync configuration complete."
echo "  Remote: $REMOTE_URL"
echo "  Directory: $REPO_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit configuration in JARVIS repo on GitHub"
echo "  2. Set up cron to regularly pull changes from JARVIS (see sync-from-jarvis-cron.sh)"
echo "  3. Optional: link post-sync-hook.sh to restart OpenClaw on config changes"
echo ""

exit 0

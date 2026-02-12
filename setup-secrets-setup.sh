#!/bin/bash
##############################################################################
# setup-secrets-setup.sh
# Purpose: Create `/opt/openclaw/secrets` and set secure permissions
# Usage: sudo ./setup-secrets-setup.sh [--user openclaw]
##############################################################################

set -euo pipefail

SECRETS_DIR="/opt/openclaw/secrets"
OPENCLAW_USER="openclaw"
OPENCLAW_GROUP="openclaw"

log() { echo "[setup-secrets] $@"; }

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

if [[ ${1:-} == "--user" ]]; then
  OPENCLAW_USER=${2:-$OPENCLAW_USER}
fi

# Create secrets directory
mkdir -p "$SECRETS_DIR"
chown root:root "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Ensure openclaw user exists (create system user without login if missing)
if ! id -u "$OPENCLAW_USER" >/dev/null 2>&1; then
  log "User '$OPENCLAW_USER' not found — creating system user"
  useradd -r -s /usr/sbin/nologin -d /opt/openclaw "$OPENCLAW_USER" || true
fi

# Helper to add a secret file securely
add_secret() {
  local src="$1"
  local dest="$SECRETS_DIR/$(basename "$src")"
  if [[ ! -f "$src" ]]; then
    echo "Source secret '$src' not found" >&2
    return 1
  fi
  mv "$src" "$dest"
  chown "$OPENCLAW_USER:$OPENCLAW_GROUP" "$dest" || chown "$OPENCLAW_USER":"$OPENCLAW_USER" "$dest" || true
  chmod 600 "$dest"
  log "Added secret: $dest"
}

echo "Secrets directory created: $SECRETS_DIR"
echo "Permissions: $(stat -c '%a %U:%G' "$SECRETS_DIR")"

cat <<'EOF'
Next steps:
 - Copy your provider credentials into a temporary location on the VM (scp or editor).
 - Run: sudo ./setup-secrets-setup.sh and then move the files into /opt/openclaw/secrets using the prompts
 - Example: sudo mv /tmp/google-sa.json /opt/openclaw/secrets/ && sudo chown openclaw:openclaw /opt/openclaw/secrets/google-sa.json && sudo chmod 600 /opt/openclaw/secrets/google-sa.json

Notes:
 - Files in /opt/openclaw/secrets are owned by root (directory) and individual secret files should be owned by the `openclaw` user with mode 600.
 - Do NOT commit secret files into Git. Use .gitignore (provided) and keep placeholders in repo.
EOF

exit 0

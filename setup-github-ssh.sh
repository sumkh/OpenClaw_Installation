#!/bin/bash
##############################################################################
# setup-github-ssh.sh
# Purpose: Create an SSH key for GitHub, guide user to add it to GitHub,
#          verify SSH auth, and optionally run setup-github-sync.sh to push config.
# Usage: ./setup-github-ssh.sh [--user openclaw] [--remote git@github.com:you/repo.git]
##############################################################################

set -euo pipefail

REMOTE_URL=""
TARGET_USER=""

usage() { cat <<EOF
Usage: $0 [--user <username>] [--remote <git-remote-url>]

Examples:
  # Generate key for current user and show public key
  ./setup-github-ssh.sh

  # Generate key for a specific user and run git sync to remote
  sudo ./setup-github-ssh.sh --user openclaw --remote git@github.com:you/openclaw-config.git
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE_URL="$2"; shift 2;;
    --user) TARGET_USER="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

# Determine target user if not provided
if [[ -z "$TARGET_USER" ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$USER"
  fi
fi

TARGET_HOME=$(eval echo "~$TARGET_USER")
if [[ ! -d "$TARGET_HOME" ]]; then
  echo "User home not found for $TARGET_USER" >&2
  exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
KEY_NAME="openclaw_github"
KEY_PATH="$SSH_DIR/$KEY_NAME"

echo "Target user: $TARGET_USER"
echo "Home: $TARGET_HOME"
echo "SSH dir: $SSH_DIR"

mkdir -p "$SSH_DIR"
chown "$TARGET_USER:$TARGET_USER" "$SSH_DIR" || true
chmod 700 "$SSH_DIR"

if [[ -f "$KEY_PATH" || -f "$KEY_PATH.pub" ]]; then
  echo "An SSH key named $KEY_NAME already exists in $SSH_DIR."
  read -p "Overwrite? (y/N): " resp
  if [[ ! "$resp" =~ ^[Yy]$ ]]; then
    echo "Aborting to avoid overwriting existing key."; exit 1
  fi
  rm -f "$KEY_PATH" "$KEY_PATH.pub"
fi

echo "Generating Ed25519 SSH key for GitHub (no passphrase)..."
sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -C "${TARGET_USER}@$(hostname)-$(date +%Y%m%d)" -f "$KEY_PATH" -N "" >/dev/null

chown "$TARGET_USER:$TARGET_USER" "$KEY_PATH" "$KEY_PATH.pub" || true
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

echo "Public key created at: $KEY_PATH.pub"
echo "----- BEGIN PUBLIC KEY -----"
cat "$KEY_PATH.pub"
echo "----- END PUBLIC KEY -----"

echo
echo "To add this key to GitHub:"
echo "  1) Copy the public key above"
echo "  2) Visit: https://github.com/settings/ssh/new"
echo "  3) Paste the key, give it a descriptive title, and save"

read -p "Press ENTER after you've added the key to GitHub (or Ctrl-C to cancel)" _

echo "Testing SSH connection to GitHub..."
if sudo -u "$TARGET_USER" ssh -T -o StrictHostKeyChecking=no git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "SSH authentication to GitHub verified."
else
  echo "Warning: SSH test did not confirm authentication. The message above may indicate partial success; check that the key was added and that GitHub shows it under your account."
fi

if [[ -n "$REMOTE_URL" ]]; then
  echo "Remote provided: $REMOTE_URL"
  echo "Running setup-github-sync.sh to initialize and push config..."
  if [[ ! -f ./setup-github-sync.sh ]]; then
    echo "setup-github-sync.sh not found in current directory. Please run this script from the scripts/ directory." >&2
    exit 1
  fi
  sudo chmod +x ./setup-github-sync.sh
  sudo ./setup-github-sync.sh --remote "$REMOTE_URL" --user "$TARGET_USER"
fi

echo "All done. Keep your private key ($KEY_PATH) secure."

exit 0

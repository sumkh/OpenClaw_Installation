#!/bin/bash
# SSH hardening for Tailscale-only VM management
# - Ensures key-based auth
# - Restricts SSH to tailscale0 interface
# - Installs and enables fail2ban
# Usage: sudo ./ssh-harden-tailscale.sh

set -euo pipefail

LOG=/var/log/ssh-harden-tailscale.log
exec 3>&1 1>>${LOG} 2>&1

info(){ echo "[INFO] $*" >&3; echo "[INFO] $*" >> ${LOG}; }
warn(){ echo "[WARN] $*" >&3; echo "[WARN] $*" >> ${LOG}; }
err(){ echo "[ERROR] $*" >&3; echo "[ERROR] $*" >> ${LOG}; }

if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (sudo)"
  exit 1
fi

# Determine admin user (invoking user if using sudo)
ADMIN_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "ubuntu")}
ADMIN_HOME=$(eval echo "~${ADMIN_USER}")

info "Target admin user: ${ADMIN_USER} (home: ${ADMIN_HOME})"

# Ensure .ssh exists and authorized_keys present
SSH_DIR="${ADMIN_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

if [[ ! -d "${SSH_DIR}" ]]; then
  info "Creating ${SSH_DIR}"
  mkdir -p "${SSH_DIR}"
  chown ${ADMIN_USER}:${ADMIN_USER} "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
fi

if [[ ! -s "${AUTH_KEYS}" ]]; then
  warn "No authorized_keys found for ${ADMIN_USER}. You must add your public key now to avoid lockout."
  echo "Paste your public SSH key (openssh format) followed by an empty line, then Ctrl+D:" >&3
  cat >> "${AUTH_KEYS}"
  chown ${ADMIN_USER}:${ADMIN_USER} "${AUTH_KEYS}"
  chmod 600 "${AUTH_KEYS}"
  info "Public key written to ${AUTH_KEYS}"
else
  info "Found existing ${AUTH_KEYS} (not modifying)"
fi

# Backup sshd_config
SSHD_CONF="/etc/ssh/sshd_config"
BACKUP="${SSHD_CONF}.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "${SSHD_CONF}" "${BACKUP}"
info "Backed up ${SSHD_CONF} to ${BACKUP}"

# Apply safe defaults
apply_sshd_settings(){
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONF}" || true
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONF}" || true
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "${SSHD_CONF}" || true
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "${SSHD_CONF}" || true
  # Ensure UsePAM is enabled (some distributions rely on it)
  if grep -q '^UsePAM' "${SSHD_CONF}"; then
    sed -i 's/^UsePAM.*/UsePAM yes/' "${SSHD_CONF}"
  else
    echo 'UsePAM yes' >> "${SSHD_CONF}"
  fi
  # Restrict to admin user only
  if grep -q '^AllowUsers' "${SSHD_CONF}"; then
    sed -i '/^AllowUsers/d' "${SSHD_CONF}"
  fi
  echo "AllowUsers ${ADMIN_USER}" >> "${SSHD_CONF}"
  info "sshd_config updated (PermitRootLogin no, PasswordAuthentication no, PubkeyAuthentication yes, AllowUsers ${ADMIN_USER})"
}

apply_sshd_settings

# Restart ssh service (but verify config syntax first)
if sshd -t 2>/dev/null; then
  systemctl restart ssh
  systemctl enable ssh
  info "sshd configuration validated and service restarted"
else
  err "sshd configuration test failed. Restoring backup and exiting."
  cp -a "${BACKUP}" "${SSHD_CONF}"
  exit 1
fi

# UFW rules: allow SSH on tailscale0 only
# Install ufw if missing
if ! command -v ufw >/dev/null 2>&1; then
  info "Installing ufw"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq ufw
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q ufw || true
  fi
fi

# Ensure tailscale interface exists; if not, warn but still add allow for tailscale0
if ip link show tailscale0 >/dev/null 2>&1; then
  info "Found tailscale0 interface"
else
  warn "tailscale0 interface not present. Rules will still be created for tailscale0; review if you use a different interface."
fi

# Add UFW rule for tailscale0
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via Tailscale'
info "UFW: allowed SSH on tailscale0"

# Optionally deny SSH on other common interfaces (safe default but non-destructive)
# We add per-interface deny rules for common interfaces if they exist (eth0, ens*, enp*)
for IF in eth0 ens* enp* wlan0; do
  # Use ip to check existence
  if ip link show $IF >/dev/null 2>&1; then
    # Do not add deny if it's tailscale0
    if [[ "$IF" != "tailscale0" ]]; then
      info "Adding UFW rule to deny SSH on interface $IF"
      # UFW doesn't support interface-based deny with simple syntax on all platforms; we'll create iptables raw rule if needed
      ufw deny in on $IF to any port 22 proto tcp comment 'Deny SSH on $IF'
    fi
  fi
done

# Enable UFW if inactive
UFW_STATUS=$(ufw status | head -n1 || true)
if [[ "$UFW_STATUS" =~ inactive ]]; then
  info "Enabling UFW (with --force)"
  ufw --force enable
else
  info "UFW already active"
fi

# Install and enable Fail2Ban
if ! command -v fail2ban-client >/dev/null 2>&1; then
  info "Installing fail2ban"
  apt-get update -qq
  apt-get install -y -qq fail2ban
fi

# Create basic jail config for sshd
JAIL_FILE="/etc/fail2ban/jail.d/openclaw-ssh.conf"
cat > "${JAIL_FILE}" <<'EOF'
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 600
EOF

systemctl restart fail2ban
systemctl enable fail2ban
info "Fail2Ban configured and running (jail: sshd)"

# Ensure permissions on admin .ssh
chown -R ${ADMIN_USER}:${ADMIN_USER} "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTH_KEYS}"
info "Permissions set on ${SSH_DIR} and ${AUTH_KEYS}"

# Final notes and verification
cat << EOF >&3

SSH hardening completed. Summary:
- Key-based auth enforced; password auth disabled
- Root login disabled
- AllowUsers set to: ${ADMIN_USER}
- SSH allowed on: tailscale0 interface (UFW rule)
- Fail2Ban installed and enabled

IMPORTANT: If you connected to this VM via password and did NOT add your public key to ${AUTH_KEYS}, you may be locked out.
To re-enable password auth temporarily (console access required):
  sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sudo systemctl restart ssh

Verification commands:
  sudo ss -tlnp | grep ssh
  sudo ufw status verbose
  sudo fail2ban-client status sshd
  ssh -v ${ADMIN_USER}@<your-tailscale-ip>

Logs: ${LOG}

EOF

exit 0

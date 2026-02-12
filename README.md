# OpenClaw Secure Installation Guide for VMware Virtual Machines

This guide provides step-by-step instructions for securely installing OpenClaw on a VMware virtual machine with Tailscale access.

## Prerequisites

- VMware ESXi/vCenter with a new Linux VM (Ubuntu 22.04 LTS or CentOS 8+)
- Minimum 4 vCPUs, 8GB RAM, 50GB storage
- Root or sudo access to the VM
- Tailscale account (free or paid)

## Security Best Practices Overview

- Automated system hardening (firewall, SELinux/AppArmor)
- SSH key-based authentication only
- Automated security updates
- Fail2Ban for brute-force protection
- Tailscale VPN for secure remote access
- Regular security audits and monitoring
- Principle of least privilege

## Installation Steps

### Step 1: Initial Setup & System Hardening (2-3 minutes)
Run the first script to harden your system:
```bash
sudo chmod +x 01-initial-setup.sh
sudo ./01-initial-setup.sh
```

**What it does:**
- Updates system packages
- Configures SSH security (disables root login, password auth)
- Sets up firewall (UFW)
- Enables automatic security updates
- Configures SELinux (if on CentOS/RHEL)
- Sets up system monitoring

### Step 2: Install OpenClaw (8-15 minutes)
Run the OpenClaw installation script (official Docker-based):
```bash
sudo chmod +x 02-install-openclaw.sh
sudo ./02-install-openclaw.sh
```

**What it does:**
- Installs Docker and Docker Compose
- Clones the official OpenClaw repository from GitHub
- Builds the Docker image with all dependencies
- Creates dedicated service account (openclaw user)
- Generates secure gateway token
- Configures docker-compose with environment variables
- Creates systemd service for auto-management
- Starts the gateway service (runs on port 18789)

**After installation:**
- Gateway is running as a systemd service
- Config and workspace are at `/opt/openclaw/.openclaw`
- Optional: Run the onboarding wizard to configure provider channels
  ```bash
  sudo docker compose -f /opt/openclaw/docker-compose.yml run --rm openclaw-cli onboard
  ```

### Step 3: Setup Tailscale VPN (3-5 minutes)
Secure your access with Tailscale:
```bash
sudo chmod +x 03-setup-tailscale.sh
sudo ./03-setup-tailscale.sh
```

**During this script:**
- You'll see a Tailscale authentication URL
- Login to your Tailscale account via the URL
- Approve the device
- Script automatically configures exit node (optional)

### Step 4: Post-Installation Security Hardening (2-3 minutes)
Apply additional security measures:
```bash
sudo chmod +x 04-post-install-security.sh
sudo ./04-post-install-security.sh
```

**What it does:**
- Configures AppArmor profiles (Ubuntu) or SELinux policies (CentOS)
- Sets up audit logging for OpenClaw
- Configures intrusion detection (Aide/Aide-rk)
- Enables system logging to remote syslog (optional)
- Sets up certificate management

### Step 5: Verification & Testing
Verify your installation:
```bash
sudo systemctl status openclaw
sudo tailscale status
sudo netstat -tlnp | grep LISTEN
```

## Post-Installation Security Checklist

- [ ] SSH keys are properly configured
- [ ] Password authentication is disabled in SSH
- [ ] Firewall is active and rules are applied
- [ ] OpenClaw service is running
- [ ] Tailscale is connected and authenticated
- [ ] Automated updates are scheduled
- [ ] Backups are configured
- [ ] Monitoring alerts are set up

## Maintenance & Regular Tasks

### Daily
- Monitor OpenClaw status: `sudo systemctl status openclaw`
- Check Tailscale connection: `sudo tailscale status`

### Weekly
- Review security logs: `sudo journalctl -u openclaw -n 100`
- Check for service errors: `sudo systemctl status openclaw`

### Monthly
- Run security audit: `sudo ./scripts/04-post-install-security.sh --audit`
- Update packages: `sudo apt update && sudo apt upgrade`

### Quarterly
- Review and rotate SSH keys if necessary
- Audit Tailscale connected devices
- Review firewall rules

## Troubleshooting

### OpenClaw Service Won't Start
```bash
sudo systemctl status openclaw
sudo journalctl -u openclaw -n 50
```

### Tailscale Connection Issues
```bash
sudo tailscale status
sudo tailscale ping <device-name>
```

### SSH Connection Denied
- Ensure Tailscale is running
- Verify SSH keys are in ~/.ssh/authorized_keys
- Check UFW rules: `sudo ufw status`

### Performance Issues
- Check resource usage: `top` or `htop`
- Monitor disk space: `df -h`
- Review Docker container status: `docker ps -a`

## Security Alerts to Watch For

1. Failed login attempts in `/var/log/auth.log`
2. Service restart failures in systemd journal
3. Disk space running low
4. OpenClaw returning non-zero exit codes
5. Unexpected network connections

## Updating and Rollback

### Update OpenClaw
```bash
sudo systemctl stop openclaw
sudo kubectl pull openclaw:latest
sudo systemctl start openclaw
```

### Rollback Procedure
Backups are stored in `/var/backups/openclaw/`. To restore:
```bash
sudo systemctl stop openclaw
sudo tar -xzf /var/backups/openclaw/backup-YYYYMMDD.tar.gz -C /opt/openclaw/
sudo systemctl start openclaw
```

## Additional Security Considerations

### 1. Network Segmentation
- Place VM on a separate VLAN if possible
- Restrict access at the hypervisor level
- Use network ACLs

### 2. Regular Backups
- Use VMware snapshots before major updates
- Backup OpenClaw configuration:
  ```bash
  tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz /opt/openclaw/config/
  ```

### 3. Monitoring
- Set up centralized log aggregation
- Configure alerts for critical errors
- Monitor resource utilization

### 4. Incident Response
- Keep incident response playbook
- Document all security events
- Maintain audit trails for compliance

## Support and Resources

- OpenClaw Documentation: [official docs link]
- Tailscale Documentation: https://tailscale.com/kb/
- Ubuntu Security: https://ubuntu.com/security
- CentOS Security: https://www.centos.org/

## File Structure

```
scripts/
├── 01-initial-setup.sh              # System hardening
├── 02-install-openclaw.sh           # OpenClaw installation
├── 03-setup-tailscale.sh            # Tailscale VPN
├── 04-post-install-security.sh      # Additional security
├── 05-maintenance.sh                # Maintenance tasks
├── config/
│   ├── openssh-hardened.conf        # SSH hardening config
│   ├── ufw-rules.conf               # Firewall rules
│   └── openclaw-defaults            # OpenClaw defaults
├── logs/                             # Installation logs
└── README.md                         # This file
```

## Quick Start Summary

```bash
# Download all scripts
git clone <repo-url> ~/openclaw-secure-setup
cd ~/openclaw-secure-setup/scripts

# Make all scripts executable
chmod +x *.sh

# Run in sequence
sudo ./01-initial-setup.sh
sudo ./02-install-openclaw.sh
sudo ./03-setup-tailscale.sh
sudo ./04-post-install-security.sh

# Verify installation
sudo systemctl status openclaw
sudo tailscale status
```

## Important Security Notes

⚠️ **CRITICAL**: 
- Never disable SELinux/AppArmor unless absolutely necessary
- Always use SSH keys, never rely on passwords
- Keep Tailscale updated
- Regularly audit system logs
- Maintain regular backups
- Test backup restoration procedures

---

**Last Updated**: February 12, 2026
**Version**: 1.0

## Secrets, External APIs and Docker

This package includes Docker scaffolding and helper scripts to securely manage third-party credentials (Google service account JSON, WhatsApp API tokens, etc.) and push configuration to GitHub.

- Secrets directory (created by `setup-secrets-setup.sh`): `/opt/openclaw/secrets`
- Git sync helper: `setup-github-sync.sh` — initialize and push `/opt/openclaw/config` to your GitHub remote
- Docker scaffolding: `docker/Dockerfile` and `docker/docker-compose.yml` (local development)

Recommended workflow (local VM):

1. Run the secrets setup script on the VM:

```bash
sudo chmod +x setup-secrets-setup.sh
sudo ./setup-secrets-setup.sh
```

2. Copy provider credentials to the VM (temporary location) and move them into `/opt/openclaw/secrets/`.
  Ensure each secret file is owned by the `openclaw` user and has `600` permissions.

3. Use the provided `docker/docker-compose.yml` which mounts `/opt/openclaw/secrets` read-only into the container and exposes two sample env vars:

```
GOOGLE_APPLICATION_CREDENTIALS=/opt/openclaw/secrets/google-sa.json
WHATSAPP_CRED_FILE=/opt/openclaw/secrets/whatsapp.conf
```

4. Initialize Git and push configs:

```bash
sudo chmod +x setup-github-sync.sh
sudo ./setup-github-sync.sh --remote git@github.com:youruser/openclaw-config.git --user openclaw
```

Security notes:

- Never commit secret files into Git. Use `.gitignore` (included) and store templates only.
- Rotate credentials regularly and use least-privilege service accounts.
- For future cloud deployments, migrate secrets to a secrets manager (AWS Secrets Manager, GCP Secret Manager, or Vault).

## WhatsApp & Google API Integration (brief)

OpenClaw can interface with WhatsApp via official provider APIs (Meta/WhatsApp Cloud API or Twilio). It can also use Google APIs via a service account JSON. Store these credentials as files in `/opt/openclaw/secrets` and reference them via environment variables inside the container.

WhatsApp examples:

- `whatsapp.conf` (key/value or JSON depending on provider):

```
WHATSAPP_API_TOKEN=abcd1234
WHATSAPP_PHONE_ID=1234567890
WEBHOOK_SECRET=xxxxxxxx
```

- For Meta/WhatsApp Cloud API, verify webhooks using the provided verification token and keep the token in `whatsapp.conf`.

Google example (service account JSON):

- Place `google-sa.json` in `/opt/openclaw/secrets/` and set `GOOGLE_APPLICATION_CREDENTIALS=/opt/openclaw/secrets/google-sa.json` in the container.

Example docker-compose usage (local dev):

```bash
cd scripts/docker
docker build -t openclaw:local .
docker-compose up -d
```

Replace placeholder app files in `scripts/docker/app/` with real OpenClaw runtime or modify the `Dockerfile` to install the official runtime.

## CI/CD — GitHub Actions

This repository includes a GitHub Actions workflow at `.github/workflows/docker-publish.yml` that builds and publishes the Docker image from `scripts/docker` to Docker Hub.

- **Required repository secrets** (Settings → Secrets → Actions):
  - `DOCKERHUB_USERNAME` : Docker Hub username
  - `DOCKERHUB_PASSWORD` : Docker Hub password or access token
  - `DOCKERHUB_REPO`     : Docker Hub repository in `owner/name` format (used on push to `main`)

- **How tags are chosen**:
  - When run via `workflow_dispatch` you supply `repo` and `tag` inputs.
  - When triggered on `push` to `main` the workflow uses `DOCKERHUB_REPO` and a short commit SHA as the tag.

- **Manual run (Actions → Build and publish Docker image)**: choose `repo` and `tag` parameters for a one-off build.

- **Local testing**: you can still use the provided `deploy-to-dockerhub.sh` script to build and push locally (see `scripts/deploy-to-dockerhub.sh`).

[![Docker Publish](https://github.com/sumkh/OpenClaw_Installation/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/sumkh/OpenClaw_Installation/actions/workflows/docker-publish.yml)

Set secrets via GitHub CLI (optional):

```bash
# login first: gh auth login
gh secret set DOCKERHUB_USERNAME --body 'your-docker-username'
gh secret set DOCKERHUB_PASSWORD --body 'your-docker-password-or-token'
gh secret set DOCKERHUB_REPO --body 'youruser/openclaw'
```

Notes:
- The workflow logs into Docker Hub using the credentials stored in repository secrets; prefer using a Docker Hub access token over your account password.
- Keep `DOCKERHUB_REPO` consistent with the repository you want the image published to (owner/name).

## GitOps Workflow — Configuration Sync with JARVIS

This setup uses **GitOps best practices**: configuration-as-code stored in the JARVIS repository (https://github.com/sumkh/JARVIS.git) with version control, automatic syncs, and rollback capability.

### Architecture

- **OpenClaw_Installation/** — installation and security scripts (immutable reference)
- **JARVIS/** — runtime configuration synced from VM (mutable, version-controlled at `sumkh/JARVIS`)
- **openclaw/** — upstream reference (official OpenClaw repo for latest updates)

### Initial Configuration Push (VM → GitHub)

After installing OpenClaw on the VM, push the initial configuration to JARVIS:

```bash
# Make script executable and push config to JARVIS repo
sudo chmod +x scripts/setup-github-sync.sh
sudo ./scripts/setup-github-sync.sh

# Or explicitly specify a different repo:
sudo ./scripts/setup-github-sync.sh --remote git@github.com:yourusername/your-config.git
```

This script:
- Initializes Git in `/opt/openclaw`
- Stages config and docker files
- Commits and pushes to the JARVIS repo (default) or your own repo
- Requires SSH keys configured on the VM for Git authentication

### Ongoing Configuration Management

**Edit configuration in GitHub:**
1. Browse to https://github.com/sumkh/JARVIS/tree/main/config (or your repo)
2. Edit config files directly in GitHub web UI or clone locally
3. Commit and push changes

**Pull updates to VM:**
Set up a cron job to periodically pull latest config from JARVIS:

```bash
# Copy the sync script to /opt/openclaw (so it can be called from cron)
sudo cp scripts/sync-from-jarvis-cron.sh /opt/openclaw/
sudo chmod +x /opt/openclaw/sync-from-jarvis-cron.sh

# Add to root crontab (runs daily at 2 AM):
sudo crontab -e
# Add line:
0 2 * * * /opt/openclaw/sync-from-jarvis-cron.sh
```

Or run manually:
```bash
sudo /opt/openclaw/sync-from-jarvis-cron.sh
```

### Auto-Restart on Config Changes

The `post-sync-hook.sh` script automatically restarts OpenClaw containers if the `config/` directory changes:

```bash
sudo chmod +x scripts/post-sync-hook.sh

# It's called automatically by sync-from-jarvis-cron.sh
# To test manually:
sudo scripts/post-sync-hook.sh
```

What it does:
- Compares the previous commit to the current commit
- If `config/` differs, runs `docker-compose restart` to apply changes
- Logs all actions to `/var/log/openclaw/sync-from-jarvis.log`

### Rollback & Version History

Since configuration is version-controlled:

```bash
cd /opt/openclaw

# View commit history
git log --oneline config/

# Revert to a previous config version
git revert <commit-hash>
git push origin main

# Or hard reset (VM only, don't push):
git reset --hard <commit-hash>
```

### Helper Scripts

| Script | Purpose |
|--------|---------|
| `setup-github-sync.sh` | Initial git setup and push to JARVIS/GitHub |
| `sync-from-jarvis-cron.sh` | Periodic pull from JARVIS (run via cron) |
| `post-sync-hook.sh` | Auto-restart containers on config change |

### Security Best Practices for JARVIS Repo

- **Never commit secrets** — use `.gitignore` and store credentials in `/opt/openclaw/secrets` (not in Git)
- **Use templates** — include `.env.example` and `secrets-templates/` in Git; actual values on VM only
- **SSH over HTTPS** — configure Git to use SSH keys for authentication (avoid storing tokens)
- **Audit changes** — review commit history and changes before pulling to production
- **Automated alerts** — optional: set up GitHub webhooks or Slack notifications on pushes

### Future Enhancements

- **Multi-environment** — branches for `dev`, `staging`, `main`; different configs per branch
- **Secrets manager** — migrate to AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault
- **Approval workflows** — require PR reviews before config changes are merged
- **Automated tests** — validate config syntax and schema before pulling

---

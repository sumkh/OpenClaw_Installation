# OpenClaw Secure Deployment - Complete Integration Guide

## Overview

This guide shows how to integrate:
1. **Tailscale ACL Isolation** - Restrict OpenClaw network access
2. **VMware Shared Folders** - Store API credentials securely
3. **Docker Containers** - Run OpenClaw with proper isolation
4. **All 5 Installation Scripts** - Complete security hardening flow

---

## Architecture Diagram

```
TAILSCALE NETWORK (100.64.0.0/10)
├─ Physical Device 1 (100.64.x.1) ← Can reach OpenClaw:18789
├─ Physical Device 2 (100.64.x.2) ← Can reach OpenClaw:18789
├─ Host Machine (100.64.x.100) ← Can reach OpenClaw:18789
└─ OpenClaw VM (100.64.x.101) ← ISOLATED via ACL
    │
    ├─ ACL RESTRICTIONS:
    │  ├─ ✓ Can reach Google APIs (HTTPS:443)
    │  ├─ ✓ Can reach WhatsApp APIs (HTTPS:443)
    │  ├─ ✓ Can query DNS (53)
    │  ├─ ✓ Can be accessed on port 18789
    │  ├─ ✗ CANNOT reach other Tailscale devices
    │  └─ ✗ CANNOT reach SSH/File services on network
    │
    └─ VM LOCAL STORAGE
       │
       └─ VMware Shared Folder Mount
          ├─ Path: /mnt/vmshared (NFSv4/CIFS/VMHGFS)
          ├─ Contents:
          │  ├─ .whatsapp-config.json (600 permissions)
          │  ├─ .google-credentials.json (600 permissions)
          │  └─ .env.secrets (600 permissions)
          │
          └─ Docker Volume Mount (read-only)
             └─ Inside container: /opt/openclaw/secrets:ro
                ├─ Application can READ credentials
                ├─ Application CANNOT WRITE/MODIFY
                └─ Host maintains control of secrets
```

---

## Part 1: Pre-Deployment Checklist

### Infrastructure Setup (Week -1)

- [ ] **Tailscale Account Setup**
  - [ ] Create Tailscale account at https://login.tailscale.com
  - [ ] Add existing physical devices to mesh
  - [ ] Connect host machine to Tailscale
  - [ ] Verify all devices are online
  - [ ] Note your tailnet name (e.g., "my-family.tailnet-xxxxx")

- [ ] **VMware Host Preparation**
  - [ ] Allocate storage for shared folder (50GB+)
  - [ ] Create directory: `/var/shared/openclaw-secrets`
  - [ ] Export via NFS, CIFS, or VMHGFS
  - [ ] Verify network connectivity to VM network

- [ ] **Secrets Collection**
  - [ ] Obtain WhatsApp Business API credentials
  - [ ] Obtain Google API credentials
  - [ ] Collect other API keys needed
  - [ ] Store temporary copies in secure location

- [ ] **Tailscale API Token**
  - [ ] Generate API token: https://login.tailscale.com/admin/settings/personal
  - [ ] Save with note: "For OpenClaw ACL automation"
  - [ ] Token should start with `tskey-api-`

### VM Provisioning (Week 0)

- [ ] **Create OpenClaw VM**
  - [ ] Follow VMWARE-UBUNTU-24-SETUP-GUIDE.md
  - [ ] Specs: 8vCPU, 18GB RAM, 50GB storage
  - [ ] OS: Ubuntu 24.04.3 LTS
  - [ ] Network: VMXNET3 NIC (recommended)

- [ ] **VMware Shared Folder Configuration**
  - [ ] Configure shared folder export on host
  - [ ] Verify shared folder is accessible

- [ ] **OpenClaw VM Network**
  - [ ] Verify internet connectivity
  - [ ] Verify Tailscale can be installed

---

## Part 2: Installation Flow (Week 0-1)

### Step 1: Run Initial Setup (5-10 minutes)
```bash
# SSH to OpenClaw VM
ssh ubuntu@<NEW_VM_IP>

# Download installation scripts
git clone https://github.com/sumkh/OpenClaw_Installation.git
cd OpenClaw_Installation

# Run initial hardening
sudo chmod +x *.sh
sudo ./01-initial-setup.sh

# Output: System hardened, UFW firewall enabled, audit logging setup
```

**What happens:**
- ✓ UFW firewall configured (port 22 open for SSH)
- ✓ Fail2Ban installed (brute force protection)
- ✓ AppArmor enabled
- ✓ Auditd logging configured
- ✓ Kernel hardening applied

### Step 2: Install Docker & OpenClaw (15-20 minutes)
```bash
sudo ./02-install-openclaw.sh

# Follow prompts:
# Enter Tailscale API endpoint: (press Enter for default)
# Enter OpenClaw gateway token: (auto-generated, save for later)
```

**What happens:**
- ✓ Docker & docker-compose installed
- ✓ Official OpenClaw repo cloned
- ✓ Docker image built (first run takes longer)
- ✓ .env file generated with secure token
- ✓ docker-compose.yml configured
- ✓ Systemd service created (`openclaw.service`)

**Verification:**
```bash
sudo systemctl status openclaw
# Expected: active (running)
```

### Step 3: Mount Shared Folder (5 minutes)
```bash
# Create mount point
sudo mkdir -p /mnt/vmshared

# Identify host IP (ask VMware admin or check host network)
HOST_IP="192.168.1.100"

# Mount shared folder (NFS example)
sudo mount -t nfs4 ${HOST_IP}:/var/shared/openclaw-secrets /mnt/vmshared

# Verify
ls -la /mnt/vmshared/
# Should list: .whatsapp-config.json, .google-credentials.json, .env.secrets

# Create symlink for Docker access
sudo ln -s /mnt/vmshared /opt/openclaw/secrets

# Verify
ls -la /opt/openclaw/secrets/
```

**What happens:**
- ✓ Shared folder mounted at /mnt/vmshared
- ✓ Symlink created for Docker access
- ✓ Secrets accessible to containers

**Persistence (auto-mount on reboot):**
```bash
# Add to /etc/fstab:
sudo bash -c 'echo "192.168.1.100:/var/shared/openclaw-secrets /mnt/vmshared nfs4 defaults,ro,hard,intr,_netdev 0 0" >> /etc/fstab'

# Test:
sudo mount -a
```

### Step 4: Join Tailscale Network (2-3 minutes)
```bash
sudo ./03-setup-tailscale.sh

# Follow prompts to authenticate
# Visit the URL provided to authorize device
# Accept with your Tailscale account
```

**What happens:**
- ✓ Tailscale daemon installed
- ✓ VM joins your existing Tailscale mesh
- ✓ VM gets Tailscale IP (100.64.x.101)
- ✓ Encrypted tunnel to all trusted devices established

**Verification:**
```bash
sudo tailscale status
# Expected: Shows your IP (100.64.x.101) and status "Online"

# From another Tailscale device (physical device or host):
tailscale ping 100.64.x.101
# Expected: pong (connection works)
```

### Step 5: Configure Tailscale ACL Isolation (3-5 minutes)
```bash
# Generate and apply ACL policy
sudo chmod +x ./configure-tailscale-acl.sh

# Option A: Automatic (Recommended)
sudo ./configure-tailscale-acl.sh --auto --api-token "tskey-api-xxxxx"

# Option B: Manual
sudo ./configure-tailscale-acl.sh
# Copy policy from /opt/openclaw/tailscale/acl-policy.hujson
# Apply at: https://login.tailscale.com/admin/acls
```

**What happens:**
- ✓ ACL policy generated
- ✓ Policy applies restrictions:
  - Trusted devices can reach 18789 (gateway)
  - OpenClaw can reach internet (443, 53)
  - OpenClaw CANNOT reach other devices
  - SSH restricted to admins only

**Wait 30 seconds for rules to take effect.**

**Verify ACL is working:**
```bash
# On OpenClaw VM:
# Should SUCCEED - Reach internet
curl -I https://www.google.com
# Expected: HTTP response

# Should FAIL - Reach other device
timeout 5 nc -zv 100.64.x.1 22
# Expected: Connection timed out

# From trusted device:
# Should SUCCEED - Access gateway
curl http://100.64.x.101:18789/health
# Expected: 200 OK
```

### Step 6: Security Hardening (5 minutes)
```bash
sudo ./04-post-install-security.sh

# Configures:
# - Docker daemon security (enable userns-remap)
# - AppArmor Docker profile
# - Audit logging for sensitive operations
# - Rate limiting on iptables
```

**What happens:**
- ✓ Docker daemon hardened
- ✓ Container isolation enhanced
- ✓ Logging configured for security events
- ✓ Network rate limiting applied

### Step 7: Setup Maintenance Tasks (1 minute)
```bash
sudo ./05-maintenance.sh

# Sets up:
# - Health checks for OpenClaw service
# - Backup scripts for .openclaw data
# - Log rotation
# - Automated update checks
```

---

## Part 3: Secrets Configuration

### Step 1: Add API Credentials to Shared Folder (on VMware Host)

```bash
# On VMware host machine:
cd /var/shared/openclaw-secrets

# Create WhatsApp config
cat > .whatsapp-config.json << 'EOF'
{
  "account_id": "YOUR_WHATSAPP_ACCOUNT_ID",
  "access_token": "YOUR_WHATSAPP_ACCESS_TOKEN",
  "phone_number_id": "YOUR_PHONE_NUMBER_ID",
  "webhook_token": "YOUR_WEBHOOK_VERIFY_TOKEN"
}
EOF
chmod 600 .whatsapp-config.json

# Add Google credentials
cp ~/Downloads/google-credentials.json .google-credentials.json
chmod 600 .google-credentials.json

# Create .env.secrets
cat > .env.secrets << 'EOF'
WHATSAPP_API_KEY=xxx
GOOGLE_API_KEY=yyy
EOF
chmod 600 .env.secrets

# Verify
ls -la | grep -E "\.whatsapp|\.google|\.env"
```

### Step 2: Update docker-compose.yml (on OpenClaw VM)

```bash
# Edit /opt/openclaw/docker-compose.yml
# Add volume mounts:

volumes:
  - /opt/openclaw/secrets:/opt/openclaw/secrets:ro
  
# Add environment variables:

environment:
  - OPENCLAW_SECRETS_PATH=/opt/openclaw/secrets
  - OPENCLAW_WHATSAPP_CONFIG_FILE=/opt/openclaw/secrets/.whatsapp-config.json
  - OPENCLAW_GOOGLE_CREDENTIALS_FILE=/opt/openclaw/secrets/.google-credentials.json
```

### Step 3: Restart OpenClaw with Secrets

```bash
# On OpenClaw VM:
sudo docker compose restart openclaw-gateway

# Verify secrets accessible
sudo docker compose exec openclaw-gateway \
  cat /opt/openclaw/secrets/.whatsapp-config.json

# Should show: JSON content (not permission denied)
```

---

## Part 4: Verification & Testing

### Network Isolation Verification

```bash
# On OpenClaw VM - Should SUCCEED:
echo "=== SUCCESS TESTS ==="
curl -I https://api.openai.com
curl -I https://api.google.com
nslookup google.com

# On OpenClaw VM - Should FAIL (timeout):
echo "=== FAILURE TESTS (expected to timeout) ==="
timeout 5 ssh ubuntu@100.64.x.1 # Other device
timeout 5 nc -zv 100.64.x.1 22
timeout 5 nc -zv 100.64.x.2 445

# From trusted device - Should SUCCEED:
echo "=== ACCESS FROM TRUSTED DEVICE ==="
curl http://100.64.x.101:18789/health
ssh ubuntu@100.64.x.101
```

### Secrets Access Verification

```bash
# Verify Docker can read secrets
sudo docker compose exec openclaw-gateway \
  ls -la /opt/openclaw/secrets/

# Verify cannot modify (read-only mount)
sudo docker compose exec openclaw-gateway \
  touch /opt/openclaw/secrets/test.txt
# Expected: Permission denied

# Verify environment variables loaded
sudo docker compose exec openclaw-gateway \
  env | grep -i OPENCLAW_SECRETS
```

### Service Health Check

```bash
# Check all services running
sudo systemctl status openclaw
sudo docker compose ps

# Check logs
sudo docker compose logs --follow openclaw-gateway

# Access gateway UI
# From trusted device: http://100.64.x.101:18789
```

---

## Part 5: Post-Deployment Operations

### Regular Maintenance

```bash
# Daily: Check service status
sudo systemctl status openclaw

# Weekly: Review security logs
sudo tail -f /var/log/audit/audit.log | grep -i openclaw

# Monthly: Backup configuration
sudo ./05-maintenance.sh

# Quarterly: Rotate API credentials
# Update files in /var/shared/openclaw-secrets/
# Restart: sudo docker compose restart
```

### Credential Rotation

```bash
# On VMware host:

# 1. Update credentials in shared folder
nano /var/shared/openclaw-secrets/.whatsapp-config.json
nano /var/shared/openclaw-secrets/.google-credentials.json

# 2. On OpenClaw VM - restart for changes to take effect
ssh ubuntu@100.64.x.101
sudo docker compose restart openclaw-gateway

# 3. Verify new credentials working
sudo docker compose logs openclaw-gateway
```

### Monitoring & Alerts

```bash
# Set up monitoring (optional)

# Health check endpoint:
curl http://100.64.x.101:18789/health

# Tailscale connection status:
sudo tailscale status

# Log monitoring:
sudo journalctl -u openclaw -f
```

---

## Part 6: Security Summary

### What's Protected

| Component | Protection | How |
|-----------|-----------|-----|
| **Secrets** | Isolated | Stored on host, not in image |
| **Credentials** | Encrypted | TLS/SSH for transport |
| **Network** | Restricted | Tailscale ACL blocks unauthorized access |
| **Container** | Hardened | AppArmor, userns-remap, read-only mounts |
| **OS** | Hardened | UFW, Fail2Ban, kernel tuning, auditd |

### Attack Surface Restrictions

✗ **OpenClaw CANNOT:**
- Reach other Tailscale devices
- SSH to other devices
- Access file shares (SMB/NFS)
- Reach internal databases
- Exfiltrate secrets to network

✓ **OpenClaw CAN:**
- Access Google APIs (HTTPS)
- Access WhatsApp APIs (HTTPS)
- Query DNS for domain resolution
- Be accessed by trusted devices on :18789
- Write to its own containers (/opt/openclaw)

### Secrets Security

- ✓ Stored on VMware host (not in Docker image)
- ✓ Mounted read-only to container
- ✓ Permissions: 600 (owner only)
- ✓ Transported over Tailscale VPN (encrypted)
- ✓ Never logged or exposed in docker-compose

---

## Troubleshooting Quick Guide

### Problem: Cannot reach OpenClaw from trusted device
```bash
# From trusted device:
tailscale ping 100.64.x.101
curl -v http://100.64.x.101:18789/health

# On OpenClaw VM:
sudo systemctl status openclaw
sudo docker compose ps
```

### Problem: OpenClaw cannot reach internet APIs
```bash
# On OpenClaw VM:
curl -v https://www.google.com
nslookup google.com

# Check Tailscale status:
sudo tailscale status
sudo tailscale down && sudo tailscale up
```

### Problem: Cannot read credentials from shared folder
```bash
# Verify mount
mount | grep vmshared

# Verify permissions on VM
ls -la /opt/openclaw/secrets/

# Verify permissions on host
ls -la /var/shared/openclaw-secrets/

# Restart mount
sudo systemctl restart mnt-vmshared.mount
```

### Problem: ACL not working as expected
```bash
# Wait 30+ seconds after applying ACL
# Check admin console: https://login.tailscale.com/admin/acls

# Force reconnect:
sudo tailscale logout
sudo tailscale up

# Run verification:
sudo /opt/openclaw/tailscale/verify-acl-policy.sh
```

---

## Complete Installation Timeline

| Phase | Duration | Scripts | Output |
|-------|----------|---------|--------|
| **Pre-deploy** | 1 week | N/A | Tailscale account, VM host ready |
| **VM Creation** | 1 hour | VMWARE guide | Ubuntu 24.04 VM ready |
| **System setup** | 5 min | 01-*.sh | OS hardened, firewall up |
| **OpenClaw** | 15 min | 02-*.sh | Docker image built, systemd service |
| **Shared folder** | 5 min | Mount commands | Secrets accessible |
| **Tailscale join** | 3 min | 03-*.sh | VM in mesh (100.64.x.101) |
| **ACL isolation** | 3 min | configure-acl.sh | Network restricted |
| **Security** | 5 min | 04-*.sh | Docker hardened |
| **Maintenance** | 1 min | 05-*.sh | Health checks + backups |
| **Verification** | 5 min | Test commands | All systems working |
| **Total** | ~40 minutes | | **Production Ready** |

---

## Files Reference

| File | Purpose |
|------|---------|
| `01-initial-setup.sh` | OS hardening, firewall, audit |
| `02-install-openclaw.sh` | Docker, OpenClaw build, systemd |
| `03-setup-tailscale.sh` | VPN setup, mesh join |
| `configure-tailscale-acl.sh` | Network isolation policy |
| `04-post-install-security.sh` | Container hardening |
| `05-maintenance.sh` | Health checks, backups |
| `VMWARE-UBUNTU-24-SETUP-GUIDE.md` | VM configuration |
| `TAILSCALE-INTEGRATION.md` | Network architecture |
| `TAILSCALE-ACL-CONFIGURATION.md` | ACL policy details |
| `VMWARE-SHARED-FOLDERS-SECRETS.md` | Credentials storage |

---

## Access Points After Deployment

| Service | Access From | Address | Port | Use Case |
|---------|-------------|---------|------|----------|
| **Gateway** | Trusted devices | 100.64.x.101 | 18789 | Main UI/API |
| **SSH** | Admins | 100.64.x.101 | 22 | Management |
| **Health** | Trusted devices | 100.64.x.101 | 18789 | Monitoring |
| **Secrets** | Docker only | /opt/openclaw/secrets | N/A | Credentials |

---

## Next Steps After Deployment

1. ✅ Configure integrations (WhatsApp, Google, Discord, etc.)
2. ✅ Test end-to-end workflows from trusted devices
3. ✅ Set up monitoring/alerting
4. ✅ Document your deployment specifics
5. ✅ Schedule quarterly credential rotation
6. ⊘ (Optional) Add backup/disaster recovery

**You now have a secure, isolated OpenClaw deployment!** 🎉

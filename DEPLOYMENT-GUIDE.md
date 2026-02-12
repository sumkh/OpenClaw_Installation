# OpenClaw Secure Deployment Guide - Complete Reference

## Executive Summary

This guide provides complete step-by-step instructions for deploying OpenClaw securely on VMware virtual machines with Tailscale VPN integration. The deployment follows security best practices including system hardening, network isolation, container security, and automated monitoring.

---

## Table of Contents

1. [Prerequisites & Planning](#prerequisites--planning)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Network Architecture](#network-architecture)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Production Considerations](#production-considerations)
7. [Troubleshooting & Support](#troubleshooting--support)
8. [Operational Runbooks](#operational-runbooks)

---

## Prerequisites & Planning

### System Requirements

#### Minimum Specifications
- **CPU:** 4 vCPUs (8+ recommended for production)
- **RAM:** 8GB (16GB+ recommended)
- **Storage:** 50GB (100GB+ for production with logs/backups)
- **Network:** Internet connectivity for package updates

#### Network Requirements
- Outbound HTTPS (443/tcp) - for Tailscale, package updates
- Inbound Tailscale (41641/udp) - for VPN mesh
- Optional: Inbound SSH (22/tcp) during bootstrap only

### Software Requirements

#### Supported Operating Systems
- Ubuntu 22.04 LTS (recommended)
- Ubuntu 20.04 LTS
- CentOS Stream 9
- RHEL 8.x or 9.x

#### Required Accounts
- Tailscale account (free.tailscale.com or paid)
- VMware ESXi/vCenter access
- Root or sudo privileges on VM

### Planning Considerations

#### Network Design
```
┌─────────────────────────────────────────────────┐
│           Internet/External Network             │
└──────────────────────┬──────────────────────────┘
                       │
            ┌──────────────────────┐
            │   Tailscale VPN      │
            │   (Encrypted Mesh)   │
            └──────────────────────┘
                       │
┌──────────────────────┼──────────────────────────┐
│              VMware Environment                 │
│  ┌────────────────────────────────────────┐   │
│  │   OpenClaw VM (Secured)                │   │
│  │  ┌──────────────────────────────────┐  │   │
│  │  │ Firewall (UFW/FirewallD)         │  │   │
│  │  │ - Default Deny Incoming          │  │   │
│  │  │ - Allow Tailscale VPN (41641)    │  │   │
│  │  │ - Allow SSH via Tailscale        │  │   │
│  │  └──────────────────────────────────┘  │   │
│  │  ┌──────────────────────────────────┐  │   │
│  │  │ OpenClaw Application             │  │   │
│  │  │ - Hardened SSH (key-only)        │  │   │
│  │  │ - Docker Containers              │  │   │
│  │  │ - SSL/TLS Encrypted              │  │   │
│  │  └──────────────────────────────────┘  │   │
│  └────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

#### High Availability Considerations

For HA deployment:
1. Deploy multiple VMs with same configuration
2. Use load balancer in front (if needed)
3. Centralize databases/storage
4. Replicate backups across locations
5. Use Tailscale MagicDNS for service discovery

---

## Pre-Deployment Checklist

### Hardware Verification
- [ ] VM allocated with 4+ vCPUs
- [ ] VM allocated with 8GB+ RAM
- [ ] VM allocated with 50GB+ storage
- [ ] VM network connectivity verified
- [ ] VMware snapshot created (for rollback)

### Software Preparation
- [ ] OS installation media/image available
- [ ] Download OpenClaw scripts to deployment machine
- [ ] Tailscale account created and verified
- [ ] SSH key pair generated for access

### Documentation Preparation
- [ ] README.md reviewed
- [ ] CONFIGURATION-REFERENCE.md reviewed
- [ ] Network diagram documented
- [ ] Backup location identified
- [ ] Contact information documented

### Access Preparation
- [ ] Tailscale admin credentials available
- [ ] SSH key pair created
- [ ] Password manager updated with credentials
- [ ] Emergency contact list prepared
- [ ] Change log initialized

---

## Network Architecture

### Network Zones

#### Zone 1: External Internet
- Tailscale relay servers
- Package repositories
- NTP time servers

#### Zone 2: Tailscale Mesh Network
- Encrypted tunnel between all authenticated devices
- Automatic NAT traversal
- End-to-end encryption (WireGuard)

#### Zone 3: VM Host Network
- Physical network adapter
- Optional: VLAN for additional isolation
- Firewall rules restrict traffic

#### Zone 4: Container Network
- Docker bridge network (172.28.0.0/16)
- Isolated from host network
- Containers communicate via service names

### Firewall Strategy

```
External Traffic (Internet)
          ↓
    Firewall: DROP
          ↓
Tailscale VPN Traffic (41641/udp)
          ↓
    Firewall: ACCEPT
          ↓
    Tailscale Interface (100.x.x.x)
          ↓
    Application (8080, 443, 22)
          ↓
    Docker Containers
```

### DNS Resolution

```
Client connects to:
  openclawhost.tailnet#​
           ↓
   Tailscale MagicDNS
           ↓
   100.x.x.x (VM Tailscale IP)
           ↓
   OpenClaw Application
```

---

## Step-by-Step Deployment

### Phase 1: Infrastructure Preparation (5-10 minutes)

#### Step 1.1: Create VM from Template/ISO
```bash
# In VMware vSphere/ESXi
# 1. Deploy new VM from template or OS ISO
# 2. Configure:
#    - 4 vCPUs (8+ for production)
#    - 8GB RAM (16GB+ for production)
#    - 50GB storage (100GB+ for production)
#    - Connected to production network
# 3. Boot VM and complete OS installation
# 4. Configure static IP or DHCP
# 5. Verify internet connectivity
```

#### Step 1.2: Prepare VM Access
```bash
# On deployment machine
ssh-keygen -t ed25519 -f ~/.ssh/openclaw_vm -C "openclaw-deployment"

# SSH to VM (initially via password)
ssh root@<vm-ip>

# On VM, install SSH key
mkdir -p ~/.ssh
echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

#### Step 1.3: Create VM Snapshot
```bash
# In VMware before running installation scripts
# Right-click VM → Snapshots → Take Snapshot
# Name: "Pre-OpenClaw Installation"
```

### Phase 2: Script Preparation (2-3 minutes)

#### Step 2.1: Download Installation Scripts
```bash
# On deployment machine
cd ~/deployment
git clone <scripts-repo> openclaw-deployment
cd openclaw-deployment/scripts

# Or manually copy files
scp -i ~/.ssh/openclaw_vm *.sh root@<vm-ip>:/tmp/
scp -i ~/.ssh/openclaw_vm README.md root@<vm-ip>:/tmp/
```

#### Step 2.2: Verify Script Integrity
```bash
# On VM
sha256sum *.sh
# Compare with official checksums

# Make executable (done automatically by scripts)
chmod +x *.sh
```

### Phase 3: Initial Hardening (2-3 minutes)

#### Step 3.1: Run Stage 1 Script
```bash
# SSH to VM
ssh -i ~/.ssh/openclaw_vm root@<vm-ip>

# Run script
cd /tmp
sudo ./01-initial-setup.sh

# This will:
# ✓ Update system packages
# ✓ Harden SSH (disable passwords)
# ✓ Configure firewall
# ✓ Setup Fail2Ban
# ✓ Enable auto-updates
# ✓ Apply kernel hardening
# ✓ Configure audit logging

# ⚠️ After this, password auth is DISABLED
# Only SSH keys will work
```

#### Step 3.2: Verify SSH Hardening
```bash
# SSH should still work with key
ssh -i ~/.ssh/openclaw_vm root@<vm-ip>

# Password login should FAIL
ssh root@<vm-ip>  # Should not work

# Test firewall
sudo ufw status
sudo netstat -tlnp
```

### Phase 4: Application Installation (5-10 minutes)

#### Step 4.1: Run Stage 2 Script
```bash
# SSH with key
ssh -i ~/.ssh/openclaw_vm root@<vm-ip>

# Run OpenClaw installation
sudo ./02-install-openclaw.sh

# This will:
# ✓ Install Docker & Docker Compose
# ✓ Create OpenClaw user
# ✓ Setup systemd service
# ✓ Generate SSL certificates
# ✓ Configure backups
# ✓ Start OpenClaw service
```

#### Step 4.2: Verify OpenClaw Service
```bash
# Check service status
sudo systemctl status openclaw

# Check logs
sudo journalctl -u openclaw -n 20

# Check containers
docker ps --filter "label=openclaw=true"
```

### Phase 5: Tailscale VPN Setup (3-5 minutes)

#### Step 5.1: Run Stage 3 Script
```bash
# SSH with key
ssh -i ~/.ssh/openclaw_vm root@<vm-ip>

# Run Tailscale setup
sudo ./03-setup-tailscale.sh

# During this script:
# 1. Tailscale will provide authentication URL
# 2. Visit the URL in your browser
# 3. Authenticate with your Tailscale account
# 4. The script will complete the configuration
```

#### Step 5.2: Verify Tailscale Connection
```bash
# Check Tailscale status
sudo tailscale status

# Your entry should show:
# <hostname>                           <tailscale-ip>
# ...

# Test connectivity from another device on tailnet
# (if you have another device)
ping <tailscale-ip>
ssh -i ~/.ssh/openclaw_vm root@<tailscale-ip>
```

### Phase 6: Security Hardening (2-3 minutes)

#### Step 6.1: Run Stage 4 Script
```bash
# SSH with key (can now use Tailscale IP)
ssh -i ~/.ssh/openclaw_vm root@<tailscale-ip>

# Run post-installation security
sudo ./04-post-install-security.sh

# This will:
# ✓ Configure AppArmor/SELinux
# ✓ Harden SSL/TLS
# ✓ Setup AIDE intrusion detection
# ✓ Configure security monitoring
# ✓ Setup container security
# ✓ Configure centralized logging
```

#### Step 6.2: Verify Security Tools
```bash
# Check AppArmor status
sudo aa-status | head

# Check AIDE database
ls -la /var/lib/aide/

# Check audit logs
sudo auditctl -l | head
```

---

## Post-Deployment Verification

### Verification Checklist

```bash
#!/bin/bash
# Run these commands to verify deployment

echo "=== System Status ==="
sudo systemctl status openclaw tailscaled

echo ""
echo "=== Service Connectivity ==="
sudo tailscale status

echo ""
echo "=== Network Interfaces ==="
ip addr show | grep -E "inet|tailscale"

echo ""
echo "=== Firewall Rules ==="
sudo ufw status | head -10

echo ""
echo "=== Docker Containers ==="
docker ps --filter "label=openclaw=true"

echo ""
echo "=== SSL Certificate ==="
openssl x509 -in /opt/openclaw/config/certs/openclaw.crt -noout -dates

echo ""
echo "=== Recent Logs ==="
sudo journalctl -u openclaw -n 10

echo ""
echo "=== Backup Status ==="
ls -lh /var/backups/openclaw/ | tail -5
```

### Initial Configuration Steps

#### Step 1: Configure OpenClaw Admin
```bash
# Access OpenClaw (via Tailscale VPN)
# From another device on tailnet:
curl https://<tailscale-ip>:8080/admin

# Or use SSH tunnel:
ssh -i ~/.ssh/openclaw_vm -L 8080:localhost:8080 root@<tailscale-ip>
# Then visit: https://localhost:8080
```

#### Step 2: Update Tailscale ACLs
1. Visit: https://login.tailscale.com/admin/acls
2. Configure access rules for your users
3. Add appropriate tags (e.g., tag:openclaw)
4. Save and deploy

#### Step 3: Setup Monitoring
```bash
# Run health check
sudo ./05-maintenance.sh
# Select option 1: Health Check

# Or manually:
sudo openclaw-security-audit.sh
```

#### Step 4: Configure Backups
```bash
# Verify backup script
ls -la /usr/local/bin/openclaw-backup.sh

# Test backup creation
sudo openclaw-backup.sh

# Verify backup
ls -lh /var/backups/openclaw/
```

---

## Production Considerations

### SSL/TLS Certificates

#### Replace Self-Signed Certificates
```bash
# 1. Generate CSR or use Let's Encrypt
sudo certbot certonly --standalone -d openclaw.example.com

# 2. Copy certificates
sudo cp /etc/letsencrypt/live/openclaw.example.com/fullchain.pem \
  /opt/openclaw/config/certs/openclaw.crt
sudo cp /etc/letsencrypt/live/openclaw.example.com/privkey.pem \
  /opt/openclaw/config/certs/openclaw.key

# 3. Restart service
sudo systemctl restart openclaw

# 4. Verify
openssl x509 -in /opt/openclaw/config/certs/openclaw.crt -text -noout
```

### Database Configuration

For production, configure external database:
```conf
# /opt/openclaw/config/openclaw.conf
db.type=postgresql
db.host=db-server.internal
db.port=5432
db.name=openclaw
db.user=openclaw_user
db.password_file=/opt/openclaw/config/db.pass
db.ssl=true
```

### Logging and Monitoring

#### Configure Prometheus
```yaml
# /opt/openclaw/config/prometheus.yml
scrape_configs:
  - job_name: 'openclaw'
    static_configs:
      - targets: ['localhost:9090']
```

#### Configure Grafana
```bash
# Add Prometheus data source
# https://<tailscale-ip>:3000
# Data Source URL: http://localhost:9090
```

#### Setup Alerting
```yaml
# /opt/openclaw/config/alerting.yml
groups:
  - name: openclaw
    rules:
      - alert: OpenClawServiceDown
        expr: up{job="openclaw"} == 0
        for: 5m
        annotations:
          summary: "OpenClaw service is down"
```

### High Availability Setup

#### Multiple VMs
1. Deploy 2+ VMs using same scripts
2. Configure load balancer (HAProxy, nginx)
3. Use centralized database
4. Replicate logs/backups

#### Database Replication
```sql
-- Primary VM
GRANT REPLICATION ON *.* TO 'replication'@'<secondary-ip>';

-- Secondary VM
CHANGE MASTER TO
  MASTER_HOST='<primary-ip>',
  MASTER_USER='replication',
  MASTER_PASSWORD='<password>';
START SLAVE;
```

### Disaster Recovery

#### Automated Backups
```bash
# Verified each backup
tar -tzf /var/backups/openclaw/backup-*.tar.gz > /dev/null

# Test restoration
tar -tzf /var/backups/openclaw/backup-latest.tar.gz | head
```

#### Off-site Backups
```bash
# Sync to remote server
rsync -avz --delete \
  -e "ssh -i /root/.ssh/backup-key" \
  /var/backups/openclaw/ \
  backup@offsite-server:/backups/
```

---

## Troubleshooting & Support

### Common Issues & Solutions

#### Issue: OpenClaw Service Won't Start
```bash
# Diagnosis
sudo systemctl status openclaw
sudo journalctl -u openclaw -n 50

# Solution
sudo systemctl restart openclaw
# Check for port conflicts
sudo lsof -i :8080
# Check logs for specific errors
```

#### Issue: No Internet Connectivity
```bash
# Check network
ping 8.8.8.8
ip route show
cat /etc/resolv.conf

# Reset networking
sudo systemctl restart networking
# Or
sudo systemctl restart systemd-networkd
```

#### Issue: SSH Access Denied
```bash
# Check SSH config
sudo sshd -t

# Check firewall
sudo ufw status
sudo firewall-cmd --list-all

# Check Tailscale
sudo tailscale status

# Verify key permissions
ls -la ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

#### Issue: Tailscale Not Connecting
```bash
# Check service
sudo systemctl status tailscaled

# Check logs
sudo journalctl -u tailscaled -n 50

# Restart
sudo systemctl restart tailscaled

# Manual authentication
sudo tailscale up
```

### Emergency Recovery

#### Service Down - Restore from Backup
```bash
# Stop service
sudo systemctl stop openclaw

# Extract backup
cd /opt/openclaw
tar -xzf /var/backups/openclaw/backup-latest.tar.gz

# Start service
sudo systemctl start openclaw

# Verify
sudo systemctl status openclaw
```

#### Disk Full
```bash
# Check usage
df -h
du -sh /var/log/openclaw/*

# Cleanup old logs
find /var/log/openclaw -name "*.log" -mtime +30 -delete

# Cleanup old backups
find /var/backups/openclaw -name "*.tar.gz" -mtime +30 -delete
```

### Getting Help

#### Emergency Support Contacts
- **Tailscale Support:** support@tailscale.com
- **OpenClaw Team:** [contact info]
- **VMware Support:** [contact info]

#### Information to Gather
When contacting support, provide:
- System logs: `journalctl -u openclaw -n 100 > logs.txt`
- Configuration (sanitized): `/opt/openclaw/config/`
- Network info: `ip addr`, `ip route`
- Firewall rules: `ufw status`, `firewall-cmd --list-all`

---

## Operational Runbooks

### Daily Operations

```bash
#!/bin/bash
# Daily health check and status report

echo "Daily OpenClaw Status Report - $(date)"
echo ""

echo "1. Service Status:"
sudo systemctl status openclaw --no-pager | head -5

echo ""
echo "2. Resource Usage:"
free -h | head -2

echo ""
echo "3. Recent Errors:"
sudo journalctl -u openclaw -p err -n 3

echo ""
echo "4. Tailscale Status:"
sudo tailscale status | head -3
```

### Weekly Maintenance

```bash
#!/bin/bash
# Weekly maintenance tasks

echo "Weekly Maintenance - $(date)"

# Update packages
echo "Updating packages..."
sudo apt upgrade -y

# Run security audit
echo "Running security audit..."
sudo openclaw-security-audit.sh

# Verify backups
echo "Verifying backups..."
for backup in /var/backups/openclaw/*.tar.gz; do
  tar -tzf "$backup" > /dev/null && echo "✓ $backup" || echo "✗ $backup"
done

# Check certificate expiry
echo "Certificate expiry:"
sudo openssl x509 -in /opt/openclaw/config/certs/openclaw.crt -noout -dates
```

### Monthly Review

```bash
#!/bin/bash
# Monthly security and performance review

echo "Monthly Review Report - $(date)"

# Audit logs
echo "Access logs analysis..."
grep -c "Failed password" /var/log/auth.log

echo ""
echo "Failed login attempts..."
grep "Failed password" /var/log/auth.log | tail -5

echo ""
echo "Disk usage trend..."
du -sh /var/backups/openclaw/

echo ""
echo "Package updates available..."
apt list --upgradable
```

---

## Conclusion

This comprehensive deployment guide provides all necessary information to securely deploy OpenClaw on VMware with Tailscale VPN integration. For additional information, refer to:

- [README.md](README.md) - General overview and quick start
- [CONFIGURATION-REFERENCE.md](CONFIGURATION-REFERENCE.md) - Detailed configuration options
- [Official OpenClaw Documentation](https://openclaw.org)
- [Tailscale Documentation](https://tailscale.com/kb/)

**Questions or Issues?** Contact your system administrator or support team.

---

**Document Version:** 1.0
**Last Updated:** February 12, 2026
**Maintained By:** OpenClaw Security Team

# Project Structure and File Guide

## Overview

This directory contains complete shell scripts and documentation for securely deploying OpenClaw on VMware virtual machines with Tailscale VPN integration.

## File Structure

```
scripts/
├── README.md                           # Main installation guide and overview
├── DEPLOYMENT-GUIDE.md                 # Comprehensive step-by-step deployment
├── CONFIGURATION-REFERENCE.md          # Configuration templates and examples
├── PROJECT-STRUCTURE.md                # This file
│
├── Installation Scripts:
│   ├── quick-start.sh                  # Automated installation wizard
│   ├── 01-initial-setup.sh              # System hardening and security base
│   ├── 02-install-openclaw.sh           # OpenClaw application installation
│   ├── 03-setup-tailscale.sh            # Tailscale VPN configuration
│   ├── 04-post-install-security.sh      # Additional security hardening
│   └── 05-maintenance.sh                # Maintenance and diagnostic tools
│
└── logs/                               # Created during installation
    └── [installation logs go here]
```

## Quick Reference

### Installation Methods

#### Method 1: Automated (Recommended)
```bash
sudo chmod +x quick-start.sh
sudo ./quick-start.sh
```
This guides you through all stages with user prompts and confirmations.

#### Method 2: Manual Stage-by-Stage
```bash
sudo chmod +x *.sh
sudo ./01-initial-setup.sh
sudo ./02-install-openclaw.sh
sudo ./03-setup-tailscale.sh
sudo ./04-post-install-security.sh
```

#### Method 3: Individual Script Execution
Each script can be run independently if needed:
```bash
sudo ./[script-name].sh
```

## File Descriptions

### Documentation Files

#### README.md
- **Purpose:** Main installation guide
- **Contents:**
  - Security best practices overview
  - Prerequisites
  - 5-step installation process
  - Post-installation checklist
  - Troubleshooting guide
  - Quick start summary

#### DEPLOYMENT-GUIDE.md
- **Purpose:** Comprehensive production deployment guide
- **Contents:**
  - Executive summary
  - Prerequisites and planning
  - Pre-deployment checklist
  - Network architecture
  - Detailed step-by-step deployment phases
  - Production considerations
  - HA/DR setup
  - Operational runbooks
  - Troubleshooting procedures

#### CONFIGURATION-REFERENCE.md
- **Purpose:** Configuration templates and examples
- **Contents:**
  - SSH configuration templates
  - Firewall rule examples
  - Tailscale ACL templates
  - OpenClaw configuration options
  - Docker configuration
  - Monitoring and logging setup
  - Backup strategies
  - SSL/TLS configuration
  - Performance tuning parameters

### Installation Scripts

#### quick-start.sh
- **Purpose:** Interactive installation wizard
- **Type:** Automated
- **Execution:** `sudo ./quick-start.sh`
- **Features:**
  - System requirements verification
  - User confirmations before each stage
  - Runs all 4 main installation scripts
  - Summary and verification
  - Estimated time: 15-25 minutes

#### 01-initial-setup.sh
- **Purpose:** Initial system hardening
- **Type:** Automatic
- **Execution:** `sudo ./01-initial-setup.sh`
- **Performs:**
  - System package updates
  - SSH key-based authentication setup
  - Firewall configuration (UFW/FirewallD)
  - Fail2Ban brute-force protection
  - Automatic security updates
  - Kernel hardening
  - Audit logging
  - System monitoring
- **Estimated time:** 2-3 minutes
- **Logs:** `/var/log/openclaw-setup/initial-setup-*.log`

#### 02-install-openclaw.sh
- **Purpose:** OpenClaw application installation
- **Type:** Automatic
- **Execution:** `sudo ./02-install-openclaw.sh`
- **Performs:**
  - Docker and Docker Compose installation
  - OpenClaw user account creation
  - Directory structure setup
  - Docker Compose configuration
  - Systemd service creation
  - SSL certificate generation
  - Backup script setup
  - Service startup and verification
- **Estimated time:** 5-10 minutes
- **Logs:** `/var/log/openclaw-setup/openclaw-install-*.log`

#### 03-setup-tailscale.sh
- **Purpose:** Tailscale VPN configuration
- **Type:** Interactive
- **Execution:** `sudo ./03-setup-tailscale.sh`
- **Performs:**
  - Tailscale installation
  - Interactive authentication
  - Firewall rule configuration
  - Optional exit node setup
  - Monitoring script creation
  - Admin utility setup
  - Documentation generation
  - ACL template creation
- **Estimated time:** 3-5 minutes
- **Notes:** Requires Tailscale account and browser for authentication
- **Logs:** `/var/log/openclaw-setup/tailscale-setup-*.log`

#### 04-post-install-security.sh
- **Purpose:** Additional security hardening
- **Type:** Automatic
- **Execution:** `sudo ./04-post-install-security.sh`
- **Performs:**
  - AppArmor/SELinux policy configuration
  - SSL/TLS hardening
  - AIDE intrusion detection setup
  - Application security monitoring
  - Container security profiles
  - Centralized logging configuration
  - Security checklist generation
- **Estimated time:** 2-3 minutes
- **Logs:** `/var/log/openclaw-setup/post-security-*.log`

#### 05-maintenance.sh
- **Purpose:** Operational maintenance and diagnostics
- **Type:** Interactive menu-based
- **Execution:** `sudo ./05-maintenance.sh`
- **Options:**
  1. Health Check - System resource and service status
  2. Status Check - Quick service verification
  3. Security Audit - Run security audit
  4. System Update - Update all packages
  5. Create Backup - Manual backup creation
  6. Restore Backup - Restore from backup
  7. View Logs - Browse system logs
  8. Restart Services - Restart all services
  9. Fix Permissions - Correct file permissions
  10. Cleanup Old Files - Remove old logs/backups
  11. Network Diagnostics - Network troubleshooting
  12. Generate System Report - Full diagnostic report
  13. Help/Documentation - View help

### Log Directories

#### Installation Logs
- **Location:** `/var/log/openclaw-setup/`
- **Contents:**
  - `initial-setup-YYYYMMDD-HHMMSS.log`
  - `openclaw-install-YYYYMMDD-HHMMSS.log`
  - `tailscale-setup-YYYYMMDD-HHMMSS.log`
  - `post-security-YYYYMMDD-HHMMSS.log`

#### Application Logs
- **Location:** `/var/log/openclaw/`
- **Contents:**
  - OpenClaw application logs
  - Docker container logs
  - Security audit logs

#### Backup Location
- **Location:** `/var/backups/openclaw/`
- **Contents:**
  - Daily backups (`.tar.gz` format)
  - Retention: 30 days (auto-cleanup)

## Key Installation Paths

### User & Group
- **OpenClaw User:** `openclaw`
- **OpenClaw Group:** `openclaw`

### Installation Directories
- **Application:** `/opt/openclaw/`
- **Configuration:** `/opt/openclaw/config/`
- **Data:** `/opt/openclaw/data/`
- **Logs:** `/var/log/openclaw/`
- **Backups:** `/var/backups/openclaw/`

### Utility Scripts
- **Backup:** `/usr/local/bin/openclaw-backup.sh`
- **Security Audit:** `/usr/local/bin/openclaw-security-audit.sh`
- **Health Check:** `/usr/local/bin/check-system-health.sh`
- **Tailscale Admin:** `/usr/local/bin/tailscale-admin.sh`

### Configuration Files
- **OpenClaw Config:** `/opt/openclaw/config/openclaw.conf`
- **SSH Config:** `/etc/ssh/sshd_config.d/99-hardened.conf`
- **Fail2Ban:** `/etc/fail2ban/jail.local`
- **AppArmor:** `/etc/apparmor.d/usr.bin.openclaw`
- **Firewall (UFW):** `/etc/ufw/rules.v4`
- **Firewall (FirewallD):** `/etc/firewalld/zones/public.xml`

## Security Features Implemented

### System Hardening (Stage 1)
✓ SSH key-based authentication (passwords disabled)
✓ Firewall configuration (UFW/FirewallD)
✓ Fail2Ban brute-force protection
✓ Automatic security updates
✓ Kernel hardening parameters
✓ Audit logging
✓ System monitoring

### Application Hardening (Stage 2)
✓ Docker containerization
✓ Least privilege user account
✓ SSL/TLS encryption
✓ Automated backups
✓ systemd service hardening
✓ Health checks

### VPN Security (Stage 3)
✓ Tailscale VPN encryption
✓ WireGuard protocol
✓ Automatic NAT traversal
✓ Network segmentation
✓ ACL-based access control

### Additional Hardening (Stage 4)
✓ AppArmor/SELinux policies
✓ AIDE intrusion detection
✓ Container security profiles
✓ Centralized logging
✓ Security monitoring
✓ System audit rules

## Maintenance Activities

### Daily
- Monitor OpenClaw service status
- Check Tailscale connection
- Review error logs

### Weekly
- Run security audit
- Review system logs
- Run backups (automated)

### Monthly
- Full security assessment
- Test backup restoration
- Update packages
- Review access logs

### Quarterly
- Penetration testing
- SSL certificate validation
- ACL review
- Disaster recovery drill

## Troubleshooting Quick Links

1. **Service Issues** → See README.md "Troubleshooting"
2. **Configuration** → See CONFIGURATION-REFERENCE.md
3. **Deployment Problems** → See DEPLOYMENT-GUIDE.md
4. **Maintenance** → Run `sudo ./05-maintenance.sh`

## Support Resources

- **Documentation:** README.md, DEPLOYMENT-GUIDE.md, CONFIGURATION-REFERENCE.md
- **Logs:** `/var/log/openclaw-setup/`
- **Maintenance Tool:** `sudo ./05-maintenance.sh`
- **System Journal:** `sudo journalctl -u openclaw`

## Version Information

- **Scripts Version:** 1.0
- **Created:** February 12, 2026
- **Last Updated:** February 12, 2026
- **Tested On:** Ubuntu 22.04 LTS, CentOS Stream 9

## License

These scripts and documentation are provided as-is for secure deployment
of OpenClaw on VMware virtual machines. Ensure proper authorization
before use in production environments.

## Getting Help

1. **Check Documentation:** Start with README.md
2. **Review Logs:** `/var/log/openclaw-setup/`
3. **Run Diagnostics:** `sudo ./05-maintenance.sh`
4. **Contact Support:** [Your support contact]

---

**Quick Start:**
```bash
# Download scripts to /tmp
cd /tmp

# Make executable
chmod +x *.sh

# Run automated installation
sudo ./quick-start.sh
```

**Estimated Total Time:** 15-25 minutes for complete installation

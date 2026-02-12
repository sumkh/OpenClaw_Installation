# OpenClaw Secure Installation - Configuration Reference

This document provides configuration templates and best practices for the OpenClaw secure installation on VMware.

## Table of Contents
1. [SSH Configuration](#ssh-configuration)
2. [Firewall Rules](#firewall-rules)
3. [Tailscale Configuration](#tailscale-configuration)
4. [OpenClaw Configuration](#openclaw-configuration)
5. [Docker Configuration](#docker-configuration)
6. [Monitoring & Logging](#monitoring--logging)
7. [Backup Configuration](#backup-configuration)
8. [SSL/TLS Configuration](#ssltls-configuration)

---

## SSH Configuration

### Location
`/etc/ssh/sshd_config.d/99-hardened.conf`

### Key Settings
- **Port 22** - Standard SSH port
- **PubkeyAuthentication yes** - Enable SSH keys
- **PasswordAuthentication no** - Disable passwords
- **PermitRootLogin no** - Prevent root SSH access
- **AllowUsers openclaw** - Restrict SSH users

### Generate SSH Key Pair (on client)
```bash
ssh-keygen -t ed25519 -f ~/.ssh/openclaw -C "openclaw@$(hostname)"
chmod 600 ~/.ssh/openclaw
chmod 644 ~/.ssh/openclaw.pub
```

### Add Public Key to Server
```bash
# As root on server
mkdir -p /root/.ssh
cat >> /root/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbcdefg... openclaw@myhost
EOF
chmod 600 /root/.ssh/authorized_keys
```

### SSH Config for Client
```bash
# File: ~/.ssh/config
Host openclaw-vm
    HostName <tailscale-ip>
    User root
    IdentityFile ~/.ssh/openclaw
    IdentitiesOnly yes
    PubkeyAuthentication yes
    ForwardAgent no
    ServerAliveInterval 300
    ServerAliveCountMax 2
```

---

## Firewall Rules

### UFW (Ubuntu) Rules
```bash
# View rules
sudo ufw status numbered

# Important default rules
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Essential ports
sudo ufw allow 22/tcp              # SSH
sudo ufw allow 41641/udp           # Tailscale
sudo ufw allow 8080/tcp            # OpenClaw HTTP (adjust as needed)
sudo ufw allow 443/tcp             # HTTPS (adjust as needed)

# Source-based rules (via Tailscale)
sudo ufw allow from 100.0.0.0/8 to any port 22
sudo ufw allow from 100.0.0.0/8 to any port 8080

# Deny specific
sudo ufw deny from 10.0.0.5
```

### FirewallD (CentOS/RHEL) Rules
```bash
# View rules
sudo firewall-cmd --list-all

# Add rules permanently
sudo firewall-cmd --permanent --set-default-zone=public
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --permanent --add-port=41641/udp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## Tailscale Configuration

### Authentication

Edit Tailscale ACLs at: `https://login.tailscale.com/admin/acls`

#### Example ACL Configuration
```hujson
{
  "version": 1,
  "acls": [
    // Allow SSH from admin group
    {
      "action": "accept",
      "src": ["group:admin"],
      "dst": ["tag:openclaw:22"],
      "priority": "high"
    },
    
    // Allow OpenClaw web access
    {
      "action": "accept",
      "src": ["group:users"],
      "dst": ["tag:openclaw:8080,443"],
    },
    
    // Default: allow everything in tailnet
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*"]
    }
  ],
  
  "groups": {
    "group:admin": ["admin@example.com", "ops@example.com"],
    "group:users": ["user1@example.com", "user2@example.com"]
  },
  
  "tagOwners": {
    "tag:openclaw": ["group:admin"]
  }
}
```

### Exit Node Configuration

Enable this VM as an exit node:
```bash
# On VM
sudo tailscale up --advertise-exit-node

# On client (for all traffic through this VM)
sudo tailscale set --exit-node=<vm-tailscale-ip>
sudo tailscale set --exit-node-allow-lan-access=true
```

### Device Tags
```bash
# Tag the device during setup
sudo tailscale up --hostname=openclaw-prod

# Or tag later at dashboard
https://login.tailscale.com/admin/machines
```

---

## OpenClaw Configuration

### Default Configuration File
Location: `/opt/openclaw/config/openclaw.conf`

#### Server Settings
```conf
# Port and binding
server.port=8080
server.bind=127.0.0.1
server.interface=tailscale0

# SSL/TLS
server.ssl.enabled=true
server.ssl.certificate=/opt/openclaw/config/certs/openclaw.crt
server.ssl.key=/opt/openclaw/config/certs/openclaw.key
server.ssl.protocols=TLSv1.2,TLSv1.3
```

#### Security Settings
```conf
# Security mode
security.mode=production
security.strict_mode=true
security.cors.enabled=false
security.cors.allowed_origins=https://example.com

# Authentication
security.auth.type=token
security.auth.token_expiry=3600
security.password_policy.min_length=16
security.password_policy.require_special=true
```

#### Logging Configuration
```conf
# Logging
logging.level=INFO
logging.format=json
logging.file=/var/log/openclaw/openclaw.log
logging.rotation.size=100M
logging.retention.days=30
logging.syslog.enabled=true

# Audit logging
audit.enabled=true
audit.log_file=/var/log/openclaw/audit.log
audit.log_level=INFO
```

#### Performance Tuning
```conf
# Connection settings
server.connection_timeout=30s
server.read_timeout=30s
server.write_timeout=30s
server.request_timeout=60s

# Resource limits
resources.max_concurrent_requests=1000
resources.max_body_size=10M
resources.connection_pool_size=50
```

---

## Docker Configuration

### Docker Security Daemon Config
Location: `/etc/docker/daemon.json`

```json
{
  "debug": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "labels": "openclaw=true"
  },
  "icc": false,
  "ip-forward": true,
  "userland-proxy": true,
  "seccomp-profile": "/etc/docker/seccomp/openclaw-seccomp.json",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
```

### Docker Network Bridge
```bash
# Create custom bridge
docker network create \
  --driver bridge \
  --subnet=172.28.0.0/16 \
  --ip-range=172.28.5.0/24 \
  openclaw-net

# Use in compose file
networks:
  openclaw-net:
    external: true
```

### Image Security Scanning
```bash
# Scan for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image openclasw/openclaw:latest

# Check signed images
docker trust inspect openclaw/openclaw:latest
```

---

## Monitoring & Logging

### Systemd Logging
```bash
# View all logs
sudo journalctl -u openclaw

# Follow logs in real-time
sudo journalctl -u openclaw -f

# Filter by priority
sudo journalctl -u openclaw -p err,crit

# Time range
sudo journalctl -u openclaw --since "2024-02-01" --until "2024-02-12"

# Output format
sudo journalctl -u openclaw -o json-pretty
```

### Central Log Aggregation (Syslog)

Configure Rsyslog:
```bash
# /etc/rsyslog.d/50-openclaw-forward.conf
$ModLoad imuxsock
$ModLoad imudp

$UDPServerRun 514

# Forward all openclaw logs
:programname, isequal, "openclaw" @syslog.example.com:514

# Stop processing after forward
& stop
```

### Prometheus Metrics Export
```yaml
# /opt/openclaw/config/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'openclaw'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'openclaw-prod'
```

---

## Backup Configuration

### Automated Backup Script
```bash
# Schedule: Daily at 3 AM
0 3 * * * /usr/local/bin/openclaw-backup.sh
```

### Backup Retention Policy
```bash
# Keep 30-day rolling backups
find /var/backups/openclaw -name "*.tar.gz" -mtime +30 -delete

# Keep weekly copies for 3 months
for i in {1..12}; do
  BACKUP="/var/backups/openclaw/backup-week-$i.tar.gz"
  if [[ ! -f $BACKUP ]]; then
    cp /var/backups/openclaw/openclaw-backup-*.tar.gz "$BACKUP"
    break
  fi
done
```

### Remote Backup
```bash
# Rsync to remote server
rsync -avz --delete \
  /var/backups/openclaw/ \
  user@backup-server:/backups/openclaw-prod/

# SSH key authentication
rsync -av \
  -e "ssh -i /root/.ssh/backup-key" \
  /var/backups/openclaw/ \
  backup@backup-server:/backups/
```

### Backup Verification
```bash
# Compare sizes
du -sh /var/backups/openclaw/openclaw-backup-*.tar.gz

# Test extraction
tar -tzf /var/backups/openclaw/openclaw-backup-latest.tar.gz | head

# Checksum verification
sha256sum /var/backups/openclaw/*.tar.gz > backup-checksums.txt
sha256sum -c backup-checksums.txt
```

---

## SSL/TLS Configuration

### Generate Self-Signed Certificate (Development)
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/openclaw/config/certs/openclaw.key \
  -out /opt/openclaw/config/certs/openclaw.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

### Generate Certificate Signing Request (CSR)
```bash
openssl req -new -newkey rsa:2048 \
  -keyout /opt/openclaw/config/certs/openclaw.key \
  -out /opt/openclaw/config/certs/openclaw.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=openclaw.example.com"
```

### Install CA-Signed Certificate
```bash
# After receiving signed cert from CA
cp /path/to/signed/openclaw.crt /opt/openclaw/config/certs/
cp /path/to/ca-bundle.crt /opt/openclaw/config/certs/ca-bundle.crt

# Verify certificate chain
openssl verify -CAfile /opt/openclaw/config/certs/ca-bundle.crt \
  /opt/openclaw/config/certs/openclaw.crt
```

### Certificate Renewal (Let's Encrypt)
```bash
# Install Certbot
sudo apt-get install certbot python3-certbot-nginx

# Generate certificate
sudo certbot certonly --standalone \
  -d openclaw.example.com \
  --email admin@example.com

# Copy to OpenClaw
sudo cp /etc/letsencrypt/live/openclaw.example.com/fullchain.pem \
  /opt/openclaw/config/certs/openclaw.crt
sudo cp /etc/letsencrypt/live/openclaw.example.com/privkey.pem \
  /opt/openclaw/config/certs/openclaw.key

# Restart service
sudo systemctl restart openclaw
```

### Certificate Monitoring
```bash
# Check expiry
openssl x509 -in /opt/openclaw/config/certs/openclaw.crt -noout -dates

# Add to monitoring
echo "0 9 * * * openssl x509 -in /opt/openclaw/config/certs/openclaw.crt -noout -dates | mail -s 'Certificate Status' admin@example.com" | crontab -
```

---

## WhatsApp & Google API Credentials (Storage & Usage)

Store provider credentials on the VM in `/opt/openclaw/secrets` and mount them read-only into the container. Keep secrets out of Git and use `.env.example` and templates in the repo.

Recommended file names and env vars:

- `/opt/openclaw/secrets/google-sa.json`
  - Env: `GOOGLE_APPLICATION_CREDENTIALS=/opt/openclaw/secrets/google-sa.json`
  - Usage: Google client libraries will read `GOOGLE_APPLICATION_CREDENTIALS` automatically.

- `/opt/openclaw/secrets/whatsapp.conf` (or `whatsapp.json`)
  - Example contents (ENV-style):
    ```
    WHATSAPP_API_TOKEN=abcd1234
    WHATSAPP_PHONE_ID=1234567890
    WEBHOOK_SECRET=xxxxxxxx
    ```
  - Env: `WHATSAPP_CRED_FILE=/opt/openclaw/secrets/whatsapp.conf`

Access pattern inside container (example in shell):

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/opt/openclaw/secrets/google-sa.json
source /opt/openclaw/secrets/whatsapp.conf
# start OpenClaw process which reads these env vars
```

Permissions and ownership (on VM):

```bash
sudo chown openclaw:openclaw /opt/openclaw/secrets/*
sudo chmod 600 /opt/openclaw/secrets/*
sudo chmod 700 /opt/openclaw/secrets
```

If you later migrate to cloud, replace host-mounted secrets with a secret manager (AWS Secrets Manager, GCP Secret Manager, or Vault) and inject secrets securely at runtime.


## Performance Tuning

### Docker Memory Limits
```yaml
# docker-compose.yml
services:
  openclaw:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

### Kernel Parameters
```bash
# /etc/sysctl.conf
# TCP optimization
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=10000 65000

# Connection tracking
net.netfilter.nf_conntrack_max=2000000
net.netfilter.nf_conntrack_tcp_timeout_established=600
```

### File Descriptor Limits
```bash
# /etc/security/limits.conf
openclaw soft nofile 65536
openclaw hard nofile 65536
openclaw soft nproc 32768
openclaw hard nproc 32768
```

---

## Environment Variables

### Application Environment
```bash
# /opt/openclaw/config/.env
OPENCLAW_MODE=production
OPENCLAW_LOG_LEVEL=INFO
OPENCLAW_SECURE_MODE=true
OPENCLAW_ADMIN_EMAIL=admin@example.com
OPENCLAW_DATABASE_URL=postgresql://user:pass@localhost/openclaw
OPENCLAW_REDIS_URL=redis://localhost:6379/0
TZ=UTC
```

---

## Troubleshooting Configuration

### Enable Debug Logging
```conf
# /opt/openclaw/config/openclaw.conf
logging.level=DEBUG
server.debug=true
```

### Network Diagnostics
```bash
# Test containers network
docker network inspect openclaw-net

# Test DNS resolution
docker run --rm --net openclaw-net busybox ping openclaw

# Test ports
netstat -tlnp | grep openclaw
docker port openclaw
```

### SSL Debugging
```bash
# Test SSL connection
openssl s_client -connect localhost:443 -showcerts

# Verify certificate
openssl verify -CAfile ca-bundle.crt openclaw.crt
```

---

## Security Hardening Checklist

- [ ] SSH keys configured (no password auth)
- [ ] Firewall rules applied
- [ ] Tailscale ACLs configured
- [ ] SSL/TLS certificates in place
- [ ] Automated backups scheduled
- [ ] Monitoring configured
- [ ] Audit logging enabled
- [ ] Container security policies applied
- [ ] Resource limits set
- [ ] File permissions verified
- [ ] Secrets stored securely
- [ ] Regular security updates scheduled

---

**Last Updated:** February 12, 2026
**Version:** 1.0

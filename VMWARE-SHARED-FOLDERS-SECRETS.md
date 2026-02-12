# VMware Shared Folders - Secrets & Credentials Storage

## Overview

This guide explains how to:
1. ✅ Share a folder from the VMware host to the OpenClaw VM
2. ✅ Configure it for secrets/credentials storage
3. ✅ Grant OpenClaw container access to shared folder
4. ✅ Keep credentials separate from Docker image

---

## Architecture

```
VMware Host
    ↓
    └─ Shared Folder (NFSv4 or VMFS)
         ├─ /var/shared/openclaw-secrets/
         │  ├─ .whatsapp-config.json
         │  ├─ .google-credentials.json
         │  ├─ .env.secrets
         │  └─ api-keys.yaml
         ↓
OpenClaw VM (Ubuntu 24.04)
    ↓
    └─ Mount Point: /mnt/vmshared/
         ├─ Read-only: /opt/openclaw/secrets (symlink)
         └─ Permissions: 600 (OpenClaw user only)
         ↓
Docker Container
         ├─ Volume: /mnt/vmshared:/opt/openclaw/secrets:ro
         └─ Access: Inside container at /opt/openclaw/secrets
```

---

## Part 1: Configure Shared Folder on VMware Host

### For VMware vSphere (ESXi)

#### 1.1 Create Shared Folder Directory
```bash
# On host machine or NAS
mkdir -p /var/shared/openclaw-secrets
chmod 755 /var/shared/openclaw-secrets
```

#### 1.2 Export via NFS (Recommended for Linux/UNIX)
```bash
# On VMware host or NAS
# Edit /etc/exports (or create if Linux NFS server):
echo "/var/shared/openclaw-secrets 192.168.1.0/24(rw,sync,no_subtree_check)" >> /etc/exports

# Reload NFS exports:
sudo exportfs -r

# Verify:
showmount -e
# Output should include: /var/shared/openclaw-secrets
```

#### 1.3 Configure Firewall (If Host Has Firewall)
```bash
# On VMware host:
sudo ufw allow from 192.168.1.0/24 to any port 111     # NFS portmapper
sudo ufw allow from 192.168.1.0/24 to any port 2049    # NFS server
sudo ufw allow from 192.168.1.0/24 to any port 20048   # NFS mountd
```

### For VMware Workstation/Player (Windows Host)

#### 1.1 Create Shared Folder Manually
1. **Right-click VM** → **Settings**
2. Go to **Shared Folders** tab
3. Click **Add**
4. Select host folder: `C:\Shared\openclaw-secrets`
5. VM folder name: `openclaw-secrets`
6. Check: **Enabled**, **Read-only** (optional)
7. Click **OK**

#### 1.2 Verify Shared Folder
In VM: `vmware-hgfsClient mount` should show the mount

---

## Part 2: Configure Mount on OpenClaw VM

### 2.1 Install NFS Client (for NFSv4 mounts)
```bash
# On OpenClaw VM:
sudo apt-get update
sudo apt-get install -y nfs-common
```

### 2.2 Create Mount Point
```bash
# On OpenClaw VM:
sudo mkdir -p /mnt/vmshared
sudo chown root:root /mnt/vmshared
sudo chmod 755 /mnt/vmshared
```

### 2.3 Mount Shared Folder

#### Option A: NFS Mount (Linux/UNIX Host)
```bash
# Identify host IP (e.g., 192.168.1.100)
HOST_IP="192.168.1.100"

# Mount shared folder:
sudo mount -t nfs4 ${HOST_IP}:/var/shared/openclaw-secrets /mnt/vmshared

# Verify:
mount | grep vmshared
ls -la /mnt/vmshared/
```

#### Option B: VMHGFS Mount (VMware Workstation)
```bash
# Mount VMware shared folder:
sudo mount -t vmhgfs .host:/openclaw-secrets /mnt/vmshared

# Verify:
mount | grep vmshared
```

#### Option C: SMB/CIFS Mount (Windows Host)
```bash
# Mount Windows shared folder:
sudo mount -t cifs //192.168.1.100/shared/openclaw-secrets \
  -o username=DOMAIN\\user,password=pass /mnt/vmshared

# Or with credentials file:
sudo mount -t cifs //192.168.1.100/shared/openclaw-secrets \
  -o credentials=/root/.smbcredentials /mnt/vmshared

# Create credentials file:
echo "username=DOMAIN\\user" > ~/.smbcredentials
echo "password=your_password" >> ~/.smbcredentials
chmod 600 ~/.smbcredentials
```

### 2.4 Verify Mount
```bash
# Check mount status:
sudo mount | grep vmshared

# Test write permission:
sudo touch /mnt/vmshared/test.txt
sudo ls -la /mnt/vmshared/
sudo rm /mnt/vmshared/test.txt

# Check permissions:
stat /mnt/vmshared/
```

### 2.5 Create Symlink to Secret Directory
```bash
# Create symlink so OpenClaw can access at standard path:
sudo ln -s /mnt/vmshared /opt/openclaw/secrets

# Verify:
ls -la /opt/openclaw/secrets
```

### 2.6 Persistent Mount (Auto-mount on Boot)

#### Edit /etc/fstab
```bash
# For NFS:
sudo bash -c 'echo "192.168.1.100:/var/shared/openclaw-secrets /mnt/vmshared nfs4 defaults,ro,hard,intr 0 0" >> /etc/fstab'

# For CIFS/SMB:
sudo bash -c 'echo "//192.168.1.100/shared/openclaw-secrets /mnt/vmshared cifs credentials=/root/.smbcredentials,ro,uid=1000,gid=1000 0 0" >> /etc/fstab'

# For VMHGFS:
sudo bash -c 'echo ".host:/openclaw-secrets /mnt/vmshared vmhgfs defaults,ro 0 0" >> /etc/fstab'

# Test fstab:
sudo mount -a

# Verify:
mount | grep vmshared
```

#### Or Use Systemd Mount Unit (More Reliable)
```bash
# Create mount unit file:
sudo tee /etc/systemd/system/mnt-vmshared.mount > /dev/null << EOF
[Unit]
Description=OpenClaw VMware Shared Folder
After=network-online.target
Wants=network-online.target

[Mount]
What=192.168.1.100:/var/shared/openclaw-secrets
Where=/mnt/vmshared
Type=nfs4
Options=defaults,ro,hard,intr,_netdev

[Install]
WantedBy=multi-user.target
EOF

# Enable and start:
sudo systemctl daemon-reload
sudo systemctl enable mnt-vmshared.mount
sudo systemctl start mnt-vmshared.mount

# Verify:
sudo systemctl status mnt-vmshared.mount
```

---

## Part 3: Configure OpenClaw Docker to Access Shared Folder

### 3.1 Update docker-compose.yml

Modify `/opt/openclaw/docker-compose.yml`:

```yaml
version: '3.8'

services:
  openclaw-gateway:
    image: openclaw:latest
    container_name: openclaw-gateway
    ports:
      - "18789:18789"
    networks:
      - openclaw
    volumes:
      # Shared folder (read-only) for secrets
      - /opt/openclaw/secrets:/opt/openclaw/secrets:ro
      
      # Standard volumes
      - /opt/openclaw/.openclaw:/opt/openclaw/.openclaw
      - /opt/openclaw/workspace:/opt/openclaw/workspace
    env_file:
      - /opt/openclaw/.env
    environment:
      - OPENCLAW_SECRETS_PATH=/opt/openclaw/secrets
      - OPENCLAW_WHATSAPP_CONFIG_FILE=/opt/openclaw/secrets/.whatsapp-config.json
      - OPENCLAW_GOOGLE_CREDENTIALS_FILE=/opt/openclaw/secrets/.google-credentials.json
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  openclaw-cli:
    image: openclaw:latest
    container_name: openclaw-cli
    depends_on:
      - openclaw-gateway
    networks:
      - openclaw
    volumes:
      # Shared folder for secrets
      - /opt/openclaw/secrets:/opt/openclaw/secrets:ro
      
      # Standard volumes
      - /opt/openclaw/.openclaw:/opt/openclaw/.openclaw
      - /opt/openclaw/workspace:/opt/openclaw/workspace
    env_file:
      - /opt/openclaw/.env
    environment:
      - OPENCLAW_SECRETS_PATH=/opt/openclaw/secrets
      - OPENCLAW_GATEWAY_URL=http://openclaw-gateway:18789
    command: ["tail", "-f", "/dev/null"]  # Keep running
    restart: always

networks:
  openclaw:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

### 3.2 Verify Docker Access to Secrets

```bash
# Check if volume is mounted in container:
sudo docker compose -f /opt/openclaw/docker-compose.yml exec openclaw-gateway ls -la /opt/openclaw/secrets/

# Test reading a secret file:
sudo docker compose -f /opt/openclaw/docker-compose.yml exec openclaw-gateway cat /opt/openclaw/secrets/.whatsapp-config.json

# Verify read-only:
sudo docker compose -f /opt/openclaw/docker-compose.yml exec openclaw-gateway touch /opt/openclaw/secrets/test.txt
# Expected: Permission denied
```

---

## Part 4: Prepare Secret Files on Host

### 4.1 Create Secrets Directory Structure
```bash
# On VMware host:
mkdir -p /var/shared/openclaw-secrets

# Set appropriate permissions:
chmod 755 /var/shared/openclaw-secrets
```

### 4.2 Add Credentials Files

#### WhatsApp API Configuration
```bash
# Create .whatsapp-config.json on host:
cat > /var/shared/openclaw-secrets/.whatsapp-config.json << 'EOF'
{
  "account_id": "YOUR_WHATSAPP_ACCOUNT_ID",
  "access_token": "YOUR_WHATSAPP_ACCESS_TOKEN",
  "phone_number_id": "YOUR_PHONE_NUMBER_ID",
  "webhook_token": "YOUR_WEBHOOK_VERIFY_TOKEN"
}
EOF

chmod 600 /var/shared/openclaw-secrets/.whatsapp-config.json
```

#### Google API Credentials
```bash
# Add Google credentials file on host:
cp ~/Downloads/google-credentials.json /var/shared/openclaw-secrets/.google-credentials.json
chmod 600 /var/shared/openclaw-secrets/.google-credentials.json
```

#### Additional Secrets
```bash
# Create generic secrets file:
cat > /var/shared/openclaw-secrets/.env.secrets << 'EOF'
# WhatsApp
WHATSAPP_API_KEY=your_whatsapp_api_key
WHATSAPP_ACCOUNT_ID=your_account_id

# Google
GOOGLE_API_KEY=your_google_api_key
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret

# Other services
DISCORD_BOT_TOKEN=your_discord_token
MATRIX_HOMESERVER=https://matrix.org
EOF

chmod 600 /var/shared/openclaw-secrets/.env.secrets
```

### 4.3 Verify File Permissions (Host)
```bash
# Verify owner and permissions:
ls -la /var/shared/openclaw-secrets/

# Expected output:
# -rw------- 1 root root 256 Feb 12 10:30 .whatsapp-config.json
# -rw------- 1 root root 512 Feb 12 10:30 .google-credentials.json
# -rw------- 1 root root 384 Feb 12 10:30 .env.secrets
```

---

## Part 5: Test Integration

### 5.1 Start OpenClaw Docker Compose
```bash
# On OpenClaw VM:
cd /opt/openclaw
sudo docker compose up -d

# Wait for container to start:
sleep 10
```

### 5.2 Verify Secrets Accessible
```bash
# Check container can read secrets:
sudo docker compose exec openclaw-gateway ls -la /opt/openclaw/secrets/

# Test reading WhatsApp config:
sudo docker compose exec openclaw-gateway cat /opt/openclaw/secrets/.whatsapp-config.json

# Verify env var configuration:
sudo docker compose exec openclaw-gateway env | grep OPENCLAW_SECRETS_PATH
```

### 5.3 Verify Read-Only Access
```bash
# Attempt to write (should fail):
sudo docker compose exec openclaw-gateway touch /opt/openclaw/secrets/test.txt
# Expected: Permission denied

# Verify directory listing works:
sudo docker compose exec openclaw-gateway find /opt/openclaw/secrets -type f
```

### 5.4 Test Gateway Functionality
```bash
# Check gateway is running:
curl http://localhost:18789/health
# Expected: 200 OK

# Access gateway from another Tailscale device:
# From trusted device:
curl http://100.64.x.101:18789/health
```

---

## Part 6: Security Best Practices

### 6.1 File Permissions on Host
```bash
# Recommended permissions:
find /var/shared/openclaw-secrets -type f -exec chmod 600 {} \;
find /var/shared/openclaw-secrets -type d -exec chmod 755 {} \;

# Verify:
stat /var/shared/openclaw-secrets/.whatsapp-config.json
# Should show: Access: (0600/-rw-------)
```

### 6.2 Mount Options on VM
```bash
# Use read-only mount to prevent accidental modification:
# In /etc/fstab:
192.168.1.100:/var/shared/openclaw-secrets /mnt/vmshared nfs4 defaults,ro,hard,intr 0 0

# Verify read-only:
mount | grep vmshared | grep -i "ro"
```

### 6.3 Docker Volume Permissions
```bash
# In docker-compose.yml, use read-only volume:
volumes:
  - /opt/openclaw/secrets:/opt/openclaw/secrets:ro  # :ro = read-only
```

### 6.4 Secrets Rotation
```bash
# Update secrets on host:
nano /var/shared/openclaw-secrets/.whatsapp-config.json

# Restart OpenClaw to pick up changes:
sudo docker compose restart openclaw-gateway

# No downtime needed; just a graceful restart
```

### 6.5 Access Control
```bash
# Only OpenClaw user can access:
ls -la /opt/openclaw/secrets/
# Should show: drwxr-xr-x (755) for directory, but files are 600

# Verify OpenClaw user can read:
sudo docker compose exec openclaw-gateway id
# Should show: uid=1000(openclaw) gid=1000(openclaw)
```

---

## Troubleshooting

### Problem: Mount fails at boot
```bash
# Check logs:
sudo systemctl status mnt-vmshared.mount
sudo journalctl -u mnt-vmshared.mount -n 50

# If NFS, verify server is accessible:
ping 192.168.1.100
showmount -e 192.168.1.100
```

### Problem: OpenClaw cannot read secrets
```bash
# 1. Verify mount exists:
ls -la /mnt/vmshared/

# 2. Verify symlink:
ls -la /opt/openclaw/

# 3. Check in container:
sudo docker compose exec openclaw-gateway ls /opt/openclaw/secrets/

# 4. Check container logs:
sudo docker compose logs openclaw-gateway
```

### Problem: Permission denied when reading secrets
```bash
# 1. Check file permissions on host:
ls -la /var/shared/openclaw-secrets/

# 2. Check mount permissions on VM:
stat /mnt/vmshared/

# 3. Check container user:
sudo docker compose exec openclaw-gateway id

# 4. Fix permissions:
sudo chmod 755 /var/shared/openclaw-secrets
sudo chmod 644 /var/shared/openclaw-secrets/*
```

### Problem: Host changes not visible in container
```bash
# 1. Container may have cached data, restart:
sudo docker compose restart openclaw-gateway

# 2. Verify mount on VM:
mount | grep vmshared

# 3. Manually verify file contents:
sudo cat /mnt/vmshared/.whatsapp-config.json
```

---

## Summary

| Step | Command | Purpose |
|------|---------|---------|
| 1 | Export folder from host | NFS/CIFS/VMHGFS share |
| 2 | Mount on VM | `sudo mount -t nfs4 ...` |
| 3 | Verify mount | `mount \| grep vmshared` |
| 4 | Create symlink | `sudo ln -s /mnt/vmshared /opt/openclaw/secrets` |
| 5 | Update docker-compose.yml | Add volume mount |
| 6 | Add secret files | Copy credentials to host folder |
| 7 | Test access | `docker compose exec ... cat` |
| 8 | Verify read-only | `docker compose exec ... touch` (should fail) |

---

## Next Steps

1. ✅ Configure shared folder on VMware host
2. ✅ Mount shared folder on OpenClaw VM
3. ✅ Update docker-compose.yml with volumes
4. ✅ Add secret files to host shared folder
5. ✅ Test OpenClaw access to secrets
6. ⊘ Configure Tailscale ACL (see TAILSCALE-ACL-CONFIGURATION.md)
7. ⊘ Deploy OpenClaw with API integrations

**Benefit:** Your API credentials are now:
- ✅ Separate from Docker image
- ✅ Stored securely on host (not in containers)
- ✅ Easy to rotate without rebuilding
- ✅ Protected by read-only mounts
- ✅ Isolated from Tailscale network (local storage only)

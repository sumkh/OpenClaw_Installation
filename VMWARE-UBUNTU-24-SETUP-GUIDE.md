# VMware Ubuntu 24.04 LTS VM Configuration Guide

## Overview

This guide provides step-by-step instructions to configure and deploy an Ubuntu Server 24.04.3 LTS virtual machine in VMware with recommended specifications (8vCPU, 18GB RAM, 50GB Storage) for optimal OpenClaw performance.

---

## Table of Contents

1. [VM Creation in VMware](#vm-creation-in-vmware)
2. [Hardware Configuration (Recommended Specs)](#hardware-configuration-recommended-specs)
3. [Ubuntu 24.04 LTS Installation](#ubuntu-2404-lts-installation)
4. [Post-Installation Setup](#post-installation-setup)
5. [Pre-OpenClaw Verification](#pre-openclaw-verification)
6. [Quick Start Script](#quick-start-script)

---

## VM Creation in VMware

### Step 1: Create New Virtual Machine

#### In VMware vSphere Web Client

1. **Right-click on ESXi host** → **"Storage"** or **"Virtual Machines"**
2. Click **"+ Create a new virtual machine"** (or similar option)
3. Choose **"Create a new virtual machine"** (not clone/template)
4. Click **"Next"**

#### In VMware Workstation Pro/Player

1. **File** → **New Virtual Machine**
2. Select **"Custom (Advanced)"**
3. Click **"Next"**

### Step 2: Name and Folder

```
VM Name: openclaw-gateway
Folder: [Choose your datacenter/folder]
Compatibility: ESXi 8.0 or later (or your ESXi version)
```

Click **"Next"**

### Step 3: Guest OS Selection

```
Datastore: [Select default or preferred storage]
```

For the next screen:

```
Guest OS Family:     Linux
Guest OS Version:    Ubuntu Linux 24.04 LTS
```

Click **"Next"**

---

## Hardware Configuration (Recommended Specs)

### CPU, Memory & Storage Settings

```
┌─────────────────────────────────────────────────────┐
│  RECOMMENDED SPECIFICATIONS                         │
├─────────────────────────────────────────────────────┤
│  CPUs:              8 vCPU                          │
│  Memory:            18 GB RAM                       │
│  Storage:           50 GB (Thin Provisioned)        │
│  Network:           VMXNET3 (Paravirtual)          │
│  Video Memory:      128 MB                          │
│  SCSI Controller:   LSI SAS 1068 (or VMware)       │
└─────────────────────────────────────────────────────┘
```

#### Step 1: CPU Configuration
```
Number of Virtual CPUs:    8
Cores per CPU:             4 (2 sockets × 4 cores)
   or
Cores per CPU:             1 (8 sockets × 1 core)  ← Recommended for guest OS licensing
```

➤ **Why 8 vCPU?**
- Docker daemon: 1 vCPU
- OpenClaw gateway: 2 vCPU
- CLI tools/utilities: 1 vCPU
- System services/overhead: 4 vCPU buffer
- **Total: ~8 vCPU for comfortable performance**

#### Step 2: Memory Configuration
```
Memory:    18 GB (18,432 MB)
```

Breakdown:
- Host OS (Ubuntu): 1 GB
- Docker daemon: 1 GB
- OpenClaw containers: 10-12 GB
- System cache/buffers: 4-6 GB
- **Total: 18 GB for stable operation**

#### Step 3: Storage Configuration
```
Storage:                  50 GB
Provisioning:            Thin Provisioned  ← Saves space, grows as needed
Disk Type:               VMDK (VMware Virtual Machine Disk)
Datastore:               [Your datastore]
Controller:              LSI SAS 1068 or VMware Paravirtual SCSI
```

Why Thin Provisioning?
- Saves initial disk space (grows as you use it)
- Fine for non-critical workloads
- Allocate from datastore with enough free space (at least 100GB recommended)

#### Step 4: Network Configuration
```
Network Adapter 1:    VMXNET3 (Paravirtual)  ← Recommended for performance
Network Connection:   Bridged or NAT (per your lab setup)
MAC Address:          Auto-generated
```

Why VMXNET3?
- Better performance than E1000
- Lower latency
- Optimal for Docker networking

#### Step 5: Advanced Settings
```
Virtual TPM:          Disabled (for Ubuntu 24.04 standard)
EFI Firmware:         Enabled (Recommended for UEFI boot)
Secure Boot:          Disabled initially (can enable after installation)
```

**Note on EFI:** Ubuntu 24.04 supports UEFI. If your ESXi supports it, use it for modern BIOS support.

### Storage Allocation Details

Since you mentioned 50GB, here's the recommended layout:

```
50 GB Total Allocation
├─ Root Filesystem (/):         30 GB
│  ├─ OS + system packages:     8 GB
│  ├─ Docker images:            12 GB (openclaw:local built image)
│  ├─ Docker layers:            8 GB
│  └─ Headroom:                 2 GB
├─ /var/lib/docker:             15 GB (container data)
│  ├─ Volumes (config/data):    10 GB
│  ├─ Container storage:        3 GB
│  └─ Logs:                     2 GB
└─ /var/backups/openclaw:       5 GB (for backups)
```

**If upgrading to 100GB (recommended for production):**

```
100 GB Total Allocation
├─ Root Filesystem (/):         50 GB
├─ /var/lib/docker:             35 GB
└─ /var/backups/openclaw:       15 GB (more backup history)
```

---

## Ubuntu 24.04 LTS Installation

### Step 1: Download ISO

**Download from:**
- Ubuntu: https://releases.ubuntu.com/24.04/
- File: `ubuntu-24.04.3-live-server-amd64.iso` (or latest 24.04)
- Size: ~1.3 GB
- Checksum: Verify SHA256 from official source

### Step 2: Mount ISO in VMware

**In vSphere Web Client:**
1. VM Settings → CD/DVD Drive → Datastore ISO file
2. Browse → Select downloaded ISO
3. Check "Connect" box

**In Workstation Pro/Player:**
1. VM Settings → CD/DVD Drive
2. Use ISO file image → Browse to downloaded ISO
3. Click OK

### Step 3: Boot from ISO

1. Power on the VM
2. Press **F2** or **Esc** (depending on ESXi version) to enter BIOS
3. Set boot order: CD/DVD first
4. Save and exit
5. VM should boot from ISO

### Step 4: Ubuntu Installation Screens

#### Screen 1: Language Selection
```
Language:   English
Location:   [Your timezone]
```
Press **Enter** to continue.

#### Screen 2: Keyboard Layout
```
Keyboard layout:     English (US)  ← or your preference
```
Use **Tab** to navigate, **Enter** to select.

#### Screen 3: Network Configuration
```
Network Interface:     eth0 or ens33/ens160 (VMware VMXNET3)
IPv4 Method:          DHCP  ← or Static (if you prefer fixed IP)
IPv6:                 Enabled (optional)
```

**If using Static IP** (recommended for servers):
```
IPv4 Method:          Static
Address:              192.168.x.x/24 (your subnet)
Gateway:              192.168.x.1
Nameservers:          8.8.8.8, 8.8.4.4
Search domains:       (leave empty or domain name)
```

Press **Tab** to "Done" and **Enter**.

#### Screen 4: Proxy Configuration
```
Proxy address:  (leave empty unless using proxy)
```
Press **Enter** to skip.

#### Screen 5: Ubuntu Archive Mirror
```
Mirror address:  http://archive.ubuntu.com/ubuntu  (default is fine)
```
Press **Enter** to continue.

#### Screen 6: Disk Configuration
```
Use Entire Disk:       Yes
Disk:                  /dev/sda (VMware allocated disk)
Partition scheme:      LVM (recommended)
Setup LVM:             Yes
Encrypt LVM:           No (personal choice; slows performance)
```

⚠️ **Warning**: This will erase the entire disk. Confirm you're on the correct disk.

Recommended partition layout:
```
/           (root):    30 GB (or 50 GB if using thin provisioning)
/boot:      1 GB
swap:       Not needed (use zswap if needed)
```

#### Screen 7: Storage Summary
```
Review partitions...
Boot loader installation: /dev/sda
```
Confirm and press **Enter** to proceed.

#### Screen 8: Account Setup
```
Profile name:        ubuntu  ← Your login username
Server name:         openclaw-gateway  ← VM hostname
Password:            [Strong password: 16+ chars, mixed]
Confirm password:    [Same password]
```

**Example strong password:**
```
A_Str0ng!Passw0rd#2024
```

#### Screen 9: SSH Setup
```
Install OpenSSH server:   YES  ← Important for remote access
Import SSH public keys:    YES (if available) or NO
Allow password auth:       NO  (use keys only) ← Recommended
```

#### Screen 10: Featured Snaps
```
Docker:  ☐ (uncheck - we'll install Docker via installation script)
Others:  ☐ (leave unchecked)
```

#### Screen 11: Installation Complete
```
Installation complete. System will reboot.
```

Eject ISO before reboot:
1. VM button → CD/DVD → Disconnect
2. Wait for reboot
3. Remove ISO from datastore (optional)

### Step 5: Post-Installation Boot

Ubuntu should boot into login prompt:
```
openclaw-gateway login: _
```

✅ Installation complete!

---

## Post-Installation Setup

### Step 1: Initial SSH Connection

**From host machine:**
```bash
ssh ubuntu@<vm-ip-address>
```

**Or via Tailscale (once setup):**
```bash
ssh ubuntu@<tailscale-ip>
```

### Step 2: Update System

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
```

Expected time: 2-5 minutes (first update can install many packages)

### Step 3: Configure Static IP (Optional but Recommended)

**Check current IP:**
```bash
ip addr show
```

**Edit netplan configuration:**
```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

**Example static config:**
```yaml
network:
  version: 2
  ethernets:
    eth0:               # or ens160
      dhcp4: false
      addresses:
        - 192.168.1.101/24
      routes:
        - to: 0.0.0.0/0
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

**Apply changes:**
```bash
sudo netplan apply
ip addr show
```

### Step 4: Harden SSH (Important!)

```bash
sudo nano /etc/ssh/sshd_config
```

Make these changes:
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
```

**Restart SSH:**
```bash
sudo systemctl restart ssh
```

### Step 5: Set Hostname

```bash
sudo hostnamectl set-hostname openclaw-gateway
sudo nano /etc/hosts
```

Add:
```
127.0.0.1   localhost
127.0.1.1   openclaw-gateway
```

### Step 6: Set Timezone (Important for Logs)

```bash
sudo timedatectl set-timezone UTC
# or your preferred timezone: timedatectl list-timezones
```

---

## Pre-OpenClaw Verification

Before running installation scripts, verify:

```bash
# Check OS version
cat /etc/os-release | grep -E "^NAME|^VERSION"
# Output: NAME="Ubuntu", VERSION="24.04.3 LTS"

# Check available storage
df -h /
# Output: "50G total, X used, Y available"

# Check CPU count
nproc
# Output: 8

# Check RAM
free -h
# Output: "Mem: 18G"

# Check kernel
uname -r
# Output: "6.8.x-x-generic" (Ubuntu 24.04 typical)

# Check network
ip route show
# Output: Shows default gateway

# Verify internet connectivity
ping -c 1 8.8.8.8
# Output: "1 packets transmitted, 1 received"
```

All should show allocated resources. If not, check VMware console.

---

## Quick Start Script

Once VM is set up and verified, prepare for OpenClaw:

```bash
# Create working directory
mkdir -p ~/openclaw-setup
cd ~/openclaw-setup

# Download installation scripts from GitHub
git clone https://github.com/sumkh/OpenClaw_Installation.git
cd OpenClaw_Installation

# Make scripts executable
chmod +x *.sh

# Verify checksums (optional but recommended)
sha256sum -c checksums.txt 2>/dev/null || echo "No checksums.txt found"

# Run installation sequence
sudo ./01-initial-setup.sh              # ~5-10 minutes (hardening)
sudo ./02-install-openclaw.sh           # ~15-20 minutes (Docker build)
sudo ./03-setup-tailscale.sh            # ~2-3 minutes (Tailscale setup)
sudo ./04-post-install-security.sh      # ~5 minutes (security hardening)

# Verify installation
sudo systemctl status openclaw
sudo docker compose -f /opt/openclaw/docker-compose.yml ps
sudo tailscale status
```

**Total time:** ~40-50 minutes for complete setup

---

## Hardware Specifications Summary Table

| Component | Minimum | Recommended | Production |
|-----------|---------|-------------|-----------|
| **vCPU** | 4 | **8** | 16 |
| **RAM** | 8 GB | **18 GB** | 32 GB |
| **Storage** | 50 GB | **50-75 GB** | 100-200 GB |
| **Storage Type** | SATA | **Thin SSD** | SSD |
| **NIC** | E1000 | **VMXNET3** | VMXNET3 |
| **Boot Mode** | BIOS | **UEFI** | UEFI |
| **Encryption** | None | LVM (optional) | LVM + TDE |

---

## Network Configuration Summary

### Network Interfaces After Setup

```
ESXi Host
    ├─ Management Network (vMkernel)
    └─ VMware Port Group (Standard or Distributed)
        └─ OpenClaw VM (VMXNET3)
            ├─ Physical Network (eth0/ens160)
            │  ├─ IP: 192.168.x.x (Tailscale joins here)
            │  └─ Gateway: 192.168.x.1
            ├─ Tailscale Tunnel
            │  └─ IP: 100.64.x.101 (virtual mesh IP)
            └─ Docker Internal Bridge
               ├─ Gateway IP: 172.28.0.1
               └─ Container IPs: 172.28.0.2+
```

### Firewall Rules After Installation

```
Inbound Rules (UFW) - Default Deny
├─ Allow: Tailscale (41641/udp) - always
├─ Allow: SSH (22/tcp) - via Tailscale only
└─ Allow: HTTP/HTTPS (80,443/tcp) - if needed

Outbound Rules (UFW) - Default Allow
├─ Allow: Tailscale (443/tcp)
├─ Allow: Docker Hub (443/tcp)
├─ Allow: GitHub (443/tcp)
└─ Allow: System updates (80,443/tcp)
```

---

## Performance Tuning (Optional)

### Enable Nested Virtualization (if needed)
For VT-x/AMD-V support in Docker:

```bash
# Check current setting
sudo grep -o 'nested' /etc/vmx-commands.txt 2>/dev/null || echo "Not found"

# In VMware vSphere: VM Settings → CPU → Advanced → "Enable hardware assisted virtualization"
```

### Optimize Docker Storage

```bash
sudo nano /etc/docker/daemon.json
```

Add:
```json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "insecure-registries": ["localhost:5000"]
}
```

Restart: `sudo systemctl restart docker`

### Enable Swap (for additional memory buffer)

```bash
# Check current swap
free -h

# If none, create 4GB swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Troubleshooting VM Creation

### Issue: "Cannot allocate 18GB RAM"
- **Solution:** Check ESXi host has sufficient free memory. Reduce to 16GB if needed.

### Issue: "Thin provisioning not supported"
- **Solution:** Use eager-zeroed thick provisioning instead (slower initial write, but stable).

### Issue: "VMXNET3 driver not available"
- **Solution:** Use E1000e or E1000 (lower performance but compatible).

### Issue: "Ubuntu 24.04 not in guest OS list"
- **Solution:** Select "Linux" → "Other Linux" → Edit VM settings post-creation.

### Issue: "Network not responding during installation"
- **Solution:** Ensure VMware port group is connected to physical network or configured for DHCP.

---

## First Boot & SSH Connection Troubleshooting

### Problem: Cannot SSH to VM

If you're having trouble connecting to the VM via SSH (e.g., "command not found" on network utilities):

#### Step 1: Get the VM's IP Address

**On the VM Console** (directly at VMware ESXi/Workstation):

```bash
# ✓ Correct Linux commands:
ip addr show          # Shows all network interfaces and IPs
hostname -I           # Shows just the IP address
ip route              # Shows network routes

# ✗ Do NOT use (these are Windows commands):
ipconfig              # NOT on Linux
ipconfig /all         # NOT on Linux
```

**Save the IP address** (e.g., `192.168.1.101`)

#### Step 2: SSH from Host Machine

**On your host machine** (Windows, Mac, Linux):

```powershell
# PowerShell on Windows:
ssh ubuntu@192.168.1.101
# Replace 192.168.1.101 with your actual VM IP

# macOS/Linux terminal:
ssh ubuntu@192.168.1.101
```

**First connection prompt:**
```
The authenticity of host '192.168.1.101 (192.168.1.101)' can't be established.
Are you sure you want to continue connecting (yes/no)?
```

**Type `yes` and press Enter.**

#### Step 3: If SSH Fails - Troubleshooting

**Check SSH service is running (on VM):**
```bash
sudo systemctl status ssh
# Expected: active (running)

# If not running:
sudo systemctl start ssh
sudo systemctl enable ssh
```

**Check network connectivity (on VM):**
```bash
ping 8.8.8.8
# Should get responses

# Check firewall isn't blocking SSH:
sudo ufw status
sudo ufw allow 22/tcp   # Allow SSH if needed
```

**Test SSH locally (on VM):**
```bash
ssh localhost
# If this fails, SSH service has issues

# If it works, try direct SSH from host again
```

**Verify SSH is listening (on VM):**
```bash
sudo ss -tlnp | grep ssh
# Should show:
# tcp   0   0 0.0.0.0:22   0.0.0.0:*   LISTEN
```

#### Step 4: Password vs. SSH Keys

**If using password authentication** (set during Ubuntu installation):
```bash
# Just enter your password when prompted:
ssh ubuntu@192.168.1.101
# Password: [type your Ubuntu password]
```

**If using SSH keys:**
```bash
# First time setup - generate key pair:
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""

# Copy public key to VM:
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@192.168.1.101

# Future logins don't need password
```

### Common SSH Issues

| Issue | Solution |
|-------|----------|
| "Connection refused" | `sudo systemctl start ssh` on VM |
| "Connection timed out" | Check VM IP is correct; verify network connectivity |
| "Permission denied" | Use correct password or SSH key; check key permissions |
| "Command not found" | Using Windows commands; see table below |

### Command Reference: Linux vs Windows

| Task | Windows | Linux/Ubuntu |
|------|---------|--------------|
| **List network interfaces** | `ipconfig` | `ip addr show` |
| **Get IP only** | `ipconfig /all` | `hostname -I` |
| **List processes** | `tasklist` | `ps aux` |
| **Clear screen** | `cls` | `clear` |
| **Check disk space** | `dir` | `df -h` |
| **Check memory** | `systeminfo` | `free -h` |
| **Restart service** | `net start svc` | `sudo systemctl start svc` |

**Key point:** Once you SSH into the Ubuntu VM, you're in Linux. Use Linux commands, not Windows commands.

---

## Post-VM Creation Checklist

- [ ] VM boots successfully to login prompt
- [ ] Static IP configured (if desired)
- [ ] SSH key-based authentication working
- [ ] `uname -r` shows Linux kernel 6.8+
- [ ] `df -h` shows 50GB available
- [ ] Free RAM shows ~18GB available
- [ ] `nproc` shows 8 CPUs
- [ ] Internet connectivity verified (`ping 8.8.8.8`)
- [ ] Tailscale joined your existing mesh
- [ ] Installation scripts ready to run

**Once all checks pass, proceed with OpenClaw installation using the scripts in OpenClaw_Installation folder.**

---

## Quick Reference: Network Access After Setup

```
Via Tailscale:
ssh ubuntu@100.64.x.101
http://100.64.x.101:18789

Via Host Network (if direct):
ssh ubuntu@192.168.x.x
http://192.168.x.x:18789  (if exposed)

Via Tailscale MagicDNS (if enabled):
ssh ubuntu@openclaw-gateway.tailnet-xxxx.ts.net
http://openclaw-gateway.tailnet-xxxx.ts.net:18789
```

📌 **Note:** Recommended access method is **Tailscale** for security and encryption.


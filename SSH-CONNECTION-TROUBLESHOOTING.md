# OpenClaw VM - Initial SSH Connection Troubleshooting

## Issue: Cannot SSH to VM, `ipconfig` command not found

This guide helps you troubleshoot SSH connectivity to your OpenClaw Ubuntu VM.

---

## Quick Fix

The issue is that **`ipconfig` is a Windows command, not Linux**.

On Ubuntu/Linux VMs, you need to use **`ip`** command instead:

```bash
# On the Ubuntu VM:
ip addr show
# or
hostname -I
```

---

## Step-by-Step Troubleshooting

### Phase 1: Get the VM's IP Address

#### **On the Ubuntu VM Console** (direct at VMware ESXi/Workstation):

```bash
# Method 1: Get IP address
ip addr show
# Look for line like: inet 192.168.1.101/24

# Method 2: Get just the IP
hostname -I
# Output: 192.168.1.101

# Method 3: Check network interfaces
ip link show
# Should see: eth0 or ens33 or enp0s3 (depending on driver)

# Method 4: Get IP with netplan (Ubuntu 24.04)
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
```

**Save this IP address** (e.g., `192.168.1.101`)

---

### Phase 2: SSH from Host Machine to VM

#### **On Host Machine (Windows, Mac, or Linux):**

```powershell
# PowerShell on Windows Host:
ssh ubuntu@192.168.1.101
# Replace 192.168.1.101 with your VM's IP

# When prompted:
# Type: yes
# Then enter password OR ssh key passphrase
```

```bash
# macOS/Linux host:
ssh ubuntu@192.168.1.101
# Same as above
```

**Expected first connection:**
```
The authenticity of host '192.168.1.101 (192.168.1.101)' can't be established.
ECDSA key fingerprint is SHA256:xxxxx
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Type `yes` and press Enter.**

---

### Phase 3: If SSH Still Fails

#### **Check 1: Verify SSH Service is Running (on VM)**

```bash
# On Ubuntu VM console:
sudo systemctl status ssh
# Expected: active (running)

# If not running:
sudo systemctl start ssh
sudo systemctl enable ssh
```

#### **Check 2: Verify Network Connectivity**

```bash
# On Ubuntu VM:
ping 8.8.8.8
# Should get responses

# If fails, check DNS:
cat /etc/resolv.conf
# Should show nameserver entries
```

#### **Check 3: Check Firewall on VM**

```bash
# On Ubuntu VM:
sudo ufw status
# Expected: Status: inactive (or showing allow rules)

# If blocking SSH:
sudo ufw allow 22
sudo ufw reload
```

#### **Check 4: Verify SSH Port (on VM)**

```bash
# On Ubuntu VM:
sudo netstat -tlnp | grep ssh
# or:
sudo ss -tlnp | grep ssh

# Expected output:
# tcp   0   0 0.0.0.0:22   0.0.0.0:*   LISTEN
```

#### **Check 5: Test SSH Locally (on VM)**

```bash
# On Ubuntu VM:
ssh localhost
# Should connect without password (if key auth enabled)

# If fails, SSH service has issues
```

---

## Common SSH Scenarios

### Scenario 1: "Connection refused" / "Connection timed out"

**Causes:**
- SSH service not running
- Firewall blocking port 22
- Wrong IP address

**Solution:**
```bash
# On VM:
sudo systemctl start ssh
sudo systemctl enable ssh

# Check if listening:
sudo netstat -tlnp | grep 22

# Allow through firewall:
sudo ufw allow 22/tcp
```

### Scenario 2: "Permission denied (publickey)" / "Authentication failed"

**Causes:**
- SSH keys not configured
- Wrong keyfile permissions
- SSH config has issues

**Solution:**
```bash
# On Host, check key file permissions:
# macOS/Linux:
ls -la ~/.ssh/id_rsa
# Should show: -rw------- (600)

# If wrong permissions:
chmod 600 ~/.ssh/id_rsa

# Windows PowerShell - check key permissions:
Get-Item -Path "$env:USERPROFILE\.ssh\id_rsa" | Get-Acl
# Should show only your user has access

# Copy public key to VM:
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@192.168.1.101
```

### Scenario 3: No Key Authentication (First Time Setup)

**If you set a password during Ubuntu installation:**

```bash
# On Host - SSH with password authentication:
ssh ubuntu@192.168.1.101
# It will prompt for password

# Then on VM - generate SSH key for host:
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@192.168.1.101

# Now future logins don't need password
```

---

## Complete SSH Setup Workflow

### Step 1: Get VM IP
```bash
# On VM console (direct at hypervisor):
hostname -I
# Save this IP (e.g., 192.168.1.101)
```

### Step 2: Test SSH Connection
```bash
# On Host machine:
ssh ubuntu@192.168.1.101
# Should succeed (if using password) or ask for SSH key passphrase
```

### Step 3: If Password Prompt Appears
```bash
# Enter the password you set during Ubuntu installation
# Once logged in, you're in the VM for future commands
```

### Step 4: Generate SSH Key (First Time)
```bash
# Still on VM:
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
# This creates key pair for password-less access
```

### Step 5: Download Key to Host (Optional)
```bash
# On Host - copy key from VM to host (for backup):
scp ubuntu@192.168.1.101:~/.ssh/id_rsa ~/openclw-vm-key.pem
chmod 600 ~/openclw-vm-key.pem

# Future logins:
ssh -i ~/openclw-vm-key.pem ubuntu@192.168.1.101
```

---

## Correct Commands for Ubuntu VM

### ❌ **Wrong (Windows Commands)**
```bash
ipconfig              # ← Windows
ipconfig /all         # ← Windows
netstat -an           # ← Windows format
tasklist              # ← Windows
cls                   # ← Windows
```

### ✅ **Correct (Linux/Unix Commands)**
```bash
ip addr show          # ← Ubuntu
hostname -I           # ← Ubuntu
ifconfig              # ← Ubuntu (if installed)
netstat -tlnp         # ← Ubuntu
ss -tlnp              # ← Ubuntu (modern)
ps aux                # ← Ubuntu
clear                 # ← Ubuntu
pwd                   # ← Print working directory
ls -la                # ← List files
```

---

## If You're Still in the Ubuntu VM

Check if you're already SSH'd into the VM:

```bash
# Run this command:
hostname

# If output shows: ubuntu-openclaw (or similar)
# ✓ You're already in the VM!

# Check IP:
hostname -I
# You can see the VM's IP here

# Exit VM and go back to host:
exit
# Now you're back on host
```

---

## Verification Matrix

| Task | Command | Expected Result |
|------|---------|-----------------|
| **Get VM IP** | `hostname -I` | `192.168.1.x` |
| **Check SSH running** | `sudo systemctl status ssh` | `active (running)` |
| **SSH listening** | `sudo netstat -tlnp \| grep 22` | `tcp ... LISTEN` |
| **DNS working** | `ping 8.8.8.8` | `replies from 8.8.8.8` |
| **Firewall allowing SSH** | `sudo ufw status` | `22/tcp ALLOW` or `inactive` |
| **SSH from host** | `ssh ubuntu@IP` | Connected prompt |

---

## Quick SSH Cheat Sheet

```bash
# Get IP address
ip addr show
hostname -I

# Check SSH service
sudo systemctl status ssh
sudo systemctl start ssh
sudo systemctl enable ssh

# Check SSH listening
sudo ss -tlnp | grep 22

# Allow SSH through firewall
sudo ufw allow 22

# Reload firewall
sudo ufw reload

# Test SSH locally
ssh localhost

# Connect from host
# Replace 192.168.1.101 with your VM IP
ssh ubuntu@192.168.1.101

# Copy SSH key to VM (if not using password)
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@192.168.1.101

# SSH with specific key
ssh -i ~/.ssh/mykey.pem ubuntu@192.168.1.101

# Show SSH config
cat ~/.ssh/config

# View SSH daemon config
sudo cat /etc/ssh/sshd_config

# Restart SSH service
sudo systemctl restart ssh
```

---

## Summary

| Issue | Solution |
|-------|----------|
| "`ipconfig` not found" | Use `hostname -I` or `ip addr show` instead |
| "Cannot SSH" | Check VM IP with `hostname -I`, then `ssh ubuntu@IP` |
| "SSH service not running" | `sudo systemctl start ssh` |
| "Firewall blocking" | `sudo ufw allow 22` |
| "Permission denied" | Fix SSH key permissions: `chmod 600 ~/.ssh/id_rsa` |
| "No key, need password" | Use password you set during Ubuntu install |

---

## Next Steps

Once SSH works:

```bash
# You're ready to run installation scripts:
# 1. SSH into VM
ssh ubuntu@192.168.1.101

# 2. Download scripts
git clone https://github.com/sumkh/OpenClaw_Installation.git
cd OpenClaw_Installation

# 3. Start installation
sudo chmod +x *.sh
sudo ./01-initial-setup.sh
```

---

**Common Misconception:** If you see Linux commands like `ip addr show`, `hostname -I`, or `sudo systemctl` returning "command not found", verify:
1. ✓ You're in a Linux/Ubuntu terminal (not Windows)
2. ✓ Ubuntu is fully installed and booted
3. ✓ You're using the correct command (not Windows equivalents)

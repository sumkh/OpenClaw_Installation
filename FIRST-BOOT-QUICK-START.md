# OpenClaw VM - First Boot Quick Start

## After Ubuntu VM Boots (First Time Setup)

You now have a running Ubuntu 24.04 LTS VM. Follow these steps to get it ready for OpenClaw installation.

---

## ⏱️ Estimated Time: 5-10 minutes

---

## Step 1: Get VM IP Address (1 minute)

### At the VM Console (Direct at VMware ESXi/Workstation)

You should see a login prompt:
```
ubuntu login: _
```

**Type your username** (usually `ubuntu` if you chose that during install):
```
ubuntu
```

**Press Enter, then type your password** (the one you set during Ubuntu installation):
```
Password: [your password here]
```

**Press Enter.**

Now you're at the Ubuntu command prompt:
```
ubuntu@openclaw-gateway:~$ _
```

**Get your IP address:**
```bash
hostname -I
```

**Expected output:**
```
192.168.1.101
```

**Save this IP address.** (or write it down - you'll need it next)

---

## Step 2: SSH from Your Host Machine (2 minutes)

Now you can SSH from your **host machine** (Windows, Mac, or Linux) instead of using the console.

### On Your Host Machine

#### **Windows PowerShell:**
```powershell
# Replace 192.168.1.101 with your actual VM IP
ssh ubuntu@192.168.1.101
```

#### **macOS/Linux Terminal:**
```bash
ssh ubuntu@192.168.1.101
```

**When prompted:**
```
The authenticity of host '192.168.1.101 (192.168.1.101)' can't be established.
ECDSA key fingerprint is SHA256:xxxxx
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Type:** `yes` and press **Enter**

**When prompted for password:**
```
ubuntu@192.168.1.101's password: _
```

**Type your Ubuntu password and press Enter.**

---

## ✅ Step 3: Verify You're Connected

If successful, you should see:
```
ubuntu@openclaw-gateway:~$ 
```

**This means you're now inside the Ubuntu VM via SSH!**

Verify the connection:
```bash
# Check you're in the VM (not your host):
hostname
# Output: openclaw-gateway (or whatever you named it)

# Check IP again:
hostname -I
# Output: 192.168.1.101 (your VM IP)

# Check internet:
ping 8.8.8.8
# Should get pong responses (Ctrl+C to stop)
```

---

## ⚡ Step 4: Download Installation Scripts

```bash
# Download the OpenClaw installation package:
git clone https://github.com/sumkh/OpenClaw_Installation.git
cd OpenClaw_Installation

# List scripts:
ls -la *.sh

# Make scripts executable:
sudo chmod +x *.sh
```

---

## 🚀 Step 5: Start Installation

```bash
# Run the first script:
sudo ./01-initial-setup.sh

# Follow prompts - takes about 5-10 minutes
```

---

## 🛠️ Troubleshooting First Boot

### Problem: "command not found" when trying `ipconfig`

**Root cause:** `ipconfig` is a Windows command, not Linux.

**Solution:** Use Linux commands instead:
```bash
# ✓ Correct:
hostname -I
ip addr show
hostname

# ✗ Wrong (these are Windows):
ipconfig
netstat -an
tasklist
```

### Problem: Can't SSH to VM

**Troubleshooting steps:**

1. **Verify IP is correct:**
   ```bash
   # On VM console:
   hostname -I
   # Double-check you're using this IP in SSH command
   ```

2. **Check SSH service is running:**
   ```bash
   # On VM:
   sudo systemctl status ssh
   # Should show: active (running)
   
   # If not:
   sudo systemctl start ssh
   ```

3. **Check firewall:**
   ```bash
   # On VM:
   sudo ufw status
   # SSH should be allowed, or firewall inactive
   ```

4. **Try from VM console:**
   ```bash
   # On VM:
   ssh localhost
   # If this works, SSH is fine - issue is network or firewall
   ```

### Problem: "Permission denied" on SSH

**Solutions:**
```bash
# If using password authentication:
# Make sure you type the same password you set during Ubuntu install

# If using SSH keys:
# Check key permissions on host:
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

---

## 📋 First Boot Checklist

- [ ] VM boots to login prompt
- [ ] I can log in with my Ubuntu username/password
- [ ] I can get IP address with `hostname -I`
- [ ] SSH from host machine works (`ssh ubuntu@IP`)
- [ ] I see command prompt inside VM
- [ ] `ping 8.8.8.8` works (internet connected)
- [ ] I've downloaded installation scripts with git clone
- [ ] Scripts have execute permissions (`ls -la *.sh` shows `x`)

---

## What's Next

Once you complete the checklist above, you're ready for:

1. **Read:** [OPENCLAW-SECURE-DEPLOYMENT-GUIDE.md](OPENCLAW-SECURE-DEPLOYMENT-GUIDE.md)
2. **Run:** `sudo ./01-initial-setup.sh`
3. **Continue:** Follow the 5-step installation

---

## Quick Command Reference

```bash
# Get VM IP
hostname -I

# SSH to VM
ssh ubuntu@192.168.1.101

# Check you're in VM
hostname

# Check internet
ping 8.8.8.8

# Update packages
sudo apt update && sudo apt upgrade

# Check system specs
uname -r              # Kernel version
df -h                 # Disk space
free -h               # Memory
nproc                 # CPU count

# Exit SSH and return to host
exit
```

---

## Next Steps

1. ✅ Complete this first boot checklist
2. ✅ Verify SSH connection works
3. ✅ Download installation scripts
4. ⊘ Read [OPENCLAW-SECURE-DEPLOYMENT-GUIDE.md](OPENCLAW-SECURE-DEPLOYMENT-GUIDE.md)
5. ⊘ Run installation scripts (5 scripts, ~40 minutes total)

**You're ready to install OpenClaw!** 🎉

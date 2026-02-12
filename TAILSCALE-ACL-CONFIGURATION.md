# OpenClaw Tailscale ACL Configuration - Quick Reference

## Overview

This guide explains how to configure Tailscale ACLs to isolate OpenClaw from your other Tailscale devices while allowing necessary API access.

---

## Quick Start (3 Steps)

### Step 1: Get Tailscale API Token (1 minute)
```bash
# Visit: https://login.tailscale.com/admin/settings/personal
# Under "API Access Tokens" → Click "Generate API token..."
# Copy token (looks like: tskey-api-xxxxx)
```

### Step 2: Run Automated ACL Setup (1 minute)
```bash
# On OpenClaw VM or from your host machine:
sudo ./configure-tailscale-acl.sh --auto --api-token "tskey-api-xxxxx"
```

### Step 3: Verify ACL Applied (1 minute)
```bash
# Wait 30 seconds, then test on OpenClaw VM:
curl -I https://www.google.com          # Should work
timeout 5 nc -zv 100.64.x.1 22          # Should timeout (blocked)
```

✅ **Done!** OpenClaw now isolated from other Tailscale devices.

---

## What the ACL Does

### ✅ Allows
| Traffic | Source | Destination | Port | Purpose |
|---------|--------|-------------|------|---------|
| **API Access** | OpenClaw | Internet | 443 | Google APIs, WhatsApp |
| **DNS** | OpenClaw | Internet | 53 | Domain resolution |
| **Gateway Access** | Trusted devices | OpenClaw | 18789 | Access OpenClaw UI |
| **SSH (Admins)** | Admin users | OpenClaw | 22 | Server management |
| **Device-to-Device** | Trusted devices | Each other | * | Normal operation |

### ❌ Blocks
| Traffic | Source | Destination | Port | Reason |
|---------|--------|-------------|------|--------|
| **SSH** | OpenClaw | Other devices | 22 | Prevent lateral movement |
| **File Share** | OpenClaw | Other devices | 445, 139 | Prevent data access |
| **All Other** | OpenClaw | Tailscale devices | * | Default deny |

---

## Three Ways to Apply ACL

### Option 1: Automatic (Recommended)
**Pros:** Fast, no manual steps needed  
**Cons:** Requires API token

```bash
sudo ./configure-tailscale-acl.sh --auto --api-token "tskey-api-xxxxx"
```

### Option 2: Manual via Admin Console
**Pros:** No API token needed  
**Cons:** Manual steps, room for error

```bash
# 1. Get policy file
cat /opt/openclaw/tailscale/acl-policy.hujson

# 2. Copy the output

# 3. Visit https://login.tailscale.com/admin/acls

# 4. Paste into policy editor and save
```

### Option 3: Using Helper Script
**Pros:** Guided step-by-step  
**Cons:** Manual application required

```bash
sudo ./configure-tailscale-acl.sh  # Generates files in /opt/openclaw/tailscale/
# Then follow MANUAL_ACL_SETUP.md
```

---

## Verification Tests

### From OpenClaw VM (Should SUCCEED)
```bash
# Test 1: Reach Google APIs
curl -I https://www.google.com
# Expected: HTTP 200 or 403

# Test 2: Resolve DNS
nslookup google.com
# Expected: IP addresses returned

# Test 3: Check Tailscale connection
sudo tailscale status
# Expected: Shows your IP in 100.64.x.x range
```

### From OpenClaw VM (Should FAIL)
```bash
# Test 1: Cannot reach other Tailscale devices
timeout 5 nc -zv 100.64.x.1 22
# Expected: Connection timed out

# Test 2: Cannot reach file shares
timeout 5 nc -zv 100.64.x.2 445
# Expected: Connection timed out
```

### From Trusted Device (Should SUCCEED)
```bash
# Test 1: Can reach OpenClaw gateway
curl http://100.64.x.101:18789/health
# Expected: 200 OK or JSON response

# Test 2: Can ping OpenClaw
tailscale ping 100.64.x.101
# Expected: pong response

# Test 3: Can reach other trusted devices
tailscale ping 100.64.x.1
# Expected: pong response
```

---

## Troubleshooting

### Problem: "ACL policy not taking effect"
```bash
# 1. Wait 30 seconds after saving
# 2. Clear Tailscale cache:
sudo systemctl restart tailscaled

# 3. Check Tailscale admin console for errors:
# https://login.tailscale.com/admin/acls
```

### Problem: "Cannot reach Google APIs from OpenClaw"
```bash
# 1. Check Tailscale connection:
sudo tailscale status
# Should show: Online

# 2. Check if 443 is open locally:
sudo ufw status | grep 443

# 3. Test DNS resolution:
nslookup google.com

# 4. Try IP directly (if DNS not working):
curl -I https://8.8.8.8:443
```

### Problem: "Trusted device cannot reach OpenClaw gateway"
```bash
# 1. Verify OpenClaw VM is online:
sudo tailscale status

# 2. Check gateway is running:
sudo docker compose -f /opt/openclaw/docker-compose.yml ps

# 3. Verify firewall on OpenClaw allows 18789:
sudo ufw status | grep 18789

# 4. From trusted device, test with exact IP:
curl http://100.64.x.101:18789/health
```

### Problem: "API Token not working"
```bash
# 1. Verify token format (should start with "tskey-api-"):
echo "$API_TOKEN" | head -c 15

# 2. Check token hasn't expired:
# https://login.tailscale.com/admin/settings/personal
# (regenerate if needed)

# 3. Try manual method instead:
sudo ./configure-tailscale-acl.sh  # (without --auto flag)
```

---

## Files Generated

After running ACL configuration script:

```
/opt/openclaw/tailscale/
├── acl-policy.hujson              # Actual ACL policy (generated)
├── MANUAL_ACL_SETUP.md            # Step-by-step manual setup guide
├── verify-acl-policy.sh           # Script to verify ACL is working
└── logs/
    └── tailscale-acl-*.log        # Setup logs with timestamps
```

---

## Reference: ACL Policy Structure

### Groups (Who)
```json
"groups": {
  "group:trusted": ["user@example.com", "admin@example.com"],
  "group:openclaw-admins": ["admin@example.com"]
}
```

### Tag Owners (Security Authority)
```json
"tagOwners": {
  "tag:openclaw": ["group:openclaw-admins"],
  "tag:trusted": ["group:openclaw-admins"]
}
```

### ACL Rules (What's Allowed)
```json
"acls": [
  {
    "action": "accept",              // Allow
    "src": ["group:trusted"],        // From trusted devices
    "dst": ["tag:openclaw:18789"],   // To OpenClaw port 18789
    "comment": "Description"
  },
  {
    "action": "drop",                // Block
    "src": ["tag:openclaw"],         // From OpenClaw
    "dst": ["tag:trusted:*"],        // To any trusted device
    "comment": "Security: Isolate OpenClaw"
  }
]
```

---

## Advanced: Customizing the ACL

### Allow OpenClaw to Reach Specific Service
```json
{
  "action": "accept",
  "src": ["tag:openclaw"],
  "dst": ["tag:database:5432"],     // PostgreSQL
  "comment": "OpenClaw can query database"
}
```

### Restrict to Specific Admin User
```json
{
  "action": "accept",
  "src": ["user:admin@example.com"],
  "dst": ["tag:openclaw:22"],
  "comment": "Only this admin can SSH"
}
```

### Allow OpenClaw to Reach Specific External IP
```json
{
  "action": "accept",
  "src": ["tag:openclaw"],
  "dst": ["api.whatsapp.com:443"],
  "comment": "WhatsApp API only"
}
```

---

## Security Best Practices

✅ **Do:**
- Review ACL policy before applying
- Test with verification script after applying
- Use separate admin group for OpenClaw management
- Monitor Tailscale admin console for policy violations
- Rotate API tokens every 3-6 months
- Enable 2FA on Tailscale account
- Document which APIs OpenClaw needs

❌ **Don't:**
- Allow OpenClaw to access other Tailscale devices
- Use overly permissive (*:*) rules for OpenClaw
- Leave SSH open to all users
- Disable ACL restrictions for convenience
- Share API tokens with unauthorized users
- Allow outbound on unknown ports

---

## Getting Help

### View Configuration Files
```bash
# View current ACL policy
cat /opt/openclaw/tailscale/acl-policy.hujson

# View setup logs
tail -f /var/log/openclaw-setup/tailscale-acl-*.log

# View Tailscale status
sudo tailscale status
```

### Run Verification
```bash
# Full ACL verification script
sudo /opt/openclaw/tailscale/verify-acl-policy.sh

# Manual verification
timeout 5 curl -I https://www.google.com
timeout 5 nc -zv 100.64.x.1 22
```

### Reference Documentation
- Tailscale ACL Docs: https://tailscale.com/kb/1018/acl/
- Tailscale API: https://tailscale.com/api
- OpenClaw Docs: `/opt/openclaw/docs/`

---

## Summary

| Step | Action | Time | Command |
|------|--------|------|---------|
| 1 | Get API token | 1 min | https://login.tailscale.com/admin/settings/personal |
| 2 | Run script | 1 min | `sudo ./configure-tailscale-acl.sh --auto --api-token "..."` |
| 3 | Test | 1 min | `curl -I https://www.google.com` |
| ✅ | Done! | ~3 min | OpenClaw is now isolated |

**Next:** Run `sudo ./04-post-install-security.sh` to complete security hardening.

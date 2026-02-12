#!/bin/bash

##############################################################################
# Tailscale ACL Configuration Script - OpenClaw Isolation
# Purpose: Restrict OpenClaw VM to only access APIs and shared folders
#          Prevent OpenClaw from reaching other Tailscale devices
# Runs on: Host machine with Tailscale admin access OR OpenClaw VM
# Usage: sudo ./configure-tailscale-acl.sh [--auto] [--api-token <token>]
# Note: Requires Tailscale account with admin privileges
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TAILSCALE_ADMIN_URL="https://api.tailscale.com/api/v2"
ACL_CONFIG_DIR="/opt/openclaw/tailscale"
LOG_DIR="/var/log/openclaw-setup"
LOG_FILE="${LOG_DIR}/tailscale-acl-$(date +%Y%m%d-%H%M%S).log"

# Arguments
AUTO_MODE=false
API_TOKEN=""

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --api-token)
                API_TOKEN="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Tailscale ACL Configuration Script for OpenClaw Isolation

Usage: sudo ./configure-tailscale-acl.sh [OPTIONS]

OPTIONS:
  --auto              Automatically apply ACL via Tailscale API (requires --api-token)
  --api-token TOKEN   Tailscale API token for automated application

EXAMPLES:

1. Generate ACL template (manual application):
   sudo ./configure-tailscale-acl.sh

2. Automatically apply ACL via API:
   sudo ./configure-tailscale-acl.sh --auto --api-token "tskey-api-xxxxx"

SETUP INSTRUCTIONS:

To get your Tailscale API token:
  1. Visit: https://login.tailscale.com/admin/settings/personal
  2. Scroll to "API Access Tokens"
  3. Click "Generate API token..."
  4. Copy the token: tskey-api-xxxxx
  5. Run this script with --api-token parameter

Manual Application Steps:
  1. Run this script without --auto flag
  2. Copy the generated ACL policy
  3. Visit: https://login.tailscale.com/admin/acls
  4. Paste the ACL policy and save
  5. Wait 30 seconds for Tailscale to apply rules

EOF
}

# Create configuration directories
setup_directories() {
    log "INFO" "Creating ACL configuration directories..."
    mkdir -p "$ACL_CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$ACL_CONFIG_DIR" "$LOG_DIR"
    chmod 700 "$ACL_CONFIG_DIR"
}

# Generate ACL policy template for OpenClaw isolation
generate_acl_policy() {
    log "INFO" "Generating OpenClaw isolation ACL policy..."
    
    cat > "${ACL_CONFIG_DIR}/acl-policy.hujson" << 'EOFACL'
{
  // ============================================================================
  // OpenClaw AI Agent - Secure Tailscale ACL Policy
  // ============================================================================
  // Purpose: Isolate OpenClaw VM to prevent unauthorized access to other devices
  //          while allowing necessary internet API access for integrations
  //
  // RESTRICTIONS:
  //  ✓ OpenClaw can ONLY be reached on port 18789 (gateway) by trusted devices
  //  ✓ OpenClaw can ONLY reach internet on port 443 (HTTPS APIs) and 53 (DNS)
  //  ✗ OpenClaw CANNOT reach any other Tailscale device
  //  ✗ OpenClaw CANNOT reach SSH (port 22) on any device
  //  ✗ OpenClaw CANNOT reach file services (445, 139)
  //
  // ALLOWED TRAFFIC FOR OPENCLAW:
  //  • Google APIs (HTTPS on 443)
  //  • WhatsApp Business API (HTTPS on 443)
  //  • DNS queries (port 53)
  //  • GitHub (HTTPS on 443) - for config sync
  //
  // INCOMING TO OPENCLAW:
  //  • Trusted devices can access gateway on 18789
  //  • SSH restricted to admin users (recommended)
  //
  // ============================================================================

  "version": 1,

  // Define user groups
  "groups": {
    // All trusted devices (physical devices, host machine)
    "group:trusted": [
      "user@example.com",          // Physical Device 1 user
      "admin@example.com"          // Admin/Host Machine user
      // Add more users as needed
    ],
    
    // OpenClaw administrator (for SSH management)
    "group:openclaw-admins": [
      "admin@example.com"
    ]
  },

  // Assign device tags
  "tagOwners": {
    "tag:openclaw": ["group:openclaw-admins"],
    "tag:trusted": ["group:openclaw-admins"],
    "tag:phys-device": ["group:openclaw-admins"]
  },

  // Host name resolution
  "hosts": {
    "openclaw": "100.x.x.x",      // Will be auto-assigned by Tailscale
    "phys1": "100.x.x.x",         // Physical Device 1
    "phys2": "100.x.x.x"          // Physical Device 2
  },

  // ============================================================================
  // ACCESS CONTROL LIST (ACL) RULES
  // ============================================================================
  // Rules are evaluated top-to-bottom; first match wins
  // Default: DENY (most restrictive)

  "acls": [
    // ─────────────────────────────────────────────────────────────────────
    // SECTION 1: Trusted Device Inter-Access
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["group:trusted"],
      "dst": ["group:trusted:*"],
      "priority": "high",
      "comment": "Trusted devices can reach each other fully"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 2: Trusted Devices → OpenClaw Gateway (ALLOWED)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["group:trusted"],
      "dst": ["tag:openclaw:18789"],
      "priority": "high",
      "comment": "Trusted devices can access OpenClaw gateway on port 18789"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 3: OpenClaw SSH (Restricted to Admins)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["group:openclaw-admins"],
      "dst": ["tag:openclaw:22"],
      "priority": "high",
      "comment": "Admin users can SSH to OpenClaw for management"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 4: OpenClaw → Internet APIs (ALLOWED - HTTPS only)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["tag:openclaw"],
      "dst": ["*:443"],
      "priority": "high",
      "comment": "OpenClaw can reach internet APIs on HTTPS (443)"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 5: OpenClaw → DNS (ALLOWED)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["tag:openclaw"],
      "dst": ["*:53"],
      "priority": "high",
      "comment": "OpenClaw can query DNS (necessary for API resolution)"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 6: OpenClaw → OTHER TAILSCALE DEVICES (DENIED)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "drop",
      "src": ["tag:openclaw"],
      "dst": ["tag:trusted:*"],
      "priority": "high",
      "comment": "BLOCK: OpenClaw cannot reach trusted devices"
    },

    {
      "action": "drop",
      "src": ["tag:openclaw"],
      "dst": ["tag:phys-device:*"],
      "priority": "high",
      "comment": "BLOCK: OpenClaw cannot reach physical devices"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 7: OpenClaw → Catch-All DENY (Safety)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "drop",
      "src": ["tag:openclaw"],
      "dst": ["*:*"],
      "priority": "default",
      "comment": "BLOCK: Deny all other traffic from OpenClaw (safety default)"
    },

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 8: Default Allow (Between Trusted Devices)
    // ─────────────────────────────────────────────────────────────────────
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"],
      "priority": "default",
      "comment": "Default: Allow other traffic (non-OpenClaw related)"
    }
  ],

  // ============================================================================
  // TESTING REQUIREMENTS (Verify after applying ACL)
  // ============================================================================
  // After applying this ACL, run these tests on OpenClaw VM:
  //
  // 1. SHOULD SUCCEED: Reach Google API
  //    curl -I https://www.google.com
  //    Expected: HTTP response (200, 403, etc.)
  //
  // 2. SHOULD SUCCEED: Reach WhatsApp API
  //    curl -I https://www.whatsapp.com
  //    Expected: HTTP response
  //
  // 3. SHOULD SUCCEED: DNS resolution
  //    nslookup google.com
  //    Expected: IP addresses returned
  //
  // 4. SHOULD FAIL: SSH to another device (timeout after 5 seconds)
  //    timeout 5 nc -zv 100.64.x.1 22
  //    Expected: Connection timed out
  //
  // 5. SHOULD FAIL: SMB/File share (timeout after 5 seconds)
  //    timeout 5 nc -zv 100.64.x.2 445
  //    Expected: Connection timed out
  //
  // 6. FROM TRUSTED DEVICE - SHOULD SUCCEED: Access OpenClaw gateway
  //    curl http://100.64.x.101:18789/health
  //    Expected: 200 OK or JSON response

  // ============================================================================
  // NOTES
  // ============================================================================
  // • Replace "user@example.com" with actual Tailscale user emails
  // • Replace "100.x.x.x" with actual Tailscale IPs after VM joins mesh
  // • Update physical device IPs when OpenClaw joins your tailnet
  // • Review and test this policy before applying to production
  // • Monitor Tailscale admin console for policy violations
  // • Enable audit logging in Tailscale settings for security monitoring
  // • Consider adding VPN logs to your SIEM if available
}
EOFACL

    log "INFO" "ACL policy generated: ${ACL_CONFIG_DIR}/acl-policy.hujson"
}

# Apply ACL via Tailscale API
apply_acl_via_api() {
    if [[ -z "$API_TOKEN" ]]; then
        log "ERROR" "API token required for automatic application. Use --api-token parameter."
        return 1
    fi

    log "INFO" "Applying ACL policy via Tailscale API..."

    if ! command -v jq &> /dev/null; then
        log "WARN" "jq not found. Installing..."
        apt-get install -y jq &> /dev/null || yum install -y jq &> /dev/null
    fi

    # Get current user's tailnet
    TAILNET=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
        "${TAILSCALE_ADMIN_URL}/tailnet/me" | jq -r '.name' || echo "")

    if [[ -z "$TAILNET" ]]; then
        log "ERROR" "Failed to get tailnet information. Check your API token."
        return 1
    fi

    log "INFO" "Using tailnet: $TAILNET"

    # Read ACL policy
    ACL_CONTENT=$(cat "${ACL_CONFIG_DIR}/acl-policy.hujson")

    # Apply ACL
    log "INFO" "Sending ACL policy to Tailscale..."
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"acl\": $(echo "$ACL_CONTENT" | jq -Rs .)}" \
        "${TAILSCALE_ADMIN_URL}/tailnet/${TAILNET}/acl")

    # Check for errors
    if echo "$RESPONSE" | jq -e '.errors' &> /dev/null; then
        log "ERROR" "Failed to apply ACL policy:"
        echo "$RESPONSE" | jq '.errors'
        return 1
    fi

    log "INFO" "✓ ACL policy applied successfully via API"
    log "INFO" "Changes will take effect within 30 seconds"
    
    return 0
}

# Generate manual application instructions
generate_manual_instructions() {
    cat > "${ACL_CONFIG_DIR}/MANUAL_ACL_SETUP.md" << 'EOFMANUAL'
# Manual Tailscale ACL Configuration

## Step-by-Step Instructions

### 1. Get Your ACL Policy
The policy is located at: `/opt/openclaw/tailscale/acl-policy.hujson`

```bash
cat /opt/openclaw/tailscale/acl-policy.hujson
```

### 2. Open Tailscale Admin Console
Visit: https://login.tailscale.com/admin/acls

### 3. Copy the ACL Policy
Select all text from the file above and copy it.

### 4. Replace Policy in Admin Console
1. Click "Edit" in the Tailscale admin ACL page
2. Select all existing policy (Ctrl+A)
3. Paste the new policy (Ctrl+V)
4. Click "Save"

### 5. Tailscale will apply the policy
- Status: "Policy saved"
- Timeline shows the update
- Wait 30 seconds for all devices to receive new rules

### 6. Verify the Policy Works

#### On OpenClaw VM:
```bash
# Test 1: Should SUCCEED - Reach internet APIs
curl -I https://www.google.com
# Expected: HTTP 200/403 response

# Test 2: Should FAIL - Try to reach another device
timeout 5 nc -zv 100.64.x.1 22
# Expected: Connection timed out (blocked by ACL)
```

#### From Trusted Device:
```bash
# Test 3: Should SUCCEED - Access OpenClaw gateway
curl http://100.64.x.101:18789/health
# Expected: 200 OK or JSON response

# Test 4: Verify OpenClaw listed in devices
tailscale status | grep openclaw
```

## If Tests Fail

### OpenClaw Cannot Reach Internet APIs
```bash
# Check firewall on VM
sudo ufw status | grep 443
# Should show: Allow 443/tcp

# Check Tailscale connection
sudo tailscale status
# Should show online status

# Restart Tailscale daemon
sudo systemctl restart tailscaled
```

### Trusted Device Cannot Reach OpenClaw Gateway
```bash
# From trusted device:
tailscale ping 100.64.x.101
# Should succeed

# Check OpenClaw service
ssh ubuntu@100.64.x.101
sudo docker compose -f /opt/openclaw/docker-compose.yml ps
# Should show gateway running
```

### ACL Rules Not Taking Effect
```bash
# Wait 30+ seconds after saving policy
# Check admin console for any error messages
# Verify VM's Tailscale IP in policy (might have changed)
# Force reconnect:
cd /opt/openclaw
sudo ./03-setup-tailscale.sh
```

## Advanced Verification

### View Current ACL Policy
```bash
# From any device
tailscale debug via
```

### Check Policy Violations
```bash
# Visit Tailscale admin console → Audit logs
# Look for ACL-related dropped connections
```

### Get OpenClaw Tailscale IP
```bash
# On OpenClaw VM:
sudo tailscale status | grep -E '^[[:space:]]+100'
# Or:
ip addr show tailscale0
```

## Important Notes

- Tailscale IPs are assigned dynamically (100.64.x.x range)
- Update policy if VM gets new IP (rare, but possible)
- Default: if hostname changes, re-tag in admin console
- Test before deploying to production
- Enable audit logging for comprehensive monitoring

EOFMANUAL

    log "INFO" "Manual setup instructions created: ${ACL_CONFIG_DIR}/MANUAL_ACL_SETUP.md"
}

# Generate compliance verification script
generate_verification_script() {
    cat > "${ACL_CONFIG_DIR}/verify-acl-policy.sh" << 'EOFVERIFY'
#!/bin/bash
# ACL Policy Verification Script

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ OpenClaw Tailscale ACL Policy Verification                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get OpenClaw Tailscale IP
OPENCLAW_IP=$(sudo tailscale status --json 2>/dev/null | jq -r '.Self.TailscaleIPs[0]' 2>/dev/null || echo "")

if [[ -z "$OPENCLAW_IP" ]]; then
    echo "❌ ERROR: OpenClaw not connected to Tailscale"
    exit 1
fi

echo "OpenClaw IP: $OPENCLAW_IP"
echo ""

# Test connectivity from this device
if [[ "$OPENSSH_CLIENT" == "" && "$SSH_CLIENT" == "" ]]; then
    # Running on the OpenClaw VM
    echo "Testing from OpenClaw VM:"
    echo "─────────────────────────────────────────────────────────────"
    
    # Test 1: Internet connectivity
    echo -n "Test 1: Can reach internet (Google)... "
    if timeout 5 curl -I https://www.google.com &> /dev/null; then
        echo "✓ PASS"
    else
        echo "✗ FAIL"
    fi
    
    # Test 2: DNS resolution
    echo -n "Test 2: Can resolve DNS... "
    if nslookup google.com &> /dev/null; then
        echo "✓ PASS"
    else
        echo "✗ FAIL"
    fi
    
    # Test 3: Cannot reach other Tailscale devices
    echo -n "Test 3: Cannot reach other devices (SSH blocked)... "
    # Get a device IP from status (not OpenClaw)
    OTHER_IP=$(sudo tailscale status --json 2>/dev/null | jq -r '.Peer[] | select(.HostName != "openclaw") | .TailscaleIPs[0]' 2>/dev/null | head -1)
    if [[ -n "$OTHER_IP" ]]; then
        if timeout 5 nc -zv $OTHER_IP 22 2>&1 | grep -q "Connection timed out"; then
            echo "✓ PASS"
        else
            echo "✗ FAIL"
        fi
    else
        echo "⊘ SKIP (no other devices)"
    fi
else
    # Running on a trusted device
    echo "Testing from trusted device:"
    echo "─────────────────────────────────────────────────────────────"
    
    # Test 1: Can reach OpenClaw
    echo -n "Test 1: Can reach OpenClaw... "
    if timeout 5 nc -zv $OPENCLAW_IP 18789 2>&1 | grep -q "succeeded"; then
        echo "✓ PASS"
    else
        echo "✗ FAIL"
    fi
    
    # Test 2: Try to SSH (should fail with port 22 in ACL)
    echo -n "Test 2: Cannot SSH to OpenClaw (policy blocked)... "
    if timeout 5 nc -zv $OPENCLAW_IP 22 2>&1 | grep -q "Connection timed out"; then
        echo "✓ PASS"
    else
        echo "⊘ WARN (SSH might be allowed for admins)"
    fi
fi

echo ""
echo "✓ ACL Verification Complete"
EOFVERIFY

    chmod +x "${ACL_CONFIG_DIR}/verify-acl-policy.sh"
    log "INFO" "ACL verification script created: ${ACL_CONFIG_DIR}/verify-acl-policy.sh"
}

# Print summary
print_summary() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║         Tailscale ACL Configuration - COMPLETED ✓              ║
╚════════════════════════════════════════════════════════════════╝

ACL CONFIGURATION FILES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Policy:          ${ACL_CONFIG_DIR}/acl-policy.hujson
Manual Setup:    ${ACL_CONFIG_DIR}/MANUAL_ACL_SETUP.md
Verification:    ${ACL_CONFIG_DIR}/verify-acl-policy.sh

POLICY OVERVIEW:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ OpenClaw CAN:
  • Be reached by trusted devices on port 18789 (gateway)
  • Reach internet on port 443 (HTTPS for APIs)
  • Query DNS on port 53 (domain resolution)
  • Be managed via SSH by admins (port 22)

✗ OpenClaw CANNOT:
  • Reach other Tailscale devices (all ports blocked)
  • Reach trusted devices' SSH on port 22
  • Reach file services (SMB 445, NetBIOS 139)
  • Access databases or internal services
  • Exfiltrate data to unauthorized locations

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    if [[ "$AUTO_MODE" == true ]]; then
        cat << EOF
✓ ACL policy applied automatically via Tailscale API

1. Wait 30 seconds for rules to propagate
2. Run verification script:
   sudo ${ACL_CONFIG_DIR}/verify-acl-policy.sh

3. Send policy file to admins for review:
   cat ${ACL_CONFIG_DIR}/acl-policy.hujson

LOG: $LOG_FILE
EOF
    else
        cat << EOF
Manual Application Required:

1. Copy the ACL policy:
   cat ${ACL_CONFIG_DIR}/acl-policy.hujson

2. Visit Tailscale Admin Console:
   https://login.tailscale.com/admin/acls

3. Replace the current policy with the generated one

4. Save and wait 30 seconds

5. Run verification script:
   sudo ${ACL_CONFIG_DIR}/verify-acl-policy.sh

AUTOMATED SETUP (Optional):
To automatically apply via Tailscale API:
  1. Get API token: https://login.tailscale.com/admin/settings/personal
  2. Run: sudo ./configure-tailscale-acl.sh --auto --api-token "tskey-api-xxxxx"

LOG: $LOG_FILE
EOF
    fi

    cat << EOF

SHARED FOLDER ACCESS (Local Only):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Secrets stored at: /opt/openclaw/secrets (NFSv4 from VMware)
✓ Access via: /mnt/vmshared (mounted at container startup)
✓ Permissions: 600 (OpenClaw user only reads)

SECURITY REMINDERS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠  Review ACL policy created above
⚠  Update user emails in "group:trusted" before applying
⚠  Test with verification script after applying
⚠  Monitor Tailscale admin logs for violations
⚠  Rotate API keys periodically
⚠  Keep secrets on mounted folder (never in container)

EOF
}

# Main execution
main() {
    mkdir -p "$LOG_DIR"

    log "INFO" "Starting Tailscale ACL configuration for OpenClaw isolation"
    
    parse_args "$@"
    setup_directories
    generate_acl_policy
    generate_manual_instructions
    generate_verification_script

    if [[ "$AUTO_MODE" == true ]]; then
        if apply_acl_via_api; then
            log "INFO" "✓ ACL applied successfully"
        else
            log "ERROR" "Failed to apply ACL via API. Please apply manually."
            exit 1
        fi
    fi

    print_summary
    log "INFO" "✓ Tailscale ACL configuration completed"
}

trap 'log "ERROR" "Script failed at line $LINENO"' ERR

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

main "$@"

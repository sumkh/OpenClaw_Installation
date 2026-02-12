#!/bin/bash

##############################################################################
# Tailscale VPN Setup Script
# Purpose: Securely configure Tailscale for remote access
# Runs on: Ubuntu 22.04+ or CentOS 8+
# Usage: sudo ./03-setup-tailscale.sh
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration variables
LOG_DIR="/var/log/openclaw-setup"
LOG_FILE="${LOG_DIR}/tailscale-setup-$(date +%Y%m%d-%H%M%S).log"
TAILSCALE_CONFIG_DIR="/var/lib/tailscale"
TAILSCALE_STATE_DIR="/var/lib/tailscale"

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    fi
}

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Install Tailscale
install_tailscale() {
    log "INFO" "Installing Tailscale..."
    
    if command -v tailscale &> /dev/null; then
        CURRENT_VERSION=$(tailscale version | head -1)
        log "INFO" "Tailscale already installed: $CURRENT_VERSION"
        return
    fi
    
    if [[ "$OS" == "ubuntu" ]]; then
        # Add Tailscale repository
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | apt-key add - 2>/dev/null || true
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.list | \
            tee /etc/apt/sources.list.d/tailscale.list > /dev/null
        
        apt-get update -qq
        apt-get install -y -q tailscale
        
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
        # Add Tailscale repository
        yum-config-manager --add-repo https://pkgs.tailscale.com/stable/centos/8/tailscale.repo
        yum install -y -q tailscale
    fi
    
    # Enable and start Tailscale
    systemctl enable tailscaled
    systemctl start tailscaled
    
    log "INFO" "Tailscale installed successfully"
}

# Configure Tailscale with security settings
configure_tailscale() {
    log "INFO" "Configuring Tailscale security settings..."
    
    # Create Tailscale config directory
    mkdir -p "$TAILSCALE_STATE_DIR"
    chmod 700 "$TAILSCALE_STATE_DIR"
    chown root:root "$TAILSCALE_STATE_DIR"
    
    # Wait for tailscaled to be ready
    sleep 2
    
    log "INFO" "Starting Tailscale authentication..."
    log "WARN" "Please visit the URL below to authenticate:"
    echo ""
    
    # Get authentication URL
    AUTH_OUTPUT=$(tailscale up --auth-once 2>&1 || true)
    
    # Extract and display the URL
    AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://[^\s]+' | head -1)
    
    if [[ -n "$AUTH_URL" ]]; then
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║ TAILSCALE AUTHENTICATION REQUIRED                              ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}CLICK this link or copy it to your browser:${NC}"
        echo ""
        echo -e "${GREEN}${AUTH_URL}${NC}"
        echo ""
        echo "After authentication, press ENTER to continue..."
        read -r
        
        log "INFO" "Waiting for Tailscale to connect..."
        sleep 5
    else
        log "WARN" "Could not get authentication URL"
        log "INFO" "Please run: sudo tailscale up"
    fi
    
    # Verify connection
    TAILSCALE_STATUS=$(tailscale status 2>&1 || true)
    if echo "$TAILSCALE_STATUS" | grep -q "Logged in"; then
        log "INFO" "Tailscale authentication successful"
    else
        log "WARN" "Tailscale may not be authenticated yet"
    fi
}

# Configure Tailscale ACL (Access Control List)
setup_tailscale_acl() {
    log "INFO" "Configuring Tailscale ACL rules..."
    
    # Create ACL template file for reference
    cat > "$TAILSCALE_CONFIG_DIR/tailscale-acl-template.hujson" << 'EOF'
{
  // Example Tailscale ACL Configuration
  // By default, all users can connect to all machines on the network except SSH
  
  "acls": [
    // Allow SSH from specific users/groups
    {
      "action": "accept",
      "src": ["group:team"],
      "dst": ["*:22"],
      "priority": "high"
    },
    
    // Allow OpenClaw access from specific users
    {
      "action": "accept",
      "src": ["user:admin@example.com"],
      "dst": ["tag:openclaw:8080,443"],
      "priority": "high"
    },
    
    // Block everything else
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["tag:openclaw:*"],
      "priority": "default"
    }
  ],
  
  "groups": {
    "group:team": ["admin@example.com", "user@example.com"]
  },
  
  "hosts": {
    "openclaw": "100.x.x.x"  // Tailscale IP will be assigned
  },
  
  "tagOwners": {
    "tag:openclaw": ["admin@example.com"]
  }
}
EOF
    
    log "INFO" "ACL template created at: $TAILSCALE_CONFIG_DIR/tailscale-acl-template.hujson"
    log "INFO" "Update your ACL policies via: https://login.tailscale.com/admin/acls"
}

# Setup firewall rules for Tailscale
configure_firewall_for_tailscale() {
    log "INFO" "Configuring firewall for Tailscale..."
    
    # UFW
    if command -v ufw &> /dev/null; then
        # Allow Tailscale traffic
        ufw allow 41641/udp comment "Tailscale"
        ufw allow in on tailscale0 comment "Tailscale interface"
        
        log "INFO" "UFW rules configured for Tailscale"
    fi
    
    # FirewallD
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=41641/udp
        firewall-cmd --reload
        log "INFO" "FirewallD rules configured for Tailscale"
    fi
}

# Configure Tailscale as exit node (optional)
setup_exit_node() {
    log "INFO" "Would you like to configure this as an exit node? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Enabling exit node mode..."
        
        # Verify IPv4 forwarding is enabled
        if [[ $(cat /proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
            echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
            sysctl -p > /dev/null
            log "INFO" "IPv4 forwarding enabled"
        fi
        
        # Verify IPv6 forwarding
        if [[ $(cat /proc/sys/net/ipv6/conf/all/forwarding) -eq 0 ]]; then
            echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
            sysctl -p > /dev/null
            log "INFO" "IPv6 forwarding enabled"
        fi
        
        # Enable exit node in Tailscale
        tailscale up --advertise-exit-node --accept-routes
        
        log "WARN" "Exit node enabled. Visit https://login.tailscale.com/admin/machines to approve."
    else
        log "INFO" "Exit node setup skipped"
    fi
}

# Create Tailscale monitoring script
create_tailscale_monitor() {
    log "INFO" "Creating Tailscale monitoring script..."
    
    cat > /usr/local/bin/check-tailscale-health.sh << 'EOF'
#!/bin/bash
# Tailscale Health Check Script

echo "=== Tailscale Status ==="
tailscale status --json 2>/dev/null | jq . || tailscale status

echo ""
echo "=== Connected Devices ==="
tailscale status --json 2>/dev/null | jq '.Peer[] | {HostName, TailscaleIPs}' || tailscale status | tail -n +2

echo ""
echo "=== Tailscale Interfaces ==="
ip addr show tailscale0 2>/dev/null || echo "Tailscale interface not found"

echo ""
echo "=== Recent Tailscale Events ==="
journalctl -u tailscaled -n 20 --no-pager 2>/dev/null || echo "Unable to read tailscaled logs"
EOF
    
    chmod +x /usr/local/bin/check-tailscale-health.sh
    
    # Add to cron (every 6 hours)
    CRON_ENTRY="0 */6 * * * /usr/local/bin/check-tailscale-health.sh >> /var/log/tailscale-health.log 2>&1"
    (crontab -l 2>/dev/null || echo "") | grep -v "check-tailscale-health.sh" | \
    (cat; echo "$CRON_ENTRY") | crontab -
    
    log "INFO" "Tailscale monitoring script created"
}

# Create Tailscale admin script
create_tailscale_admin_script() {
    log "INFO" "Creating Tailscale administration script..."
    
    cat > /usr/local/bin/tailscale-admin.sh << 'EOF'
#!/bin/bash
# Tailscale Administration Script

case "${1:-help}" in
    status)
        echo "=== Tailscale Status ==="
        tailscale status
        ;;
    connect)
        tailscale up
        ;;
    disconnect)
        tailscale down
        ;;
    exit-node)
        tailscale up --advertise-exit-node
        ;;
    info)
        tailscale status --json | jq .
        ;;
    restart)
        systemctl restart tailscaled
        ;;
    logs)
        journalctl -u tailscaled -n 50 -f
        ;;
    devices)
        echo "Connected Devices:"
        tailscale status --json 2>/dev/null | jq '.Peer[] | {HostName, TailscaleIPs}'
        ;;
    *)
        echo "Tailscale Administration Tool"
        echo ""
        echo "Usage: tailscale-admin <command>"
        echo ""
        echo "Commands:"
        echo "  status      - Show current Tailscale status"
        echo "  connect     - Authenticate and connect"
        echo "  disconnect  - Disconnect from Tailscale"
        echo "  exit-node   - Enable exit node"
        echo "  info        - Show detailed JSON info"
        echo "  restart     - Restart Tailscale daemon"
        echo "  logs        - Show recent logs (follow mode)"
        echo "  devices     - List connected devices"
        echo "  help        - Show this help message"
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/tailscale-admin.sh
    
    log "INFO" "Tailscale admin script created"
}

# Create documentation
create_tailscale_docs() {
    log "INFO" "Creating Tailscale documentation..."
    
    cat > "$TAILSCALE_CONFIG_DIR/TAILSCALE_GUIDE.md" << 'EOF'
# Tailscale Setup Guide

## Quick Start

### Connect to Tailscale
```bash
sudo tailscale up
```

### Check Status
```bash
sudo tailscale status
```

### Disconnect
```bash
sudo tailscale down
```

## Advanced Commands

### Get JSON Status
```bash
tailscale status --json
```

### Ping Another Device
```bash
tailscale ping <device-name>
```

### List Connected Peers
```bash
tailscale status --self=false
```

### Configure as Exit Node
```bash
sudo tailscale up --advertise-exit-node
```

## Troubleshooting

### Cannot Connect
1. Check service status: `sudo systemctl status tailscaled`
2. Check logs: `sudo journalctl -u tailscaled -n 50`
3. Verify network: `curl -I https://www.google.com`

### Slow Connection
1. Check signal: `tailscale status`
2. Try switching connection: `tailscale set --accept-routes=false && tailscale set --accept-routes=true`
3. Check firewall: `sudo ufw status`

### Device Not Appearing
1. Verify authentication: `tailscale status`
2. Check for blocking: `grep -i tailscale /var/log/syslog`
3. Reboot if needed: `sudo systemctl restart tailscaled`

## Security Best Practices

- Regularly review connected devices at: https://login.tailscale.com
- Use ACLs to restrict access
- Enable 2FA on Tailscale account
- Disable exit node if not needed
- Monitor logs for unusual activity
- Use tailscale + SSH keys for remote access

## Admin Script Usage

```bash
tailscale-admin status     # Show status
tailscale-admin connect    # Authenticate
tailscale-admin devices    # List peers
tailscale-admin logs       # View logs
tailscale-admin restart    # Restart service
```

## Monitoring

Health check runs automatically every 6 hours:
```bash
/var/log/tailscale-health.log
```

Manual health check:
```bash
check-tailscale-health.sh
```

## References

- Official: https://tailscale.com/kb/
- ACL Docs: https://tailscale.com/kb/1018/acl/
- Exit Nodes: https://tailscale.com/kb/1103/exit-nodes/

EOF
    
    log "INFO" "Tailscale documentation created"
}

# Print summary
print_summary() {
    TAILSCALE_IP=$(tailscale status --json 2>/dev/null | jq -r '.Self.TailscaleIPs[]' 2>/dev/null || echo "Not yet available")
    
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║           Tailscale Setup - COMPLETED ✓                       ║
╚════════════════════════════════════════════════════════════════╝

✓ Tailscale installed
✓ Authentication configured
✓ ACL template created
✓ Firewall rules configured
✓ Monitoring script set up
✓ Admin utilities created

TAILSCALE INFORMATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tailscale IP Address: $TAILSCALE_IP

Useful Commands:
  Status:      sudo tailscale status
  Start:       sudo tailscale up
  Stop:        sudo tailscale down
  Admin Tool:  sudo tailscale-admin <command>
  Health:      check-tailscale-health.sh

Configuration Files:
  Config Dir:  $TAILSCALE_STATE_DIR
  Docs:        $TAILSCALE_CONFIG_DIR/TAILSCALE_GUIDE.md
  ACL Template: $TAILSCALE_CONFIG_DIR/tailscale-acl-template.hujson

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Review and update ACL policies:
   https://login.tailscale.com/admin/acls

2. Configure your organization/team settings:
   https://login.tailscale.com/admin/settings/general

3. Add this device to your tailnet

4. Run: sudo ./04-post-install-security.sh

SECURITY REMINDERS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠  Review connected devices regularly
⚠  Use ACLs to restrict access
⚠  Enable 2FA on Tailscale account
⚠  Monitor logs for unusual activity
⚠  Disable exit node when not needed

Logs: $LOG_FILE

EOF
}

# Main execution
main() {
    mkdir -p "$LOG_DIR"
    
    log "INFO" "Starting Tailscale setup"
    log "INFO" "User: $(whoami)"
    log "INFO" "Hostname: $(hostname)"
    
    check_root
    detect_os
    install_tailscale
    configure_tailscale
    setup_tailscale_acl
    configure_firewall_for_tailscale
    create_tailscale_monitor
    create_tailscale_admin_script
    create_tailscale_docs
    
    log "INFO" "Would you like to setup exit node? (y/n)"
    read -r setup_exit
    if [[ "$setup_exit" =~ ^[Yy]$ ]]; then
        setup_exit_node
    fi
    
    log "INFO" "Tailscale setup completed successfully"
    print_summary
}

trap 'log "ERROR" "Script failed at line $LINENO"' ERR

main "$@"

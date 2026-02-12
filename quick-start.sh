#!/bin/bash

##############################################################################
# OpenClaw Secure Installation - Quick Start Script
# Purpose: Automated installation with user prompts
# Runs on: Ubuntu 22.04+ or CentOS 8+
# Usage: sudo ./quick-start.sh
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/openclaw-setup"

# Welcome screen
show_welcome() {
    clear
    cat << 'EOF'

    
   ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ██╗    ██╗
   ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██║    ██║
   ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║ █╗ ██║
   ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║███╗██║
   ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚███╔███╔╝
    ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ 
                                                                          
    Secure Installation & Deployment System
    ──────────────────────────────────────────────────────────────────

EOF
    
    echo -e "${CYAN}Welcome to OpenClaw Secure Installation!${NC}"
    echo ""
    echo "This script will guide you through a complete secure installation of"
    echo "OpenClaw with Tailscale VPN access on your VMware virtual machine."
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  ✓ Fresh Ubuntu 22.04+ or CentOS 8+ installation"
    echo "  ✓ 4+ vCPUs, 8GB+ RAM, 50GB+ storage"
    echo "  ✓ Internet connectivity"
    echo "  ✓ Root or sudo access"
    echo "  ✓ Tailscale account (free or paid)"
    echo ""
}

# Check system requirements
check_requirements() {
    echo -e "${BLUE}Checking system requirements...${NC}"
    echo ""
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}✗ This script must be run as root${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Running as root${NC}"
    fi
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        echo -e "${GREEN}✓ OS: ${PRETTY_NAME}${NC}"
    else
        echo -e "${RED}✗ Cannot detect OS${NC}"
        exit 1
    fi
    
    # Check CPU cores
    CORES=$(nproc)
    if [[ $CORES -ge 2 ]]; then
        echo -e "${GREEN}✓ CPU Cores: $CORES${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Only $CORES cores detected (4+ recommended)${NC}"
    fi
    
    # Check RAM
    RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $RAM_GB -ge 4 ]]; then
        echo -e "${GREEN}✓ RAM: ${RAM_GB}GB${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Only ${RAM_GB}GB RAM (8GB+ recommended)${NC}"
    fi
    
    # Check disk space
    DISK_GB=$(df / | awk 'NR==2 {print $4/1024/1024}' | cut -d. -f1)
    if [[ $DISK_GB -ge 50 ]]; then
        echo -e "${GREEN}✓ Disk Space: ${DISK_GB}GB available${NC}"
    else
        echo -e "${RED}✗ Insufficient disk space (${DISK_GB}GB available, 50GB+ needed)${NC}"
        exit 1
    fi
    
    # Check internet
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}✓ Internet connectivity${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Cannot reach internet (ping 8.8.8.8 failed)${NC}"
    fi
    
    echo ""
}

# Confirm proceeding
confirm_install() {
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}IMPORTANT: This script will modify your system${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This installation will:"
    echo "  • Harden SSH and firewall settings"
    echo "  • Install Docker and OpenClaw"
    echo "  • Configure Tailscale VPN"
    echo "  • Apply security policies"
    echo "  • Setup automated backups and monitoring"
    echo ""
    echo -e "${CYAN}Make sure you have:${NC}"
    echo "  ✓ Made a snapshot/backup of the VM"
    echo "  ✓ Reviewed the README.md file"
    echo "  ✓ Prepared your Tailscale account credentials"
    echo ""
    
    read -p "Do you want to proceed with installation? (yes/no): " response
    
    if [[ ! "$response" == "yes" ]]; then
        echo -e "${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
}

# Create log directory
setup_logs() {
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}✓ Log directory created: $LOG_DIR${NC}"
}

# Check script files
check_scripts() {
    echo ""
    echo -e "${BLUE}Checking required scripts...${NC}"
    
    local scripts=(
        "01-initial-setup.sh"
        "02-install-openclaw.sh"
        "03-setup-tailscale.sh"
        "04-post-install-security.sh"
        "05-maintenance.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            echo -e "${GREEN}✓ Found: $script${NC}"
        else
            echo -e "${RED}✗ Missing: $script${NC}"
            exit 1
        fi
    done
}

# Make scripts executable
make_scripts_executable() {
    echo ""
    echo -e "${BLUE}Making scripts executable...${NC}"
    chmod +x "$SCRIPT_DIR"/*.sh
    echo -e "${GREEN}✓ All scripts made executable${NC}"
}

# Run installation stages
run_stage_1() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ STAGE 1: Initial System Hardening                              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This stage will:"
    echo "  • Update system packages"
    echo "  • Harden SSH configuration"
    echo "  • Configure firewall"
    echo "  • Setup Fail2Ban for brute-force protection"
    echo "  • Enable automatic security updates"
    echo ""
    
    read -p "Ready to start Stage 1? (yes/no): " response
    
    if [[ "$response" == "yes" ]]; then
        "$SCRIPT_DIR/01-initial-setup.sh"
    else
        echo -e "${YELLOW}Stage 1 skipped${NC}"
        return 1
    fi
}

run_stage_2() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ STAGE 2: OpenClaw Installation                                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This stage will:"
    echo "  • Install Docker and Docker Compose"
    echo "  • Install OpenClaw application"
    echo "  • Configure systemd service"
    echo "  • Setup SSL certificates"
    echo "  • Configure backups"
    echo ""
    
    read -p "Ready to start Stage 2? (yes/no): " response
    
    if [[ "$response" == "yes" ]]; then
        "$SCRIPT_DIR/02-install-openclaw.sh"
    else
        echo -e "${YELLOW}Stage 2 skipped${NC}"
        return 1
    fi
}

run_stage_3() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ STAGE 3: Tailscale VPN Configuration                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This stage will:"
    echo "  • Install Tailscale VPN client"
    echo "  • Guide you through authentication"
    echo "  • Configure firewall rules"
    echo "  • Setup monitoring scripts"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Have your Tailscale account ready!${NC}"
    echo ""
    
    read -p "Ready to start Stage 3? (yes/no): " response
    
    if [[ "$response" == "yes" ]]; then
        "$SCRIPT_DIR/03-setup-tailscale.sh"
    else
        echo -e "${YELLOW}Stage 3 skipped${NC}"
        return 1
    fi
}

run_stage_4() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ STAGE 4: Post-Installation Security Hardening                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This stage will:"
    echo "  • Apply AppArmor/SELinux policies"
    echo "  • Harden SSL/TLS configuration"
    echo "  • Setup intrusion detection (AIDE)"
    echo "  • Configure security monitoring"
    echo "  • Setup container security"
    echo ""
    
    read -p "Ready to start Stage 4? (yes/no): " response
    
    if [[ "$response" == "yes" ]]; then
        "$SCRIPT_DIR/04-post-install-security.sh"
    else
        echo -e "${YELLOW}Stage 4 skipped${NC}"
        return 1
    fi
}

# Final summary
show_completion() {
    clear
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║     OpenClaw Secure Installation - COMPLETE ✓                 ║
╚════════════════════════════════════════════════════════════════╝

Congratulations! Your OpenClaw installation is complete with
full security hardening and Tailscale VPN access.

QUICK REFERENCE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service Management:
  Status:    sudo systemctl status openclaw
  Start:     sudo systemctl start openclaw
  Stop:      sudo systemctl stop openclaw
  Restart:   sudo systemctl restart openclaw
  Logs:      sudo journalctl -u openclaw -f

VPN Access:
  Status:    sudo tailscale status
  Devices:   sudo tailscale status --json | jq '.Peer'

Maintenance:
  Health:    sudo ./05-maintenance.sh (select option 1)
  Backup:    sudo ./05-maintenance.sh (select option 5)
  Update:    sudo ./05-maintenance.sh (select option 4)

Documentation:
  Main:      README.md
  Tailscale: /var/lib/tailscale/TAILSCALE_GUIDE.md
  Security:  /var/log/security-checklist.md

LOGS & BACKUPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Setup Logs:       /var/log/openclaw-setup/
Application Logs: /var/log/openclaw/
Backups:          /var/backups/openclaw/

INITIAL VERIFICATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Run these commands to verify your installation:

1. Check OpenClaw:
   $ sudo systemctl status openclaw

2. Check Tailscale:
   $ sudo tailscale status

3. Check services via Tailscale IP:
   $ curl http://<tailscale-ip>:8080/health

4. View recent logs:
   $ sudo journalctl -u openclaw -n 20

5. Run health check:
   $ sudo ./05-maintenance.sh
   (Select option 1)

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Replace self-signed SSL with CA-signed certificates
2. Configure OpenClaw application settings
3. Setup database backups
4. Configure monitoring/alerting
5. Schedule security audits

SECURITY REMINDERS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠  SSH password auth is DISABLED - use SSH keys only
⚠  Firewall is ENABLED - restrict access via Tailscale
⚠  Automatic updates are ENABLED
⚠  Regular backups are CONFIGURED
⚠  Monitor logs regularly for anomalies
⚠  Review Tailscale connected devices at:
   https://login.tailscale.com/admin/machines

SUPPORT & DOCUMENTATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OpenClaw Documentation: [link]
Tailscale Documentation: https://tailscale.com/kb/
Ubuntu Security Guide: https://ubuntu.com/security
CentOS Security Guide: https://wiki.centos.org/HowTos/Security

TROUBLESHOOTING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Run maintenance script for diagnostics:
  $ sudo ./05-maintenance.sh

Common issues: Check README.md "Troubleshooting" section

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Installation completed on $(date)
Hostname: $(hostname)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')

Thank you for using OpenClaw Secure Installation!

EOF
}

# Main execution
main() {
    show_welcome
    echo -e "${YELLOW}Press ENTER to continue or Ctrl+C to cancel...${NC}"
    read -r
    
    check_requirements
    check_scripts
    make_scripts_executable
    setup_logs
    
    echo ""
    read -p "Press ENTER to review prerequisites and start installation...${NC}" -r
    
    confirm_install
    
    # Run stages
    run_stage_1 && echo "" && read -p "Stage 1 complete. Press ENTER to continue to Stage 2..." _
    run_stage_2 && echo "" && read -p "Stage 2 complete. Press ENTER to continue to Stage 3..." _
    run_stage_3 && echo "" && read -p "Stage 3 complete. Press ENTER to continue to Stage 4..." _
    run_stage_4
    
    show_completion
}

# Run main
main "$@"

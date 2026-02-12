#!/bin/bash

##############################################################################
# OpenClaw Maintenance & Support Script
# Purpose: Routine maintenance and diagnostic tasks
# Runs on: Ubuntu 22.04+ or CentOS 8+
# Usage: sudo ./05-maintenance.sh [task]
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
OPENCLAW_HOME="/opt/openclaw"
LOG_DIR="/var/log/openclaw-setup"
BACKUP_DIR="/var/backups/openclaw"

# Colors for output
print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo ""
    echo -e "${YELLOW}━━ $1 ━━${NC}"
}

# Check prerequisites
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Health check
health_check() {
    print_header "OpenClaw System Health Check"
    
    print_section "Service Status"
    systemctl status openclaw --no-pager | head -10
    
    print_section "Resource Usage"
    echo "CPU & Memory (Docker containers):"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Docker not available"
    
    print_section "Disk Space"
    df -h "$OPENCLAW_HOME" /var/log
    
    print_section "Network Status"
    echo "Listening Ports:"
    netstat -tlnp 2>/dev/null | grep -E ":(22|8080|443|41641)" || echo "Standard ports"
    
    print_section "Tailscale Status"
    sudo tailscale status --json 2>/dev/null | jq '{Self,Connected: (.Peer | length)}' || echo "Tailscale not connected"
    
    print_section "Recent Errors"
    echo "OpenClaw (last 5 errors):"
    journalctl -u openclaw -p err -n 5 --no-pager || echo "None"
}

# Status check
status_check() {
    print_header "System Status Check"
    
    echo "OpenClaw Service:"
    systemctl is-active openclaw && echo "✓ RUNNING" || echo "✗ STOPPED"
    
    echo ""
    echo "Tailscale Connection:"
    sudo tailscale status 2>/dev/null | head -3 || echo "✗ DISCONNECTED"
    
    echo ""
    echo "Docker Containers:"
    docker ps --filter "label=openclaw=true" --format "table {{.Names}}\t{{.Status}}"
    
    echo ""
    echo "Firewall Status:"
    if command -v ufw &>/dev/null; then
        ufw status | head -3
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all | head -5
    fi
}

# System update
run_updates() {
    print_header "System Update & Patch"
    
    echo "Updating system packages..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get upgrade -y -qq
    elif command -v yum &>/dev/null; then
        yum update -y -q
    fi
    
    echo "Checking for security updates..."
    if command -v unattended-upgrade &>/dev/null; then
        unattended-upgrade -d
    fi
    
    echo "✓ Updates completed"
}

# Run security audit
security_audit() {
    print_header "Security Audit"
    
    if [[ -f /usr/local/bin/openclaw-security-audit.sh ]]; then
        /usr/local/bin/openclaw-security-audit.sh
    else
        echo "Security audit script not found"
    fi
}

# Backup system
backup_system() {
    print_header "Create Backup"
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/openclaw-backup-$TIMESTAMP.tar.gz"
    
    echo "Stopping OpenClaw service..."
    systemctl stop openclaw
    
    echo "Creating backup: $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" \
        -C "$OPENCLAW_HOME" config/ data/ logs/ 2>/dev/null || true
    
    echo "Restarting OpenClaw service..."
    systemctl start openclaw
    
    echo "✓ Backup completed: $BACKUP_FILE"
    echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"
}

# Restore from backup
restore_backup() {
    print_header "Restore from Backup"
    
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print $9, "(" $5 ")"}'
    
    echo ""
    read -p "Enter backup file to restore: " backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        echo "✗ Backup file not found"
        return 1
    fi
    
    echo "Stopping OpenClaw service..."
    systemctl stop openclaw
    
    echo "Restoring from: $backup_file"
    tar -xzf "$backup_file" -C "$OPENCLAW_HOME" 2>/dev/null || true
    
    echo "Restarting OpenClaw service..."
    systemctl start openclaw
    
    echo "✓ Restore completed"
}

# View logs
view_logs() {
    print_header "View Application Logs"
    
    echo "1. OpenClaw logs (last 50 lines)"
    echo "2. OpenClaw logs (follow/tail -f)"
    echo "3. System logs for openclaw"
    echo "4. Tailscale logs"
    echo "5. Docker logs"
    echo "0. Exit"
    
    read -p "Select option: " log_choice
    
    case $log_choice in
        1)
            journalctl -u openclaw -n 50 --no-pager
            ;;
        2)
            journalctl -u openclaw -f
            ;;
        3)
            journalctl -u openclaw -n 100 --no-pager
            ;;
        4)
            journalctl -u tailscaled -n 50 --no-pager
            ;;
        5)
            docker logs $(docker ps --filter "label=openclaw=true" -q) 2>/dev/null || echo "No containers"
            ;;
        0)
            return
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

# Restart services
restart_services() {
    print_header "Restart Services"
    
    echo "Restarting OpenClaw..."
    systemctl restart openclaw
    sleep 3
    
    echo "Restarting Tailscale..."
    systemctl restart tailscaled
    sleep 2
    
    echo "Restarting Docker..."
    systemctl restart docker
    sleep 2
    
    echo "✓ Services restarted"
    
    # Verify
    echo ""
    echo "Service status:"
    systemctl status openclaw --no-pager | head -3
}

# Check and repair permissions
fix_permissions() {
    print_header "Fix File Permissions"
    
    echo "Fixing OpenClaw directory permissions..."
    
    # Set correct permissions
    find "$OPENCLAW_HOME" -type d -exec chmod 755 {} \;
    find "$OPENCLAW_HOME" -type f -exec chmod 644 {} \;
    chmod 750 "$OPENCLAW_HOME"/config
    chmod 750 "$OPENCLAW_HOME"/data
    
    # Set ownership
    chown -R openclaw:openclaw "$OPENCLAW_HOME"
    chown -R openclaw:openclaw /var/log/openclaw
    
    echo "✓ Permissions fixed"
}

# Clean up old logs and backups
cleanup_old_files() {
    print_header "Cleanup Old Files"
    
    echo "Cleaning up logs older than 30 days..."
    find /var/log/openclaw -type f -mtime +30 -delete
    echo "✓ Old logs cleaned"
    
    echo ""
    echo "Cleaning up backups older than 30 days..."
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
    echo "✓ Old backups cleaned"
    
    echo ""
    echo "Current disk usage:"
    du -sh "$OPENCLAW_HOME" "$BACKUP_DIR" /var/log/openclaw
}

# Network diagnostics
network_diagnostics() {
    print_header "Network Diagnostics"
    
    print_section "Network Interfaces"
    ip addr show | grep -E "inet|link/ether"
    
    print_section "DNS Configuration"
    cat /etc/resolv.conf | head -3
    
    print_section "Routing Table"
    ip route show | head -5
    
    print_section "Open Ports"
    netstat -tlnp 2>/dev/null | grep LISTEN || echo "No listening ports"
    
    print_section "Tailscale Network"
    sudo tailscale status 2>/dev/null || echo "Tailscale not configured"
}

# Generate system report
system_report() {
    print_header "Generate System Report"
    
    REPORT_FILE="/var/log/openclaw-system-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "OpenClaw System Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        
        echo "=== System Info ==="
        uname -a
        echo ""
        
        echo "=== OpenClaw Status ==="
        systemctl status openclaw --no-pager || true
        echo ""
        
        echo "=== Tailscale Status ==="
        sudo tailscale status 2>/dev/null || echo "Tailscale info not available"
        echo ""
        
        echo "=== Resources ==="
        free -h
        df -h
        echo ""
        
        echo "=== Docker Storage ==="
        docker system df 2>/dev/null || true
        echo ""
        
        echo "=== Recent Errors ==="
        journalctl -p err -n 20 --no-pager
        echo ""
        
        echo "=== OpenClaw Logs ==="
        journalctl -u openclaw -n 50 --no-pager
        
    } | tee "$REPORT_FILE"
    
    echo ""
    echo "✓ Report saved to: $REPORT_FILE"
}

# Menu
show_menu() {
    print_header "OpenClaw Maintenance Menu"
    
    echo "1.  Health Check"
    echo "2.  Status Check"
    echo "3.  Security Audit"
    echo "4.  System Update"
    echo "5.  Create Backup"
    echo "6.  Restore Backup"
    echo "7.  View Logs"
    echo "8.  Restart Services"
    echo "9.  Fix Permissions"
    echo "10. Cleanup Old Files"
    echo "11. Network Diagnostics"
    echo "12. Generate System Report"
    echo "13. Help/Documentation"
    echo "0.  Exit"
    echo ""
}

# Help menu
show_help() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║           OpenClaw Maintenance Help & Documentation           ║
╚════════════════════════════════════════════════════════════════╝

COMMON TASKS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Check System Health
   $ sudo ./05-maintenance.sh
   Select: 1

2. Create Backup
   $ sudo ./05-maintenance.sh
   Select: 5

3. Restore from Backup
   $ sudo ./05-maintenance.sh
   Select: 6

4. View OpenClaw Logs
   $ sudo journalctl -u openclaw -f

5. Restart OpenClaw
   $ sudo systemctl restart openclaw

EMERGENCY PROCEDURES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service Failure:
   $ sudo systemctl status openclaw
   $ sudo systemctl restart openclaw
   $ sudo journalctl -u openclaw -n 50

Network Issues:
   $ sudo tailscale status
   $ sudo tailscale down
   $ sudo tailscale up

Disk Space Full:
   $ df -h
   $ sudo du -sh /var/log/openclaw/*
   $ sudo du -sh /var/backups/openclaw/*

DIAGNOSTIC COMMANDS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

System Status:
   $ sudo systemctl status openclaw tailscaled
   $ docker ps
   $ sudo tailscale status

Resource Usage:
   $ top -p $(pgrep -f docker)
   $ docker stats
   $ df -h

Network:
   $ netstat -tlnp
   $ sudo tailscale ping <device>
   $ ping 8.8.8.8

Logs:
   $ journalctl -u openclaw -n 100
   $ docker logs openclaw
   $ tail -f /var/log/openclaw/*.log

BACKUP MANAGEMENT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create Backup:
   $ sudo openclaw-backup.sh

List Backups:
   $ ls -lh /var/backups/openclaw/

Restore Backup:
   $ sudo tar -xzf /var/backups/openclaw/openclaw-backup-YYYYMMDD.tar.gz -C /opt/openclaw/

SECURITY OPERATIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Audit:
   $ sudo openclaw-security-audit.sh

Check File Integrity:
   $ sudo aide --check

View Security Logs:
   $ sudo grep "Failed password" /var/log/auth.log

Monitor Access:
   $ sudo journalctl -u openssh -f

FILE LOCATIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Application:        /opt/openclaw/
Configuration:      /opt/openclaw/config/
Data:              /opt/openclaw/data/
Logs:              /var/log/openclaw/
Backups:           /var/backups/openclaw/
SSH Config:        /etc/ssh/sshd_config
Firewall Rules:    /etc/ufw/rules.v4 (UFW)
Tailscale:         /var/lib/tailscale/

SUPPORT CONTACTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OpenClaw Team: [contact]
System Admin:  [contact]
Emergency:     [emergency contact]

EOF
    read -p "Press ENTER to continue..."
}

# Main loop
main() {
    check_root
    
    if [[ $# -gt 0 ]]; then
        case $1 in
            health)
                health_check
                ;;
            status)
                status_check
                ;;
            audit)
                security_audit
                ;;
            update)
                run_updates
                ;;
            backup)
                backup_system
                ;;
            restore)
                restore_backup
                ;;
            cleanup)
                cleanup_old_files
                ;;
            *)
                echo "Unknown command: $1"
                ;;
        esac
    else
        # Interactive menu
        while true; do
            show_menu
            read -p "Select option: " choice
            
            case $choice in
                1)
                    health_check
                    ;;
                2)
                    status_check
                    ;;
                3)
                    security_audit
                    ;;
                4)
                    run_updates
                    ;;
                5)
                    backup_system
                    ;;
                6)
                    restore_backup
                    ;;
                7)
                    view_logs
                    ;;
                8)
                    restart_services
                    ;;
                9)
                    fix_permissions
                    ;;
                10)
                    cleanup_old_files
                    ;;
                11)
                    network_diagnostics
                    ;;
                12)
                    system_report
                    ;;
                13)
                    show_help
                    ;;
                0)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    echo "Invalid option"
                    ;;
            esac
            
            read -p "Press ENTER to continue..."
        done
    fi
}

main "$@"

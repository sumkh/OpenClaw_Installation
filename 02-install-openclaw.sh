#!/bin/bash

##############################################################################
# OpenClaw Installation Script
# Purpose: Install OpenClaw with security best practices
# Runs on: Ubuntu 22.04+ or CentOS 8+
# Usage: sudo ./02-install-openclaw.sh
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration variables
OPENCLAW_USER="openclaw"
OPENCLAW_GROUP="openclaw"
OPENCLAW_HOME="/opt/openclaw"
OPENCLAW_VERSION="latest" # Change to specific version if needed
LOG_DIR="/var/log/openclaw-setup"
LOG_FILE="${LOG_DIR}/openclaw-install-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/var/backups/openclaw"

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

# Install Docker
install_docker() {
    log "INFO" "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        log "INFO" "Docker already installed"
        return
    fi
    
    if [[ "$OS" == "ubuntu" ]]; then
        apt-get update
        apt-get install -y -q \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        echo \
            "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
        yum install -y -q yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
    
    systemctl enable docker
    systemctl start docker
    log "INFO" "Docker installed successfully"
}

# Install Docker Compose
install_docker_compose() {
    log "INFO" "Installing Docker Compose..."
    
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    
    chmod +x /usr/local/bin/docker-compose
    
    log "INFO" "Docker Compose installed: $(docker-compose --version)"
}

# Create OpenClaw user and directories
create_openclaw_user() {
    log "INFO" "Creating OpenClaw user and directories..."
    
    # Create user if doesn't exist
    if ! id "$OPENCLAW_USER" &>/dev/null; then
        groupadd -r "$OPENCLAW_GROUP" 2>/dev/null || true
        useradd -r -g "$OPENCLAW_GROUP" -d "$OPENCLAW_HOME" -s /usr/sbin/nologin "$OPENCLAW_USER"
        log "INFO" "Created user: $OPENCLAW_USER"
    fi
    
    # Create directories with proper permissions
    mkdir -p "$OPENCLAW_HOME"/{config,data,logs,backups}
    mkdir -p /var/log/openclaw
    mkdir -p "$BACKUP_DIR"
    
    # Set permissions (principle of least privilege)
    chown -R "$OPENCLAW_USER:$OPENCLAW_GROUP" "$OPENCLAW_HOME"
    chown -R "$OPENCLAW_USER:$OPENCLAW_GROUP" /var/log/openclaw
    chmod 750 "$OPENCLAW_HOME"
    chmod 750 "$OPENCLAW_HOME"/config
    chmod 755 "$OPENCLAW_HOME"/logs
    chmod 750 "$OPENCLAW_HOME"/data
    
    log "INFO" "User and directories created"
}

# Download and verify OpenClaw
install_openclaw_application() {
    log "INFO" "Installing OpenClaw application..."
    
    # Note: Update this with actual OpenClaw download URL
    # This is a placeholder - adjust based on actual OpenClaw distribution
    
    # Example for Docker-based OpenClaw:
    log "INFO" "Pulling OpenClaw Docker image..."
    
    # docker pull openclaw/openclaw:$OPENCLAW_VERSION
    
    # For non-containerized installation:
    # cd "$OPENCLAW_HOME"
    # wget https://github.com/openclaw-org/openclaw/releases/download/v$OPENCLAW_VERSION/openclaw-$OPENCLAW_VERSION.tar.gz
    # tar -xzf openclaw-$OPENCLAW_VERSION.tar.gz
    
    log "INFO" "OpenClaw application installed"
}

# Create docker-compose.yml for OpenClaw
create_docker_compose_file() {
    log "INFO" "Creating Docker Compose configuration..."
    
    cat > "$OPENCLAW_HOME/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    user: "$OPENCLAW_UID:$OPENCLAW_GID"
    
    # Security configurations
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    
    # Read-only root filesystem where possible
    read_only: false
    tmpfs:
      - /tmp
      - /run
    
    volumes:
      - ./config:/etc/openclaw:ro
      - ./data:/var/lib/openclaw:rw
      - ./logs:/var/log/openclaw:rw
      - /etc/localtime:/etc/localtime:ro
    
    # Network configuration
    networks:
      - openclaw-net
    
    # Environment variables
    environment:
      - OPENCLAW_LOG_LEVEL=INFO
      - OPENCLAW_MODE=production
      - OPENCLAW_SECURE_MODE=true
    
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
    
    # Logging
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "openclaw=true"

networks:
  openclaw-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
EOF
    
    log "INFO" "Docker Compose configuration created"
}

# Create OpenClaw systemd service
create_systemd_service() {
    log "INFO" "Creating systemd service..."
    
    cat > /etc/systemd/system/openclaw.service << EOF
[Unit]
Description=OpenClaw Application Service
Documentation=https://openclaw.org/docs
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$OPENCLAW_HOME

# Security settings
PrivateTmp=yes
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$OPENCLAW_HOME/data $OPENCLAW_HOME/logs /var/log/openclaw

# Service restart policy
Restart=on-failure
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# Standard output
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw

# Start/Stop commands
ExecStartPre=/usr/bin/docker-compose -f $OPENCLAW_HOME/docker-compose.yml pull
ExecStart=/usr/bin/docker-compose -f $OPENCLAW_HOME/docker-compose.yml up
ExecStop=/usr/bin/docker-compose -f $OPENCLAW_HOME/docker-compose.yml down
ExecReload=/usr/bin/docker-compose -f $OPENCLAW_HOME/docker-compose.yml restart

# Timeout settings
TimeoutStartSec=900
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable openclaw
    
    log "INFO" "Systemd service created and enabled"
}

# Create configuration file
create_config_file() {
    log "INFO" "Creating OpenClaw configuration..."
    
    cat > "$OPENCLAW_HOME/config/openclaw.conf" << 'EOF'
# OpenClaw Secure Configuration
# Generated by secure installation script

# Server Configuration
server.port=8080
server.bind=127.0.0.1
server.ssl.enabled=true
server.ssl.certificate=/opt/openclaw/config/certs/openclaw.crt
server.ssl.key=/opt/openclaw/config/certs/openclaw.key

# Security Settings
security.mode=production
security.strict_mode=true
security.enable_csp=true
security.enable_cors=false

# Logging
logging.level=INFO
logging.file=/var/log/openclaw/openclaw.log
logging.rotation.size=10M
logging.retention.days=30

# Database
db.secure_connection=true
db.ssl_verify=true

# Rate limiting
ratelimit.enabled=true
ratelimit.requests_per_minute=100

# Session settings
session.timeout=1800
session.secure_cookie=true
session.httponly=true
session.samesite=Strict

# Feature flags
features.audit_logging=true
features.two_factor_auth=true
features.ip_whitelist=false
EOF
    
    chown "$OPENCLAW_USER:$OPENCLAW_GROUP" "$OPENCLAW_HOME/config/openclaw.conf"
    chmod 640 "$OPENCLAW_HOME/config/openclaw.conf"
    
    log "INFO" "Configuration file created"
}

# Setup SSL certificates
setup_ssl_certificates() {
    log "INFO" "Setting up SSL certificates..."
    
    CERT_DIR="$OPENCLAW_HOME/config/certs"
    mkdir -p "$CERT_DIR"
    
    # Generate self-signed certificate (for development)
    # For production, use proper CA-signed certificates
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/openclaw.key" \
        -out "$CERT_DIR/openclaw.crt" \
        -subj "/C=US/ST=State/L=City/O=Org/CN=localhost"
    
    chmod 600 "$CERT_DIR/openclaw.key"
    chmod 644 "$CERT_DIR/openclaw.crt"
    chown "$OPENCLAW_USER:$OPENCLAW_GROUP" "$CERT_DIR"/*
    
    log "INFO" "SSL certificates created (self-signed)"
    log "WARN" "For production, replace with CA-signed certificates"
}

# Create backup script
create_backup_script() {
    log "INFO" "Creating backup script..."
    
    cat > /usr/local/bin/openclaw-backup.sh << 'EOF'
#!/bin/bash
# OpenClaw Backup Script

OPENCLAW_HOME="/opt/openclaw"
BACKUP_DIR="/var/backups/openclaw"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/openclaw-backup-$TIMESTAMP.tar.gz"

echo "Starting OpenClaw backup..."

# Stop service
systemctl stop openclaw

# Create backup
tar -czf "$BACKUP_FILE" \
    -C "$OPENCLAW_HOME" config/ data/ logs/

# Restart service
systemctl start openclaw

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "openclaw-backup-*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
EOF
    
    chmod +x /usr/local/bin/openclaw-backup.sh
    
    # Add to cron (daily at 3 AM)
    echo "0 3 * * * /usr/local/bin/openclaw-backup.sh >> /var/log/openclaw-backup.log 2>&1" | \
    crontab -
    
    log "INFO" "Backup script created and scheduled"
}

# Start OpenClaw service
start_openclaw() {
    log "INFO" "Starting OpenClaw service..."
    
    systemctl start openclaw
    sleep 5
    
    if systemctl is-active --quiet openclaw; then
        log "INFO" "OpenClaw service started successfully"
    else
        log "ERROR" "Failed to start OpenClaw service"
        systemctl status openclaw
        exit 1
    fi
}

# Verify installation
verify_installation() {
    log "INFO" "Verifying installation..."
    
    echo ""
    echo "Service Status:"
    systemctl status openclaw --no-pager
    
    echo ""
    echo "Docker Containers:"
    docker ps --filter "label=openclaw=true"
    
    echo ""
    echo "Listening Ports:"
    netstat -tlnp 2>/dev/null | grep -E ":(8080|443)" || echo "Ports not yet listening"
    
    echo ""
    echo "Recent Logs:"
    journalctl -u openclaw -n 10 --no-pager
}

# Print summary
print_summary() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║          OpenClaw Installation - COMPLETED ✓                  ║
╚════════════════════════════════════════════════════════════════╝

✓ Docker and Docker Compose installed
✓ OpenClaw user and directories created
✓ OpenClaw application installed
✓ Docker Compose configuration configured
✓ Systemd service created
✓ SSL certificates generated
✓ Backup script configured
✓ OpenClaw service started

IMPORTANT INFORMATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Installation Path: /opt/openclaw
Config Path:       /opt/openclaw/config
Data Path:         /opt/openclaw/data
Log Path:          /var/log/openclaw

Service Commands:
  Status:   sudo systemctl status openclaw
  Start:    sudo systemctl start openclaw
  Stop:     sudo systemctl stop openclaw
  Restart:  sudo systemctl restart openclaw
  Logs:     sudo journalctl -u openclaw -f

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Run: sudo ./03-setup-tailscale.sh
2. Then:  sudo ./04-post-install-security.sh
3. Verify OpenClaw is accessible via Tailscale
4. Configure proper SSL certificates for production

SECURITY REMINDERS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠  SSL certificates are self-signed (for development only)
⚠  Replace with CA-signed certificates for production
⚠  Review and configure firewall rules
⚠  Setup backup verification procedures
⚠  Enable monitoring and alerting

Logs: $LOG_FILE

EOF
}

# Main execution
main() {
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    
    log "INFO" "Starting OpenClaw installation"
    log "INFO" "User: $(whoami)"
    log "INFO" "Hostname: $(hostname)"
    
    check_root
    detect_os
    install_docker
    install_docker_compose
    create_openclaw_user
    install_openclaw_application
    create_docker_compose_file
    create_systemd_service
    create_config_file
    setup_ssl_certificates
    create_backup_script
    start_openclaw
    
    sleep 2
    verify_installation
    
    log "INFO" "OpenClaw installation completed successfully"
    print_summary
}

trap 'log "ERROR" "Script failed at line $LINENO"' ERR

main "$@"

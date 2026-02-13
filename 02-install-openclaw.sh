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

# Clone and build OpenClaw from official repository
install_openclaw_application() {
    log "INFO" "Installing OpenClaw from official repository..."
    
    if [[ -d "$OPENCLAW_HOME/.git" ]]; then
        log "INFO" "OpenClaw repository already exists. Updating..."
        cd "$OPENCLAW_HOME"
        git fetch origin
        git pull origin main
    else
        log "INFO" "Cloning OpenClaw repository..."
        cd /tmp
        git clone https://github.com/openclaw/openclaw.git openclaw-repo
        
        # Copy the repo to OPENCLAW_HOME (git repo and all)
        mkdir -p "$OPENCLAW_HOME"
        cp -r /tmp/openclaw-repo/* "$OPENCLAW_HOME/"
        cp -r /tmp/openclaw-repo/.git "$OPENCLAW_HOME/" 2>/dev/null || true
        
        rm -rf /tmp/openclaw-repo
    fi
    
    log "INFO" "Creating config and workspace directories..."
    mkdir -p "$OPENCLAW_HOME/{.openclaw,.openclaw/workspace,config}"
    
    log "INFO" "Building OpenClaw Docker image..."
    cd "$OPENCLAW_HOME"
    
    # Support optional APT packages via environment variable
    BUILD_ARGS=""
    if [[ -n "${OPENCLAW_DOCKER_APT_PACKAGES:-}" ]]; then
        BUILD_ARGS="--build-arg OPENCLAW_DOCKER_APT_PACKAGES=\"${OPENCLAW_DOCKER_APT_PACKAGES}\""
        log "INFO" "Building with additional apt packages: ${OPENCLAW_DOCKER_APT_PACKAGES}"
    fi
    
    docker build \
        $BUILD_ARGS \
        -t "openclaw:local" \
        -f "$OPENCLAW_HOME/Dockerfile" \
        "$OPENCLAW_HOME" || {
        log "ERROR" "Failed to build Docker image"
        return 1
    }
    
    # Set proper ownership
    chown -R "$OPENCLAW_USER:$OPENCLAW_GROUP" "$OPENCLAW_HOME"
    
    log "INFO" "OpenClaw application installed successfully"
}

# Create .env file with gateway configuration
create_environment_file() {
    log "INFO" "Creating .env file with gateway configuration..."
    
    # Generate a secure gateway token if not present
    if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        else
            OPENCLAW_GATEWAY_TOKEN=$(tr -dc 'A-Fa-f0-9' < /dev/urandom | head -c 64)
        fi
    fi
    
    OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT:-18789}
    OPENCLAW_BRIDGE_PORT=${OPENCLAW_BRIDGE_PORT:-18790}
    OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND:-lan}
    
    cat > "$OPENCLAW_HOME/.env" << EOF
# OpenClaw Gateway Configuration
OPENCLAW_IMAGE=openclaw:local
OPENCLAW_CONFIG_DIR=$OPENCLAW_HOME/.openclaw
OPENCLAW_WORKSPACE_DIR=$OPENCLAW_HOME/.openclaw/workspace
OPENCLAW_GATEWAY_PORT=$OPENCLAW_GATEWAY_PORT
OPENCLAW_BRIDGE_PORT=$OPENCLAW_BRIDGE_PORT
OPENCLAW_GATEWAY_BIND=$OPENCLAW_GATEWAY_BIND
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN

# Optional: Provider credentials (add as needed)
# CLAUDE_AI_SESSION_KEY=
# CLAUDE_WEB_SESSION_KEY=
# CLAUDE_WEB_COOKIE=
# GOOGLE_APPLICATION_CREDENTIALS=/opt/openclaw/secrets/google-sa.json
# WHATSAPP_CRED_FILE=/opt/openclaw/secrets/whatsapp.conf

# Optional: Additional apt packages for Docker build
# OPENCLAW_DOCKER_APT_PACKAGES=ffmpeg curl jq
EOF
    
    chown "$OPENCLAW_USER:$OPENCLAW_GROUP" "$OPENCLAW_HOME/.env"
    chmod 600 "$OPENCLAW_HOME/.env"
    
    log "INFO" "Gateway token (save this): $OPENCLAW_GATEWAY_TOKEN"
    log "INFO" ".env file created"
}

# Create docker-compose.override.yml for VM deployment
create_docker_compose_file() {
    log "INFO" "Creating docker-compose configuration..."
    
    # The official docker-compose.yml is already in the cloned repo
    # Create an override file for VM-specific configuration
    
    cat > "$OPENCLAW_HOME/docker-compose-vm.yml" << 'EOF'
version: '3.8'

services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE:-openclaw:local}
    container_name: openclaw-gateway
    restart: unless-stopped
    env_file:
      - .env
    environment:
      HOME: /home/node
      TERM: xterm-256color
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "${OPENCLAW_GATEWAY_PORT:-18789}:18789"
      - "${OPENCLAW_BRIDGE_PORT:-18790}:18790"
    init: true
    restart: unless-stopped
    networks:
      - openclaw-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  openclaw-cli:
    image: ${OPENCLAW_IMAGE:-openclaw:local}
    container_name: openclaw-cli
    env_file:
      - .env
    environment:
      HOME: /home/node
      TERM: xterm-256color
      BROWSER: echo
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    init: true
    networks:
      - openclaw-net
    command: ["node", "dist/index.js"]

networks:
  openclaw-net:
    driver: bridge
EOF
    
    log "INFO" "Docker Compose configuration created at docker-compose-vm.yml"
}

# Create OpenClaw systemd service
create_systemd_service() {
    log "INFO" "Creating systemd service for docker-compose..."
    
    cat > /etc/systemd/system/openclaw.service << EOF
[Unit]
Description=OpenClaw Gateway Service (Docker Compose)
Documentation=https://docs.openclaw.ai/
After=network-online.target docker.service docker.socket containerd.service
Requires=docker.service
Wants=network-online.target

[Service]
Type=exec
User=root
WorkingDirectory=$OPENCLAW_HOME

# Load environment variables from .env
EnvironmentFile=$OPENCLAW_HOME/.env

# Use docker compose (v2) with proper file references
Environment="COMPOSE_PROJECT_NAME=openclaw"
Environment="DOCKER_HOST=unix:///run/docker.sock"

# Security settings
PrivateTmp=yes
NoNewPrivileges=true

# Service restart policy
Restart=on-failure
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# Standard output
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw

# Start/Stop commands using docker compose (official v2 syntax)
ExecStartPre=/usr/bin/docker compose -f $OPENCLAW_HOME/docker-compose.yml pull
ExecStart=/usr/bin/docker compose -f $OPENCLAW_HOME/docker-compose.yml up --remove-orphans
ExecStop=/usr/bin/docker compose -f $OPENCLAW_HOME/docker-compose.yml down
ExecReload=/usr/bin/docker compose -f $OPENCLAW_HOME/docker-compose.yml restart

# Timeout settings
TimeoutStartSec=600
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
    log "INFO" "Configuration will be created via OpenClaw CLI onboarding"
    log "INFO" "After installation, run: sudo docker compose exec openclaw-cli node dist/index.js onboard"
}

# Setup SSL certificates
setup_ssl_certificates() {
    log "INFO" "SSL/TLS handled by OpenClaw runtime (no setup needed)"
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
║      OpenClaw Installation - COMPLETED ✓                       ║
║      (Official Docker-based Installation)                      ║
╚════════════════════════════════════════════════════════════════╝

✓ Docker and Docker Compose installed
✓ OpenClaw user and directories created
✓ OpenClaw repository cloned and Docker image built
✓ Environment configuration created (.env)
✓ Systemd service created and enabled
✓ OpenClaw service started

IMPORTANT INFORMATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Installation Path:  /opt/openclaw
Config Directory:   /opt/openclaw/.openclaw
Workspace:          /opt/openclaw/.openclaw/workspace
Log Path:           journalctl -u openclaw -f

Gateway Access:
  URL:    http://localhost:18789 (or http://VM_IP:18789)
  Token:  See .env file or run: grep OPENCLAW_GATEWAY_TOKEN /opt/openclaw/.env

Service Commands:
  Status:         sudo systemctl status openclaw
  Start:          sudo systemctl start openclaw
  Stop:           sudo systemctl stop openclaw
  Restart:        sudo systemctl restart openclaw
  View Logs:      sudo journalctl -u openclaw -f
  View Compose:   cd /opt/openclaw && sudo docker compose logs -f

Docker Commands:
  Run onboarding: sudo docker compose -f /opt/openclaw/docker-compose.yml run --rm openclaw-cli onboard
  Check health:   sudo docker compose -f /opt/openclaw/docker-compose.yml exec openclaw-gateway curl http://localhost:18789/health
  List services:  sudo docker compose -f /opt/openclaw/docker-compose.yml ps

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Wait 30-40 seconds for the gateway to start
2. (OPTIONAL) Run onboarding wizard:
   sudo docker compose -f /opt/openclaw/docker-compose.yml run --rm openclaw-cli onboard
3. Connect provider channels (WhatsApp, Telegram, Discord, etc.)
4. Run: sudo ./03-setup-tailscale.sh
5. Then: sudo ./04-post-install-security.sh
6. Access via Tailscale VPN for secure remote access

Running the Gateway:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The gateway is now running under systemd. It will:
- Auto-restart if it crashes
- Start automatically on VM reboot
- Log all output to journalctl

Provider Setup (After Onboarding):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cd /opt/openclaw
# WhatsApp (QR code login):
sudo docker compose exec openclaw-cli node dist/index.js channels login

# Telegram (bot token):
sudo docker compose exec openclaw-cli node dist/index.js channels add --channel telegram --token YOUR_BOT_TOKEN

# Discord (bot token):
sudo docker compose exec openclaw-cli node dist/index.js channels add --channel discord --token YOUR_BOT_TOKEN

For credential files (Google, WhatsApp API tokens), place them in:
/opt/openclaw/secrets/

DOCUMENTATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- Official Docs:     https://docs.openclaw.ai/
- Channels Guide:    https://docs.openclaw.ai/channels
- Deployment Guides: https://docs.openclaw.ai/install

Logs: $LOG_FILE

EOF
}

# Main execution
main() {
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    
    log "INFO" "Starting OpenClaw installation (official Docker-based)"
    log "INFO" "User: $(whoami)"
    log "INFO" "Hostname: $(hostname)"
    
    check_root
    detect_os
    install_docker
    install_docker_compose
    create_openclaw_user
    install_openclaw_application
    create_environment_file
    create_docker_compose_file
    create_systemd_service
    create_backup_script
    start_openclaw
    
    sleep 2
    verify_installation
    
    log "INFO" "OpenClaw installation completed successfully"
    print_summary
}

trap 'log "ERROR" "Script failed at line $LINENO"' ERR

main "$@"

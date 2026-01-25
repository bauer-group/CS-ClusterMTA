#!/bin/bash
set -e

#######################################
# CS-ClusterMTA Setup Script
# Creates .env, sets permissions, and
# prepares the stack for first start
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/clustermta"
ENV_FILE="$SCRIPT_DIR/.env"

#######################################
# Colors and Output
#######################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     ██████╗██╗     ██╗   ██╗███████╗████████╗███████╗██████╗  ║"
    echo "║    ██╔════╝██║     ██║   ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗ ║"
    echo "║    ██║     ██║     ██║   ██║███████╗   ██║   █████╗  ██████╔╝ ║"
    echo "║    ██║     ██║     ██║   ██║╚════██║   ██║   ██╔══╝  ██╔══██╗ ║"
    echo "║    ╚██████╗███████╗╚██████╔╝███████║   ██║   ███████╗██║  ██║ ║"
    echo "║     ╚═════╝╚══════╝ ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝ ║"
    echo "║                         MTA                                   ║"
    echo "║                                                               ║"
    echo "║                      Setup Script                             ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

#######################################
# Root Check
#######################################
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root!"
    echo "Please run with 'sudo ./setup.sh'."
    exit 1
fi

print_banner

#######################################
# 1. Check Requirements
#######################################
echo "[1/5] Checking requirements..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed!"
    echo "    Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed!"
    exit 1
fi

DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "unknown")
print_success "Docker $DOCKER_VERSION found"

#######################################
# 2. Copy files to install directory
#######################################
echo "[2/5] Installing files..."

# Check if we're already running from install directory
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ] && [ -n "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
    echo "    Copying files from $SCRIPT_DIR to $INSTALL_DIR..."

    # Copy main files
    cp -f "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/clustermta.sh" "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/setup.sh" "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/update.sh" "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/.env.example" "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true

    # Copy directories
    cp -rf "$SCRIPT_DIR/src" "$INSTALL_DIR/" 2>/dev/null || true
    cp -rf "$SCRIPT_DIR/config" "$INSTALL_DIR/" 2>/dev/null || true

    # Update paths
    ENV_FILE="$INSTALL_DIR/.env"
    SCRIPT_DIR="$INSTALL_DIR"

    print_success "Files installed to $INSTALL_DIR"
else
    print_warning "Running from $SCRIPT_DIR - skipping copy"
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR/clustermta.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/setup.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/update.sh" 2>/dev/null || true

#######################################
# 3. Create backup directory
#######################################
echo "[3/5] Creating directories..."

mkdir -p "$SCRIPT_DIR/backups"
print_success "Backup directory created"

#######################################
# 4. Create .env file
#######################################
echo "[4/5] Checking .env file..."

if [ ! -f "$ENV_FILE" ]; then
    echo "    Creating new .env file..."

    # Detect system values
    GEN_DATE=$(date)
    GEN_SERVER=$(hostname)
    GEN_TIMEZONE=$(cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
    GEN_SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    GEN_SERVER_IP=${GEN_SERVER_IP:-localhost}

    # Generate stack name from hostname (sanitized)
    GEN_STACK_NAME=$(echo "mx_${GEN_SERVER}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_' | head -c 32)
    GEN_STACK_NAME=${GEN_STACK_NAME:-mx_mailserver}

    # Create .env file
    cat > "$ENV_FILE" << ENVFILE
# ==============================================================================
# CS-CLUSTERMTA - MAILSERVER CONFIGURATION
# ==============================================================================
# Generated: $GEN_DATE
# Server: $GEN_SERVER
#
# Start the stack:
#   ./clustermta.sh start
#
# Documentation: README.md
# ==============================================================================


# ==============================================================================
# STACK IDENTIFICATION
# ==============================================================================

# Unique stack name (no special characters except underscore)
# Used for container names and volume names
STACK_NAME=${GEN_STACK_NAME}


# ==============================================================================
# POSTE.IO IMAGE
# ==============================================================================

# Docker image repository
POSTEIO_REPOSITORY=analogic/poste.io

# Poste.io version
# https://hub.docker.com/r/analogic/poste.io/tags
POSTEIO_VERSION=2.5.8


# ==============================================================================
# GENERAL SETTINGS
# ==============================================================================

# Timezone (auto-detected from host)
TIME_ZONE=${GEN_TIMEZONE}

# Hostname for the mail server (DNS A/AAAA record required)
# IMPORTANT: Change this to your actual mail server hostname!
SERVICE_HOSTNAME=mail.example.com

# Enable HTTPS (ON/OFF)
HTTPS_MODE=ON


# ==============================================================================
# SERVICE MODULES
# ==============================================================================

# ClamAV Antivirus (TRUE=disabled, saves ~1GB RAM)
DISABLE_CLAMAV=FALSE

# Rspamd Spam Filter (TRUE=disabled)
DISABLE_RSPAMD=FALSE

# Roundcube Webmail (TRUE=disabled)
DISABLE_ROUNDCUBE=FALSE
ENVFILE

    chmod 600 "$ENV_FILE"
    print_success ".env file created"

    # Show generated values
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  GENERATED CONFIGURATION                                       ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Stack Name: ${BLUE}${GEN_STACK_NAME}${NC}"
    echo -e "${GREEN}║${NC}  Timezone:   ${BLUE}${GEN_TIMEZONE}${NC}"
    echo -e "${GREEN}║${NC}  Server IP:  ${BLUE}${GEN_SERVER_IP}${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
else
    print_warning ".env file already exists - no changes"
fi

#######################################
# 5. Set permissions
#######################################
echo "[5/5] Setting permissions..."

chmod 600 "$ENV_FILE" 2>/dev/null || true
print_success "Permissions set"

#######################################
# Summary
#######################################
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Installation:${NC} $SCRIPT_DIR"
echo -e "${BLUE}Config file:${NC}  $ENV_FILE"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Edit the configuration (set your hostname!):"
echo -e "     ${BLUE}nano $ENV_FILE${NC}"
echo ""
echo "  2. Start the mail server:"
echo -e "     ${BLUE}cd $SCRIPT_DIR && sudo ./clustermta.sh start${NC}"
echo ""

SERVICE_HOSTNAME=$(grep -E "^SERVICE_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "YOUR_HOSTNAME")
echo "  3. Access the admin panel:"
echo -e "     ${BLUE}https://${SERVICE_HOSTNAME}/admin/${NC}"
echo ""
echo -e "${YELLOW}Management:${NC}"
echo "  ./clustermta.sh start|stop|restart|status|logs|update|backup|restore|help"
echo ""

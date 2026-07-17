#!/bin/bash
set -e

#######################################
# CS-ClusterMTA - Installer & Setup (all-in-one)
#
# One script for everything: it bootstraps the code into a git checkout at
# INSTALL_DIR, then configures it (.env, permissions, directories) and can
# start the stack. Because the deployment is always a real git checkout,
# `./clustermta.sh update` / `./update.sh` work reliably.
#
# Usage:
#   # One-line install (bootstraps into /opt/clustermta):
#   curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/setup.sh | sudo bash
#   curl -fsSL .../setup.sh | sudo bash -s -- --start      # install and start
#
#   # From a checkout (git clone ...; cd ...; sudo ./setup.sh):
#   sudo ./setup.sh [--start] [--yes]
#
# Environment overrides (advanced / testing):
#   CLUSTERMTA_REPO_URL, CLUSTERMTA_BRANCH, CLUSTERMTA_INSTALL_DIR
#######################################

REPO_URL="${CLUSTERMTA_REPO_URL:-https://github.com/bauer-group/CS-ClusterMTA.git}"
INSTALL_DIR="${CLUSTERMTA_INSTALL_DIR:-/opt/clustermta}"
BRANCH="${CLUSTERMTA_BRANCH:-main}"

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
    echo "║                 Installer & Setup Script                      ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_info()    { echo -e "${BLUE}→${NC} $1"; }

#######################################
# Parse Arguments
#######################################
AUTO_START=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --start|-s) AUTO_START=true; shift ;;
        --yes|-y)   shift ;;                 # accepted for compatibility (no prompts)
        --help|-h)
            echo "CS-ClusterMTA Installer & Setup"
            echo ""
            echo "Usage:"
            echo "  curl -fsSL <url>/setup.sh | sudo bash [-s -- options]"
            echo "  sudo ./setup.sh [options]"
            echo ""
            echo "Options:"
            echo "  --start, -s     Start the stack after setup"
            echo "  --yes, -y       Non-interactive mode"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

#######################################
# Root Check
#######################################
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root!"
    echo "Please run with sudo (e.g. 'sudo ./setup.sh' or 'curl ... | sudo bash')."
    exit 1
fi

#######################################
# Locate this script on disk (unreliable when piped via curl)
#######################################
SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
else
    SCRIPT_DIR=""   # piped (curl | bash) - no on-disk location
fi

# We are "in place" when running from the installed checkout itself.
running_in_place() {
    [ -n "$SCRIPT_DIR" ] && [ "$SCRIPT_DIR" = "$INSTALL_DIR" ] && [ -f "$SCRIPT_DIR/docker-compose.yml" ]
}

#######################################
# Bootstrap helpers
#######################################
ensure_tools() {
    if ! command -v git &> /dev/null; then
        print_info "Installing git..."
        apt-get update -qq && apt-get install -y -qq git
    fi
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        apt-get update -qq && apt-get install -y -qq curl
    fi
}

# Ensure INSTALL_DIR is a git checkout of REPO_URL@BRANCH. Handles three states:
#   1. already a git repo   -> fetch + hard reset to origin
#   2. non-git files present -> convert in place, PRESERVING untracked files
#                               (.env, backups/) - heals legacy copy-based installs
#   3. empty / missing       -> fresh clone
ensure_repo() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        print_info "Updating existing installation at $INSTALL_DIR..."
        git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true
        git -C "$INSTALL_DIR" fetch origin "$BRANCH"
        git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
    elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        print_warning "Existing non-git installation at $INSTALL_DIR - converting to a git checkout"
        print_info "Your .env and backups/ are kept (git only manages tracked files)"
        git -C "$INSTALL_DIR" init -q -b "$BRANCH"
        git -C "$INSTALL_DIR" remote add origin "$REPO_URL" 2>/dev/null || \
            git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL"
        git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
        git -C "$INSTALL_DIR" checkout -f -B "$BRANCH" "origin/$BRANCH"
    else
        print_info "Cloning CS-ClusterMTA into $INSTALL_DIR..."
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    fi

    git -C "$INSTALL_DIR" config core.fileMode false
    chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        echo "    Please install Docker first: https://docs.docker.com/engine/install/"
        exit 1
    fi
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed!"
        exit 1
    fi
    local docker_version
    docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "unknown")
    print_success "Docker $docker_version found"
}

#######################################
# Bootstrap phase: get the code to INSTALL_DIR, then re-run from there
#######################################
print_banner

if ! running_in_place; then
    print_info "Bootstrapping CS-ClusterMTA into $INSTALL_DIR..."
    ensure_tools
    ensure_repo
    print_success "Code ready at $INSTALL_DIR"
    echo ""
    # Re-exec the freshly installed copy so the rest runs from the git checkout.
    # Forward --start only when it was actually requested.
    if [ "$AUTO_START" = true ]; then
        exec "$INSTALL_DIR/setup.sh" --start
    else
        exec "$INSTALL_DIR/setup.sh"
    fi
fi

# From here on we run from the installed git checkout ($SCRIPT_DIR == $INSTALL_DIR).
ENV_FILE="$SCRIPT_DIR/.env"

#######################################
# 1. Requirements
#######################################
echo "[1/4] Checking requirements..."
check_docker

#######################################
# 2. Create directories
#######################################
echo "[2/4] Creating directories..."
mkdir -p "$SCRIPT_DIR/backups"
print_success "Backup directory ready"

#######################################
# 3. Create .env file
#######################################
echo "[3/4] Checking .env file..."

if [ ! -f "$ENV_FILE" ]; then
    echo "    Creating new .env file..."

    GEN_DATE=$(date)
    GEN_SERVER=$(hostname)
    GEN_TIMEZONE=$(cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
    GEN_SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    GEN_SERVER_IP=${GEN_SERVER_IP:-localhost}

    GEN_STACK_NAME=$(echo "mx_${GEN_SERVER}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_' | head -c 32)
    GEN_STACK_NAME=${GEN_STACK_NAME:-mx_mailserver}

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
POSTEIO_VERSION=2.5.14


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
# 4. Set permissions
#######################################
echo "[4/4] Setting permissions..."
chmod 600 "$ENV_FILE" 2>/dev/null || true
print_success "Permissions set"

#######################################
# Optional: start the stack
#######################################
if [ "$AUTO_START" = true ]; then
    echo ""
    print_info "Starting CS-ClusterMTA..."
    "$SCRIPT_DIR/clustermta.sh" start
fi

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
echo "  cd $SCRIPT_DIR"
echo "  ./clustermta.sh start|stop|restart|status|logs|update|backup|restore|help"
echo ""

#!/bin/bash
set -e

#######################################
# CS-ClusterMTA One-Line Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/install.sh | sudo bash
#
#######################################

REPO_URL="https://github.com/bauer-group/CS-ClusterMTA.git"
INSTALL_DIR="/opt/clustermta"
BRANCH="main"

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
    echo "║                   Self-Hosted Installer                       ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}→${NC} $1"; }

#######################################
# Root Check
#######################################
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root!"
        echo "Please run with: curl -fsSL ... | sudo bash"
        exit 1
    fi
}

#######################################
# Parse Arguments
#######################################
AUTO_START=false
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --start|-s)
            AUTO_START=true
            shift
            ;;
        --yes|-y)
            INTERACTIVE=false
            shift
            ;;
        --help|-h)
            echo "CS-ClusterMTA Installer"
            echo ""
            echo "Usage:"
            echo "  curl -fsSL <url>/install.sh | sudo bash [options]"
            echo ""
            echo "Options:"
            echo "  --start, -s     Start the stack after installation"
            echo "  --yes, -y       Non-interactive mode (no prompts)"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Interactive installation"
            echo "  curl -fsSL <url>/install.sh | sudo bash"
            echo ""
            echo "  # Install and start automatically"
            echo "  curl -fsSL <url>/install.sh | sudo bash -s -- --start"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#######################################
# Check Requirements
#######################################
check_requirements() {
    print_info "Checking requirements..."

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
            print_warning "This script is designed for Ubuntu/Debian. Other distros may work but are untested."
        fi
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        print_info "Installing git..."
        apt-get update -qq
        apt-get install -y -qq git
    fi

    # Check for curl
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        apt-get update -qq
        apt-get install -y -qq curl
    fi

    print_success "Requirements satisfied"
}

#######################################
# Check Docker
#######################################
check_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        print_success "Docker $DOCKER_VERSION found"
        return 0
    else
        print_error "Docker is not installed!"
        echo ""
        echo "Please install Docker first:"
        echo "  https://docs.docker.com/engine/install/"
        echo ""
        return 1
    fi
}

#######################################
# Clone Repository
#######################################
clone_repository() {
    print_info "Downloading CS-ClusterMTA..."

    if [ -d "$INSTALL_DIR/.git" ]; then
        print_info "Existing installation found, updating..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard origin/$BRANCH
    else
        if [ -d "$INSTALL_DIR" ]; then
            print_warning "Removing existing $INSTALL_DIR (not a git repo)"
            rm -rf "$INSTALL_DIR"
        fi
        git clone --depth 1 --branch $BRANCH "$REPO_URL" "$INSTALL_DIR"
    fi

    cd "$INSTALL_DIR"
    git config core.fileMode false
    chmod +x *.sh 2>/dev/null || true

    print_success "Repository cloned to $INSTALL_DIR"
}

#######################################
# Run Setup
#######################################
run_setup() {
    print_info "Running setup..."

    cd "$INSTALL_DIR"
    ./setup.sh

    print_success "Setup complete"
}

#######################################
# Start Stack
#######################################
start_stack() {
    print_info "Starting CS-ClusterMTA..."

    cd "$INSTALL_DIR"
    ./clustermta.sh start

    print_success "Stack started"
}

#######################################
# Print Summary
#######################################
print_summary() {
    local IP
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    IP=${IP:-localhost}

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Installation Complete!                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Installation: $INSTALL_DIR"
    echo ""
    echo "  Next steps:"
    echo "    1. Edit configuration:"
    echo -e "       ${BLUE}nano $INSTALL_DIR/.env${NC}"
    echo ""
    echo "    2. Start the mail server:"
    echo -e "       ${BLUE}cd $INSTALL_DIR && sudo ./clustermta.sh start${NC}"
    echo ""
    echo "    3. Access admin panel:"
    echo -e "       ${BLUE}https://<your-hostname>/admin/${NC}"
    echo ""
    echo "  Management commands:"
    echo "    cd $INSTALL_DIR"
    echo "    ./clustermta.sh status|logs|stop|restart|backup"
    echo ""
}

#######################################
# Main
#######################################
main() {
    print_banner
    check_root
    check_requirements

    if ! check_docker; then
        exit 1
    fi

    echo ""
    clone_repository
    run_setup

    if [ "$AUTO_START" = true ]; then
        start_stack
    fi

    print_summary
}

main "$@"

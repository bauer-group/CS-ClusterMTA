#!/bin/bash
set -e

#######################################
# CS-ClusterMTA Stack Management Script
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Helper Functions
#######################################
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} CS-ClusterMTA Management${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root!"
        echo "Please run with 'sudo $0 $1'."
        exit 1
    fi
}

check_requirements() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "docker-compose.yml not found: $COMPOSE_FILE"
        exit 1
    fi

    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found: $ENV_FILE"
        echo "Please run 'cp .env.example .env' and configure it first."
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed!"
        exit 1
    fi
}

get_stack_name() {
    grep -E "^STACK_NAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "clustermta"
}

is_stack_running() {
    local stack_name=$(get_stack_name)
    docker ps --format '{{.Names}}' | grep -q "^${stack_name}_app$"
}

#######################################
# Actions
#######################################
do_start() {
    print_header
    check_root "start"
    check_requirements

    local stack_name=$(get_stack_name)

    echo "Starting CS-ClusterMTA Stack: $stack_name"
    echo ""

    cd "$SCRIPT_DIR"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" up --build -d

    echo ""
    print_success "CS-ClusterMTA Stack started!"
    echo ""
    do_status
}

do_stop() {
    print_header
    check_root "stop"
    check_requirements

    local stack_name=$(get_stack_name)

    echo "Stopping CS-ClusterMTA Stack: $stack_name"
    echo ""

    cd "$SCRIPT_DIR"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" down

    echo ""
    print_success "CS-ClusterMTA Stack stopped!"
}

do_restart() {
    print_header
    check_root "restart"
    check_requirements

    local stack_name=$(get_stack_name)

    echo "Restarting CS-ClusterMTA Stack: $stack_name"
    echo ""

    cd "$SCRIPT_DIR"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" restart

    echo ""
    print_success "CS-ClusterMTA Stack restarted!"
    echo ""
    do_status
}

do_status() {
    check_requirements

    local stack_name=$(get_stack_name)
    local hostname=$(grep -E "^SERVICE_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "localhost")

    echo -e "${BLUE}=== Container Status ===${NC}"
    echo ""

    cd "$SCRIPT_DIR"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" ps

    echo ""
    echo -e "${BLUE}=== Access ===${NC}"
    echo "Admin:   https://${hostname}/admin/"
    echo "Webmail: https://${hostname}/webmail/"
    echo ""
}

do_logs() {
    check_requirements

    local stack_name=$(get_stack_name)

    cd "$SCRIPT_DIR"
    echo "Showing logs (Ctrl+C to exit)..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" logs -f
}

do_update() {
    print_header
    check_root "update"
    check_requirements

    local stack_name=$(get_stack_name)

    echo "Updating CS-ClusterMTA Stack: $stack_name"
    echo ""

    cd "$SCRIPT_DIR"

    # 1. Pull repository updates
    if [ -d ".git" ]; then
        echo -e "${BLUE}[1/3] Pulling repository updates...${NC}"
        ./update.sh
    else
        echo -e "${BLUE}[1/3] Skipping git pull (not a git repository)${NC}"
    fi

    echo ""

    # 2. Rebuild and restart containers
    echo -e "${BLUE}[2/3] Rebuilding containers...${NC}"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" up --build -d

    echo ""

    # 3. Cleanup old images
    echo -e "${BLUE}[3/3] Cleaning up old images...${NC}"
    docker image prune -f

    echo ""
    print_success "CS-ClusterMTA Stack updated!"
    echo ""
    do_status
}

do_backup() {
    print_header
    check_root "backup"
    check_requirements

    if ! is_stack_running; then
        print_error "CS-ClusterMTA Stack is not running!"
        echo "For a consistent backup, the stack must be running."
        echo "Start with: $0 start"
        exit 1
    fi

    local stack_name=$(get_stack_name)
    local backup_dir="$SCRIPT_DIR/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${stack_name}_backup_$timestamp.tar.gz"

    mkdir -p "$backup_dir"

    echo "Creating backup..."
    echo ""

    # Get volume name
    local volume_name="${stack_name}-data"

    # Create backup of volume
    echo -e "${BLUE}[1/2] Backing up mail data volume...${NC}"
    docker run --rm \
        -v "${volume_name}:/data:ro" \
        -v "$backup_dir:/backup" \
        alpine tar -czf "/backup/${stack_name}_backup_$timestamp.tar.gz" -C /data .

    echo -e "${BLUE}[2/2] Backing up configuration...${NC}"
    cp "$ENV_FILE" "$backup_dir/${stack_name}_env_$timestamp.conf"

    echo ""
    print_success "Backup created!"
    echo ""
    echo "Files:"
    echo "  Data:   $backup_file"
    echo "  Config: $backup_dir/${stack_name}_env_$timestamp.conf"
    echo ""
    echo "Restore with: $0 restore $backup_file"
}

do_restore() {
    print_header
    check_root "restore"

    local backup_file="${2:-}"

    if [ -z "$backup_file" ]; then
        print_error "No backup file specified!"
        echo ""
        echo "Usage: $0 restore <backup-file>"
        echo ""
        echo "Available backups:"
        ls -lh "$SCRIPT_DIR/backups/"*_backup_*.tar.gz 2>/dev/null || echo "  No backups found"
        exit 1
    fi

    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi

    if is_stack_running; then
        print_error "CS-ClusterMTA Stack is still running!"
        echo "For a safe restore, the stack must be stopped."
        echo "Stop with: $0 stop"
        exit 1
    fi

    check_requirements

    local stack_name=$(get_stack_name)
    local volume_name="${stack_name}-data"

    print_warning "WARNING: This will overwrite the current mail data!"
    echo "Backup: $backup_file"
    echo ""
    read -p "Continue? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Restoring backup..."

    # Remove old volume and create new
    docker volume rm "$volume_name" 2>/dev/null || true
    docker volume create "$volume_name"

    # Restore data
    docker run --rm \
        -v "${volume_name}:/data" \
        -v "$(dirname "$backup_file"):/backup:ro" \
        alpine tar -xzf "/backup/$(basename "$backup_file")" -C /data

    echo ""
    print_success "Restore completed!"
    echo ""
    echo "Start the stack with: $0 start"
}

do_destroy() {
    print_header
    check_root "destroy"

    local stack_name=$(get_stack_name)

    print_warning "WARNING: This will completely remove CS-ClusterMTA!"
    echo ""
    echo "This will delete:"
    echo "  - All Docker containers"
    echo "  - Mail data volume (${stack_name}-data)"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Destroying CS-ClusterMTA Stack..."

    cd "$SCRIPT_DIR"
    if [ -f "$COMPOSE_FILE" ] && [ -f "$ENV_FILE" ]; then
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$stack_name" down -v --remove-orphans 2>/dev/null || true
    fi

    echo ""
    print_success "CS-ClusterMTA Stack destroyed!"
}

do_help() {
    print_header
    echo "Usage: $0 <command> [options]"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  start             Start the mail server stack"
    echo "  stop              Stop the mail server stack"
    echo "  restart           Restart the stack"
    echo "  status            Show status and access URLs"
    echo "  logs              Show logs (Ctrl+C to exit)"
    echo "  update            Update repository and rebuild"
    echo "  backup            Create a backup (stack must be running)"
    echo "  restore <file>    Restore from backup (stack must be stopped)"
    echo "  destroy           Stop and remove all containers and volumes"
    echo "  help              Show this help"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 start"
    echo "  $0 logs"
    echo "  $0 backup"
    echo "  $0 restore backups/mx1_backup_20250125_120000.tar.gz"
    echo ""
}

#######################################
# Main
#######################################
case "${1:-}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    logs)
        do_logs
        ;;
    update)
        do_update
        ;;
    backup)
        do_backup
        ;;
    restore)
        do_restore "$@"
        ;;
    destroy)
        do_destroy
        ;;
    help|--help|-h|"")
        do_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        do_help
        exit 1
        ;;
esac

exit 0

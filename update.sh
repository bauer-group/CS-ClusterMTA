#!/bin/bash
set -e

#######################################
# CS-ClusterMTA Update Script
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

cd "$SCRIPT_DIR"

# Check if this is a git repository
if [ ! -d ".git" ]; then
    print_error "This is not a git repository - cannot update via git."
    echo ""
    echo "This installation was created without git (legacy copy-based install)."
    echo "Repair it in place (keeps your .env and backups/) by re-running the"
    echo "installer, which converts $SCRIPT_DIR into a proper git checkout:"
    echo ""
    echo "  curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/setup.sh | sudo bash"
    echo ""
    exit 1
fi

echo -e "${BLUE}Updating CS-ClusterMTA from git...${NC}"
echo ""

# Prevent file mode changes from showing as modifications
git config core.fileMode false

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Branch: $BRANCH"

# Check for local changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    print_warning "Local changes detected, stashing..."
    STASH_NAME="auto-stash-$(date +%Y%m%d_%H%M%S)"
    git stash push -m "$STASH_NAME"
    STASHED=true
else
    STASHED=false
fi

# Pull updates
echo ""
echo "Pulling updates..."
if git pull origin "$BRANCH"; then
    print_success "Repository updated"
else
    print_error "Git pull failed!"
    if [ "$STASHED" = true ]; then
        echo "Restoring local changes..."
        git stash pop
    fi
    exit 1
fi

# Restore stashed changes
if [ "$STASHED" = true ]; then
    echo ""
    echo "Restoring local changes..."
    if git stash pop; then
        print_success "Local changes restored"
    else
        print_warning "Could not automatically restore changes"
        echo "Your changes are saved in git stash. Run 'git stash pop' manually."
    fi
fi

# Fix script permissions
chmod +x "$SCRIPT_DIR/clustermta.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/setup.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/update.sh" 2>/dev/null || true

echo ""
print_success "Update complete!"
echo ""
echo "Current version:"
git log -1 --format="  %h %s (%cr)"
echo ""

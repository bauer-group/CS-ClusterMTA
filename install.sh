#!/bin/bash
set -e

#######################################
# CS-ClusterMTA - Installer (compatibility shim)
#
# install.sh has been merged into setup.sh, which is now the single entry point
# for both installation and configuration. This wrapper only exists so the
# published one-line URL keeps working:
#
#   curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/install.sh | sudo bash
#
# It simply delegates to setup.sh (local copy if present, otherwise fetched).
#######################################

# Prefer a local setup.sh when run from a checkout.
SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    if [ -f "$DIR/setup.sh" ]; then
        exec "$DIR/setup.sh" "$@"
    fi
fi

# Piped via curl (no checkout around): fetch and run setup.sh.
REPO_RAW="${CLUSTERMTA_REPO_RAW:-https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main}"
curl -fsSL "$REPO_RAW/setup.sh" | bash -s -- "$@"

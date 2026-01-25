# ═══════════════════════════════════════════════════════════════════════════════
# CS-ClusterMTA - Custom Poste.io Mail Server
# ═══════════════════════════════════════════════════════════════════════════════
# Customized Poste.io image with BAUER GROUP branding
#
# Features:
#   - Full mail server stack (SMTP, IMAP, POP3, Webmail)
#   - ClamAV antivirus protection
#   - Rspamd spam filtering
#   - Roundcube webmail interface
#   - Let's Encrypt SSL/TLS support
#   - Custom branding (favicon, colors)
#   - Multi-IP support (LISTEN_ON/SEND_ON)
#   - Roundcube plugins (persistent_login, swipe)
#
# Build:  docker compose build
# Run:    docker compose up -d
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# Build Arguments
# ───────────────────────────────────────────────────────────────────────────────
ARG POSTEIO_REPOSITORY="analogic/poste.io"
ARG POSTEIO_VERSION="2.5.8"

# ───────────────────────────────────────────────────────────────────────────────
# Base Image
# ───────────────────────────────────────────────────────────────────────────────
FROM ${POSTEIO_REPOSITORY}:${POSTEIO_VERSION}

# =============================================================================
# Custom Labels
# =============================================================================

# Metadata
LABEL vendor="BAUER GROUP"
LABEL maintainer="Karl Bauer <karl.bauer@bauer-group.com>"

# Opencontainers Metadata
LABEL org.opencontainers.image.title="ClusterMTA"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="BAUER GROUP"
LABEL org.opencontainers.image.authors="Karl Bauer <karl.bauer@bauer-group.com>"
LABEL org.opencontainers.image.source="https://github.com/bauer-group/CS-ClusterMTA"
LABEL org.opencontainers.image.url="https://github.com/bauer-group/CS-ClusterMTA"
LABEL org.opencontainers.image.documentation="https://github.com/bauer-group/CS-ClusterMTA#readme"
LABEL org.opencontainers.image.description="Customized Poste.io mail server with BAUER GROUP modifications."
LABEL org.opencontainers.image.version="0.0.0"

LABEL org.opencontainers.image.base.name="docker.io/${POSTEIO_REPOSITORY}"
LABEL org.opencontainers.image.base.version="${POSTEIO_VERSION}"

# =============================================================================
# System Setup
# =============================================================================

# Install additional packages for debugging/administration
RUN set -ex && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        less \
        iputils-ping && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /root/.cache /tmp/pear

# =============================================================================
# Customization
# =============================================================================

# Copy all custom assets (branding, init scripts, etc.)
# Directory structure:
#   assets/
#   ├── etc/cont-init.d/     # s6 init scripts (run after Poste.io scripts)
#   │   ├── 91-bind-hostname.sh      # Multi-IP binding
#   │   ├── 92-roundcube-plugins.sh  # Roundcube plugins
#   │   └── 93-custom-branding.sh    # BAUER GROUP branding
#   └── opt/                  # Custom files (favicon, etc.)
COPY assets/ /

# Make init scripts executable
RUN chmod +x /etc/cont-init.d/*.sh

# ───────────────────────────────────────────────────────────────────────────────
# Usage
# ───────────────────────────────────────────────────────────────────────────────
# Build:              docker compose build
# Start:              docker compose up -d
# Logs:               docker compose logs -f
# Admin panel:        https://<hostname>/admin/
# Webmail:            https://<hostname>/
# ───────────────────────────────────────────────────────────────────────────────

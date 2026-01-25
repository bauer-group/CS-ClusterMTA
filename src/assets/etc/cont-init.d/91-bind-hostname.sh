#!/usr/bin/with-contenv bash
# =============================================================================
# ClusterMTA - Multi-IP Binding Configuration
# =============================================================================
# Controls which IP addresses the mail server listens on and sends from.
#
# Environment Variables:
#   LISTEN_ON  - IPs for incoming connections (default: "*")
#                Values: "*" | "host" | "1.2.3.4 5.6.7.8"
#   SEND_ON    - IPs for outgoing mail (default: same as LISTEN_ON)
#                Values: "*" | "host" | "1.2.3.4"
#
# Examples:
#   LISTEN_ON="*"              # Listen on all interfaces (default)
#   LISTEN_ON="host"           # Listen on hostname's IPs only
#   LISTEN_ON="1.2.3.4"        # Listen on specific IP only
#   LISTEN_ON="1.2.3.4 5.6.7.8" # Listen on multiple IPs
#
# Based on: https://github.com/dirtsimple/poste.io
# Adapted for Poste.io 2.5.x
# =============================================================================

set -e

# =============================================================================
# Functions
# =============================================================================

# Expand IP list from environment variable
# Usage: ip_list "*" | ip_list "host" | ip_list "1.2.3.4 5.6.7.8"
ip_list() {
    local spec="${1:-*}"

    case "$spec" in
        "host")
            # Get IPs associated with container hostname
            getent hosts "$(hostname)" 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//'
            ;;
        "*")
            # Wildcard - return empty (services will use their defaults)
            echo ""
            ;;
        *)
            # Specific IPs - normalize whitespace to single spaces
            echo "$spec" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//'
            ;;
    esac
}

# Convert IP list to comma-separated format
# Usage: comma_list "1.2.3.4 5.6.7.8" -> "1.2.3.4, 5.6.7.8"
comma_list() {
    echo "$1" | tr ' ' ',' | sed 's/,/, /g'
}

# Get first IP from list (for single-IP settings)
first_ip() {
    echo "$1" | awk '{print $1}'
}

# Check if IP is IPv6
is_ipv6() {
    [[ "$1" == *:* ]]
}

# Format IP for config files (bracket IPv6)
format_ip() {
    local ip="$1"
    if is_ipv6 "$ip"; then
        echo "[$ip]"
    else
        echo "$ip"
    fi
}

# =============================================================================
# Main Configuration
# =============================================================================

echo "[ClusterMTA] Configuring IP bindings..."

# Get IP lists from environment
LISTEN_IPS=$(ip_list "${LISTEN_ON:-*}")
SEND_IPS=$(ip_list "${SEND_ON:-$LISTEN_ON}")

# If SEND_ON not set, use LISTEN_ON
if [ -z "$SEND_IPS" ] && [ -n "$LISTEN_IPS" ]; then
    SEND_IPS="$LISTEN_IPS"
fi

# If no specific IPs, skip configuration (use Poste.io defaults)
if [ -z "$LISTEN_IPS" ] || [ "${LISTEN_ON:-}" = "*" ]; then
    echo "[ClusterMTA] Using default IP binding (all interfaces)"
    exit 0
fi

echo "[ClusterMTA] Listen IPs: $LISTEN_IPS"
echo "[ClusterMTA] Send IPs: ${SEND_IPS:-$LISTEN_IPS}"

FIRST_LISTEN_IP=$(first_ip "$LISTEN_IPS")
FIRST_SEND_IP=$(first_ip "${SEND_IPS:-$LISTEN_IPS}")

# =============================================================================
# Dovecot Configuration
# =============================================================================

DOVECOT_CONF="/etc/dovecot/dovecot.conf"
if [ -f "$DOVECOT_CONF" ]; then
    echo "[ClusterMTA] Configuring Dovecot..."

    # Set listen addresses
    DOVECOT_LISTEN=$(comma_list "$LISTEN_IPS")
    if grep -q "^listen = " "$DOVECOT_CONF"; then
        sed -i "s/^listen = .*/listen = $DOVECOT_LISTEN/" "$DOVECOT_CONF"
    else
        echo "listen = $DOVECOT_LISTEN" >> "$DOVECOT_CONF"
    fi
fi

# =============================================================================
# Nginx Configuration
# =============================================================================

NGINX_CONF="/etc/nginx/sites-enabled/default"
if [ -f "$NGINX_CONF" ]; then
    echo "[ClusterMTA] Configuring Nginx..."

    # Build listen directives for each IP
    for ip in $LISTEN_IPS; do
        formatted=$(format_ip "$ip")
        # Add listen directives if not present
        # This is complex - Nginx config varies, so we log but don't modify heavily
    done

    echo "[ClusterMTA] Nginx IP binding - manual review may be needed"
fi

# =============================================================================
# Haraka SMTP Configuration (Port 25)
# =============================================================================

HARAKA_SMTP_CONF="/opt/haraka-smtp/config/smtp.ini"
if [ -f "$HARAKA_SMTP_CONF" ]; then
    echo "[ClusterMTA] Configuring Haraka SMTP..."

    # Set listen address
    if grep -q "^listen=" "$HARAKA_SMTP_CONF"; then
        sed -i "s/^listen=.*/listen=$(format_ip "$FIRST_LISTEN_IP"):25/" "$HARAKA_SMTP_CONF"
    fi
fi

# =============================================================================
# Haraka Submission Configuration (Ports 587, 465)
# =============================================================================

HARAKA_SUB_CONF="/opt/haraka-submission/config/smtp.ini"
if [ -f "$HARAKA_SUB_CONF" ]; then
    echo "[ClusterMTA] Configuring Haraka Submission..."

    # Build listen string for multiple ports
    LISTEN_PORTS=""
    for ip in $LISTEN_IPS; do
        formatted=$(format_ip "$ip")
        LISTEN_PORTS="${LISTEN_PORTS}${formatted}:587,${formatted}:465,"
    done
    LISTEN_PORTS="${LISTEN_PORTS%,}"  # Remove trailing comma

    if grep -q "^listen=" "$HARAKA_SUB_CONF"; then
        sed -i "s/^listen=.*/listen=$LISTEN_PORTS/" "$HARAKA_SUB_CONF"
    fi
fi

# =============================================================================
# Postfix Configuration (Outbound)
# =============================================================================

POSTFIX_MAIN="/etc/postfix/main.cf"
if [ -f "$POSTFIX_MAIN" ] && [ -n "$FIRST_SEND_IP" ]; then
    echo "[ClusterMTA] Configuring Postfix outbound IP..."

    # Set smtp_bind_address for outgoing connections
    if grep -q "^smtp_bind_address" "$POSTFIX_MAIN"; then
        sed -i "s/^smtp_bind_address.*/smtp_bind_address = $FIRST_SEND_IP/" "$POSTFIX_MAIN"
    else
        echo "smtp_bind_address = $FIRST_SEND_IP" >> "$POSTFIX_MAIN"
    fi

    # Set smtp_bind_address6 if we have IPv6
    for ip in ${SEND_IPS:-$LISTEN_IPS}; do
        if is_ipv6 "$ip"; then
            if grep -q "^smtp_bind_address6" "$POSTFIX_MAIN"; then
                sed -i "s/^smtp_bind_address6.*/smtp_bind_address6 = $ip/" "$POSTFIX_MAIN"
            else
                echo "smtp_bind_address6 = $ip" >> "$POSTFIX_MAIN"
            fi
            break
        fi
    done
fi

echo "[ClusterMTA] IP binding configuration complete"

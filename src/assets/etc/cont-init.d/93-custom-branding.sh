#!/usr/bin/with-contenv bash
# =============================================================================
# ClusterMTA - Custom Branding Configuration
# =============================================================================
# Applies BAUER GROUP branding to Poste.io components:
#   - Haraka SMTP greeting messages
#   - Admin panel brand name
#   - Pro feature unlock
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

BRAND_NAME="BAUER GROUP"
SMTP_GREETING="Server ($BRAND_NAME)"
SMTP_EHLO="$BRAND_NAME SMTP Service"
SMTP_GOODBYE="2.0.0 Goodbye from $BRAND_NAME"

# =============================================================================
# Haraka SMTP Branding
# =============================================================================

echo "[ClusterMTA] Applying Haraka branding..."

# Configure both haraka-smtp (port 25) and haraka-submission (587/465)
for haraka_dir in /opt/haraka-smtp /opt/haraka-submission; do
    if [ -d "$haraka_dir/config" ]; then
        echo "$SMTP_EHLO" > "$haraka_dir/config/ehlo_hello_message"
        echo "$SMTP_GREETING" > "$haraka_dir/config/smtpgreeting"
        echo "$SMTP_GOODBYE" > "$haraka_dir/config/connection_close_message"
    fi
done

# =============================================================================
# Admin Panel Branding
# =============================================================================

BRAND_FILE="/opt/admin/src/Base/Config/Brand.php"

if [ -f "$BRAND_FILE" ]; then
    echo "[ClusterMTA] Applying admin panel branding..."
    sed -i "s/private \\\$brandName = \"poste.io\";/private \\\$brandName = \"$BRAND_NAME\";/g" "$BRAND_FILE"
fi

# =============================================================================
# Pro Features Unlock
# =============================================================================

echo "[ClusterMTA] Enabling pro features in templates..."

# Find and update twig templates to enable pro features
for template_dir in /opt/admin/templates /opt/admin/templates/Base/Security; do
    if [ -d "$template_dir" ]; then
        find "$template_dir" -maxdepth 1 -type f -name "*.twig" -exec \
            sed -i 's/is_pro()/true/g' {} \;
    fi
done

echo "[ClusterMTA] Branding configuration complete"

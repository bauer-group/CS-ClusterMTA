#!/usr/bin/with-contenv bash
# =============================================================================
# ClusterMTA - Roundcube Plugin Configuration
# =============================================================================
# Enables additional Roundcube plugins:
#   - persistent_login: "Keep me logged in" / "Remember Me" functionality
#   - swipe: Touch swipe gestures for mobile devices
#
# These plugins are included in Roundcube but disabled by default.
# =============================================================================

set -e

ROUNDCUBE_CONFIG="/data/roundcube/config/config.inc.php"
PLUGINS_TO_ADD=("persistent_login" "swipe")

echo "[ClusterMTA] Configuring Roundcube plugins..."

# Wait for Roundcube config to exist (created by Poste.io on first start)
if [ ! -f "$ROUNDCUBE_CONFIG" ]; then
    echo "[ClusterMTA] Roundcube config not found yet, will be configured on next start"
    exit 0
fi

# Function to check if plugin is already enabled
plugin_enabled() {
    grep -q "'$1'" "$ROUNDCUBE_CONFIG" 2>/dev/null
}

# Function to add plugin to config
add_plugin() {
    local plugin="$1"

    if plugin_enabled "$plugin"; then
        echo "[ClusterMTA] Plugin '$plugin' already enabled"
        return 0
    fi

    # Find the plugins array and add the new plugin
    # Roundcube config has: $config['plugins'] = array('plugin1', 'plugin2');
    if grep -q "\$config\['plugins'\]" "$ROUNDCUBE_CONFIG"; then
        # Add plugin to existing array (before the closing parenthesis)
        sed -i "s/\(\$config\['plugins'\].*\));/\1, '$plugin');/" "$ROUNDCUBE_CONFIG"
        echo "[ClusterMTA] Plugin '$plugin' enabled"
    else
        echo "[ClusterMTA] Warning: Could not find plugins array in config"
    fi
}

# Configure persistent_login plugin
configure_persistent_login() {
    local plugin_config="/opt/www/roundcubemail/plugins/persistent_login/config.inc.php"

    if [ ! -f "$plugin_config" ]; then
        # Create plugin config if template exists
        local template="/opt/www/roundcubemail/plugins/persistent_login/config.inc.php.dist"
        if [ -f "$template" ]; then
            cp "$template" "$plugin_config"
            echo "[ClusterMTA] Created persistent_login config from template"
        fi
    fi
}

# Enable each plugin
for plugin in "${PLUGINS_TO_ADD[@]}"; do
    add_plugin "$plugin"
done

# Configure plugins that need additional setup
configure_persistent_login

echo "[ClusterMTA] Roundcube plugin configuration complete"

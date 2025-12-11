#!/bin/bash

# Plugin System for Marmot
# Provides extensible architecture for custom cleaners and tools

plugin_init() {
    # Ensure plugin directories exist
    mkdir -p "$MARMOT_PLUGIN_DIR"
    mkdir -p "$MARMOT_PLUGIN_DIR/installed"
    mkdir -p "$MARMOT_PLUGIN_DIR/cache"
    mkdir -p "$MARMOT_PLUGIN_DIR/temp"

    # Initialize plugin registry
    if [[ ! -f "$MARMOT_PLUGIN_DIR/registry.db" ]]; then
        sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << 'EOF'
CREATE TABLE IF NOT EXISTS plugins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE,
    version TEXT,
    author TEXT,
    description TEXT,
    category TEXT,
    plugin_type TEXT,
    location TEXT,
    enabled BOOLEAN DEFAULT 1,
    installed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_updated DATETIME
);

CREATE TABLE IF NOT EXISTS plugin_dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plugin_name TEXT,
    dependency_name TEXT,
    dependency_version TEXT,
    optional BOOLEAN DEFAULT 0
);

CREATE TABLE IF NOT EXISTS plugin_hooks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plugin_name TEXT,
    hook_point TEXT,
    hook_function TEXT,
    priority INTEGER DEFAULT 50
);

CREATE INDEX IF NOT EXISTS idx_plugin_name ON plugins(name);
CREATE INDEX IF NOT EXISTS idx_plugin_hook ON plugin_hooks(hook_point);
EOF
    fi

    # Load enabled plugins
    plugin_load_all
}

# Install plugin from file
plugin_install() {
    local plugin_file=$1

    if [[ -z $plugin_file ]]; then
        echo "Usage: plugin_install <plugin_file>"
        return 1
    fi

    if [[ ! -f "$plugin_file" ]]; then
        error "Plugin file not found: $plugin_file"
        return 1
    fi

    # Extract plugin
    local temp_dir=$(mktemp -d)
    if [[ ${plugin_file##*.} == "mpkg" ]]; then
        # Marmot package format
        tar -xzf "$plugin_file" -C "$temp_dir" || {
            rm -rf "$temp_dir"
            error "Failed to extract plugin package"
            return 1
        }
    else
        error "Unsupported plugin format"
        rm -rf "$temp_dir"
        return 1
    fi

    # Read plugin manifest
    local manifest="$temp_dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        error "Plugin manifest not found"
        rm -rf "$temp_dir"
        return 1
    fi

    # Parse manifest (simplified)
    local plugin_name=$(grep -o '"name":\s*"[^"]*"' "$manifest" | cut -d'"' -f4)
    local plugin_version=$(grep -o '"version":\s*"[^"]*"' "$manifest" | cut -d'"' -f4)

    if [[ -z $plugin_name ]]; then
        error "Invalid plugin manifest"
        rm -rf "$temp_dir"
        return 1
    fi

    # Check if already installed
    local existing=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT COUNT(*) FROM plugins WHERE name='$plugin_name';")

    if [[ $existing -gt 0 ]]; then
        read -p "Plugin '$plugin_name' already installed. Update? (y/N): " update
        if [[ $update != [yY] ]]; then
            rm -rf "$temp_dir"
            return 1
        fi
        plugin_uninstall "$plugin_name"
    fi

    # Install plugin files
    local install_dir="$MARMOT_PLUGIN_DIR/installed/$plugin_name"
    mkdir -p "$install_dir"
    cp -r "$temp_dir"/* "$install_dir/"

    # Make scripts executable
    find "$install_dir" -name "*.sh" -exec chmod +x {} \;

    # Register plugin
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << EOF
INSERT INTO plugins (name, version, location)
VALUES ('$plugin_name', '$plugin_version', '$install_dir');
EOF

    # Load plugin
    plugin_load "$plugin_name"

    # Cleanup
    rm -rf "$temp_dir"

    success "Plugin installed: $plugin_name v$plugin_version"
}

# Uninstall plugin
plugin_uninstall() {
    local plugin_name=$1

    if [[ -z $plugin_name ]]; then
        echo "Usage: plugin_uninstall <plugin_name>"
        return 1
    fi

    # Get plugin location
    local location=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT location FROM plugins WHERE name='$plugin_name';")

    if [[ -z $location ]]; then
        error "Plugin not found: $plugin_name"
        return 1
    fi

    # Check dependencies
    local dependents=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << EOF
SELECT DISTINCT p.name
FROM plugins p
JOIN plugin_dependencies d ON p.name = d.plugin_name
WHERE d.dependency_name = '$plugin_name';
EOF
)

    if [[ -n $dependents ]]; then
        echo "The following plugins depend on '$plugin_name':"
        echo "$dependents"
        if ! ask "Continue uninstallation?"; then
            return 1
        fi
    fi

    # Run uninstall hook if exists
    plugin_call_hook "$plugin_name" "uninstall"

    # Unload plugin
    plugin_unload "$plugin_name"

    # Remove plugin files
    rm -rf "$location"

    # Remove from registry
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "DELETE FROM plugins WHERE name='$plugin_name';"
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "DELETE FROM plugin_dependencies WHERE plugin_name='$plugin_name';"
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "DELETE FROM plugin_hooks WHERE plugin_name='$plugin_name';"

    success "Plugin uninstalled: $plugin_name"
}

# Load plugin
plugin_load() {
    local plugin_name=$1
    local plugin_dir=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT location FROM plugins WHERE name='$plugin_name' AND enabled=1;")

    if [[ -z $plugin_dir || ! -d "$plugin_dir" ]]; then
        return 1
    fi

    # Source plugin files
    local main_script="$plugin_dir/main.sh"
    if [[ -f "$main_script" ]]; then
        source "$main_script"
    fi

    # Register hooks
    local hooks_file="$plugin_dir/hooks.json"
    if [[ -f "$hooks_file" ]]; then
        # Parse and register hooks (simplified)
        while read -r hook; do
            local hook_point=$(echo $hook | jq -r '.hook_point' 2>/dev/null)
            local hook_function=$(echo $hook | jq -r '.function' 2>/dev/null)
            if [[ -n $hook_point && -n $hook_function ]]; then
                plugin_register_hook "$plugin_name" "$hook_point" "$hook_function"
            fi
        done < <(jq -c '.hooks[]' "$hooks_file" 2>/dev/null)
    fi

    # Call init hook
    plugin_call_hook "$plugin_name" "init"

    log "info" "Plugin loaded: $plugin_name"
}

# Unload plugin
plugin_unload() {
    local plugin_name=$1

    # Call cleanup hook
    plugin_call_hook "$plugin_name" "cleanup"

    # Unset plugin functions (simplified)
    unset -f "${plugin_name}_"*

    log "info" "Plugin unloaded: $plugin_name"
}

# Load all enabled plugins
plugin_load_all() {
    log "info" "Loading all enabled plugins..."

    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT name FROM plugins WHERE enabled=1;" | \
    while read -r plugin_name; do
        plugin_load "$plugin_name"
    done
}

# List installed plugins
plugin_list() {
    echo "Installed Plugins"
    echo "================="

    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << EOF
.headers on
.mode table

SELECT
    name,
    version,
    author,
    category,
    plugin_type,
    CASE WHEN enabled THEN '✓' ELSE '✗' END as Active,
    datetime(installed_at) as Installed
FROM plugins
ORDER BY name;
EOF
}

# Enable/disable plugin
plugin_toggle() {
    local plugin_name=$1
    local state=$2  # enable/disable

    if [[ -z $plugin_name || -z $state ]]; then
        echo "Usage: plugin_toggle <plugin_name> <enable|disable>"
        return 1
    fi

    local enabled=0
    [[ $state == "enable" ]] && enabled=1

    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "UPDATE plugins SET enabled=$enabled WHERE name='$plugin_name';"

    if [[ $enabled -eq 1 ]]; then
        plugin_load "$plugin_name"
    else
        plugin_unload "$plugin_name"
    fi

    success "Plugin '$plugin_name' $state""d"
}

# Register plugin hook
plugin_register_hook() {
    local plugin_name=$1
    local hook_point=$2
    local hook_function=$3
    local priority=${4:-50}

    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << EOF
INSERT OR REPLACE INTO plugin_hooks
(plugin_name, hook_point, hook_function, priority)
VALUES ('$plugin_name', '$hook_point', '$hook_function', $priority);
EOF
}

# Call hook point
plugin_call_hook() {
    local hook_point=$1
    shift

    # Get hooks for this point
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT plugin_name, hook_function FROM plugin_hooks \
         WHERE hook_point='$hook_point' ORDER BY priority DESC;" | \
    while read -r plugin_name hook_function; do
        if declare -F "$hook_function" >/dev/null; then
            "$hook_function" "$@" 2>/dev/null || \
                log "warn" "Hook function failed: $hook_function (from $plugin_name)"
        fi
    done
}

# Call specific plugin hook
plugin_call_hook() {
    local plugin_name=$1
    local hook_point=$2
    shift 2

    local hook_function=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT hook_function FROM plugin_hooks \
         WHERE plugin_name='$plugin_name' AND hook_point='$hook_point';")

    if [[ -n $hook_function ]] && declare -F "$hook_function" >/dev/null; then
        "$hook_function" "$@"
    fi
}

# Create plugin template
plugin_create_template() {
    local plugin_name=$1
    local plugin_dir="$MARMOT_PLUGIN_DIR/temp/$plugin_name"

    if [[ -z $plugin_name ]]; then
        read -p "Enter plugin name: " plugin_name
        if [[ -z $plugin_name ]]; then
            error "Plugin name required"
            return 1
        fi
    fi

    mkdir -p "$plugin_dir"

    # Create manifest
    cat > "$plugin_dir/manifest.json" << EOF
{
    "name": "$plugin_name",
    "version": "1.0.0",
    "author": "Your Name",
    "description": "Description of your plugin",
    "category": "cleanup",
    "plugin_type": "cleaner",
    "marmot_version": "1.12.1",
    "dependencies": [],
    "hooks": [
        {
            "hook_point": "pre_clean",
            "function": "${plugin_name}_pre_clean"
        },
        {
            "hook_point": "post_clean",
            "function": "${plugin_name}_post_clean"
        }
    ]
}
EOF

    # Create main script
    cat > "$plugin_dir/main.sh" << EOF
#!/bin/bash

# $plugin_name Plugin for Marmot
# Description: Your plugin description

# Plugin initialization
${plugin_name}_init() {
    log "info" "Initializing $plugin_name plugin"

    # Initialize plugin-specific variables
    export ${plugin_name^^}_DATA_DIR="\$MARMOT_PLUGIN_DIR/installed/$plugin_name/data"
    mkdir -p "\${${plugin_name^^}_DATA_DIR}"
}

# Pre-clean hook
${plugin_name}_pre_clean() {
    log "info" "$plugin_name: Pre-clean operations"

    # Add pre-clean logic here
}

# Post-clean hook
${plugin_name}_post_clean() {
    log "info" "$plugin_name: Post-clean operations"

    # Add post-clean logic here
}

# Main clean function (if this is a cleaner plugin)
${plugin_name}_clean() {
    log "info" "$plugin_name: Starting cleanup"

    # Add your cleanup logic here
    # Example: Remove specific cache files
    # find "\$HOME/.cache/some-app" -type f -name "*.tmp" -delete 2>/dev/null || true

    success "$plugin_name: Cleanup completed"
}

# Plugin cleanup
${plugin_name}_cleanup() {
    log "info" "$plugin_name: Cleaning up"

    # Cleanup plugin resources
}

# Plugin uninstall
${plugin_name}_uninstall() {
    log "info" "$plugin_name: Uninstalling"

    # Remove any persistent data if needed
    # rm -rf "\${${plugin_name^^}_DATA_DIR}"
}

# Initialize plugin when loaded
${plugin_name}_init
EOF

    chmod +x "$plugin_dir/main.sh"

    # Create README
    cat > "$plugin_dir/README.md" << EOF
# $plugin_name Plugin

## Description
Your plugin description here.

## Installation
1. Build the plugin: \`marmot plugin build $plugin_name\`
2. Install: \`marmot plugin install $plugin_name.mpkg\`

## Usage
Explain how to use your plugin.

## Configuration
Any configuration options your plugin supports.
EOF

    success "Plugin template created: $plugin_dir"
    echo "Edit the files in $plugin_dir and build with: marmot plugin build $plugin_name"
}

# Build plugin package
plugin_build() {
    local plugin_name=$1
    local plugin_dir="$MARMOT_PLUGIN_DIR/temp/$plugin_name"
    local output_file="./$plugin_name.mpkg"

    if [[ ! -d "$plugin_dir" ]]; then
        error "Plugin template not found: $plugin_dir"
        return 1
    fi

    # Validate manifest
    if [[ ! -f "$plugin_dir/manifest.json" ]]; then
        error "manifest.json not found"
        return 1
    fi

    # Create package
    tar -czf "$output_file" -C "$plugin_dir" .

    success "Plugin built: $output_file"
    echo "Install with: marmot plugin install $output_file"
}

# Plugin marketplace (placeholder)
plugin_marketplace() {
    echo "Plugin Marketplace"
    echo "=================="
    echo
    echo "Available Plugins:"
    echo "1. Docker Cleaner - Clean up Docker containers and images"
    echo "2. Game Cache Cleaner - Clean game caches and save files"
    echo "3. Development Tools Cleaner - Clean dev tool caches and temp files"
    echo "4. Media Cache Cleaner - Clean media player caches"
    echo "5. Browser Extension Manager - Manage browser extensions"
    echo
    echo "Note: Marketplace not yet implemented. Install plugins manually."
}

# Plugin development tools
plugin_dev_tools() {
    while true; do
        echo
        echo "Plugin Development Tools"
        echo "======================="
        echo "1) Create plugin template"
        echo "2) Build plugin package"
        echo "3) Test plugin"
        echo "4) List hook points"
        echo "5) Back"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                read -p "Enter plugin name: " name
                plugin_create_template "$name"
                ;;
            2)
                read -p "Enter plugin name: " name
                plugin_build "$name"
                ;;
            3)
                read -p "Enter plugin name: " name
                plugin_test "$name"
                ;;
            4)
                plugin_list_hooks
                ;;
            5)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Test plugin
plugin_test() {
    local plugin_name=$1

    if [[ -z $plugin_name ]]; then
        error "Plugin name required"
        return 1
    fi

    echo "Testing plugin: $plugin_name"
    echo "=========================="

    # Load plugin if not already loaded
    if ! declare -F "${plugin_name}_init" >/dev/null; then
        plugin_load "$plugin_name"
    fi

    # Run test functions if they exist
    if declare -F "${plugin_name}_test" >/dev/null; then
        "${plugin_name}_test"
    else
        echo "No test function found in plugin"
    fi
}

# List available hook points
plugin_list_hooks() {
    echo "Available Hook Points"
    echo "====================="
    echo "System Hooks:"
    echo "  - init: System initialization"
    echo "  - cleanup: System cleanup"
    echo ""
    echo "Cleaning Hooks:"
    echo "  - pre_clean: Before any cleaning operation"
    echo "  - post_clean: After all cleaning operations"
    echo "  - pre_clean_[app]: Before cleaning specific app"
    echo "  - post_clean_[app]: After cleaning specific app"
    echo ""
    echo "Optimization Hooks:"
    echo "  - pre_optimize: Before optimization"
    echo "  - post_optimize: After optimization"
    echo ""
    echo "Analysis Hooks:"
    echo "  - pre_analyze: Before analysis"
    echo "  - post_analyze: After analysis"
    echo ""
    echo "UI Hooks:"
    echo "  - menu_add: Add menu items"
    echo "  - status_display: Display custom status"
    echo ""
    echo "Custom Hooks:"
    echo "  - Any custom hook point can be created"
}

# Update plugin
plugin_update() {
    local plugin_name=$1
    local update_file=$2

    if [[ -z $plugin_name || -z $update_file ]]; then
        echo "Usage: plugin_update <plugin_name> <update_file>"
        return 1
    fi

    # Backup current version
    local backup_dir="$MARMOT_PLUGIN_DIR/backups/$plugin_name_$(date +%Y%m%d_%H%M%S)"
    local current_dir=$(sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT location FROM plugins WHERE name='$plugin_name';")

    if [[ -n $current_dir ]]; then
        cp -r "$current_dir" "$backup_dir"
        echo "Current version backed up to: $backup_dir"
    fi

    # Install update
    plugin_install "$update_file"

    success "Plugin updated: $plugin_name"
}

# Plugin info
plugin_info() {
    local plugin_name=$1

    if [[ -z $plugin_name ]]; then
        plugin_list
        return
    fi

    echo "Plugin Information: $plugin_name"
    echo "=============================="

    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" << EOF
.headers off

SELECT 'Name: ' || name FROM plugins WHERE name='$plugin_name';
SELECT 'Version: ' || version FROM plugins WHERE name='$plugin_name';
SELECT 'Author: ' || author FROM plugins WHERE name='$plugin_name';
SELECT 'Description: ' || description FROM plugins WHERE name='$plugin_name';
SELECT 'Category: ' || category FROM plugins WHERE name='$plugin_name';
SELECT 'Type: ' || plugin_type FROM plugins WHERE name='$plugin_name';
SELECT 'Location: ' || location FROM plugins WHERE name='$plugin_name';
SELECT 'Installed: ' || datetime(installed_at) FROM plugins WHERE name='$plugin_name';
SELECT 'Status: ' || CASE WHEN enabled THEN 'Enabled' ELSE 'Disabled' END FROM plugins WHERE name='$plugin_name';
EOF

    echo ""
    echo "Dependencies:"
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT dependency_name FROM plugin_dependencies WHERE plugin_name='$plugin_name';" | \
        while read -r dep; do
            echo "  - $dep"
        done

    echo ""
    echo "Hooks:"
    sqlite3 "$MARMOT_PLUGIN_DIR/registry.db" \
        "SELECT hook_point || ' -> ' || hook_function FROM plugin_hooks WHERE plugin_name='$plugin_name';" | \
        while read -r hook; do
            echo "  - $hook"
        done
}
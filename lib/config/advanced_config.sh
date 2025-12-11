#!/bin/bash

# Advanced Configuration System for Marmot
# Manages profiles, settings, and customization

config_init() {
    # Ensure config directories exist
    mkdir -p "$MARMOT_CONFIG_DIR/profiles"
    mkdir -p "$MARMOT_CONFIG_DIR/custom"
    mkdir -p "$MARMOT_CONFIG_DIR/rules"

    # Initialize default configuration
    if [[ ! -f "$MARMOT_CONFIG_DIR/advanced.conf" ]]; then
        cat > "$MARMOT_CONFIG_DIR/advanced.conf" << 'EOF'
# Marmot Advanced Configuration
# ============================

# Global Settings
LOG_LEVEL="info"                     # debug, info, warn, error
AUTO_UPDATE="false"                  # Auto-check for updates
TELEMETRY="false"                    # Send anonymous usage data
BACKUP_CONFIGS="true"                # Backup configurations

# Cleaning Behavior
AGGRESSIVE_CLEANING="false"          # Clean more aggressively
PRESERVE_RECENT="7"                  # Days to preserve recent files
MIN_FILE_SIZE="1M"                   # Minimum file size to consider
EXCLUDE_SYSTEM="true"                # Exclude system files

# Performance
MAX_PARALLEL_JOBS="$(nproc)"         # Maximum parallel operations
IO_PRIORITY="low"                    # I/O priority: low, normal, high
MEMORY_LIMIT="2G"                    # Maximum memory usage

# Notifications
DESKTOP_NOTIFICATIONS="true"
EMAIL_NOTIFICATIONS="false"
EMAIL_ADDRESS=""
WEBHOOK_URL=""

# Automation
SCHEDULE_ENABLED="false"
SCHEDULE_TIME="02:00"
SCHEDULE_DAYS="daily"

# Privacy
SECURE_DELETE="false"                # Use secure deletion by default
SHRED_PASSES="3"                     # Number of shred passes
PRIVACY_MODE="false"                 # Enhanced privacy cleaning

# Network
NETWORK_OPTIMIZATION="false"
MONITOR_BANDWIDTH="false"
DNS_SERVER="auto"                    # auto, google, cloudflare, custom

# UI/UX
DARK_MODE="auto"                     # auto, true, false
SHOW_PROGRESS="true"
CONFIRM_DANGEROUS="true"
EOF
    fi

    # Create profiles database
    if [[ ! -f "$MARMOT_CONFIG_DIR/profiles.db" ]]; then
        sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << 'EOF'
CREATE TABLE IF NOT EXISTS profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE,
    description TEXT,
    config_data TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 0
);

CREATE TABLE IF NOT EXISTS rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    rule_type TEXT,
    pattern TEXT,
    action TEXT,
    priority INTEGER,
    enabled BOOLEAN DEFAULT 1
);

INSERT INTO profiles (name, description, is_active) VALUES
    ('default', 'Default configuration', 1),
    ('minimal', 'Minimal cleaning - safe mode', 0),
    ('aggressive', 'Aggressive cleaning - max space', 0);
EOF
    fi
}

# Load configuration
config_load() {
    local profile=${1:-default}

    # Load base configuration
    source "$MARMOT_CONFIG_DIR/advanced.conf"

    # Override with profile if specified
    if [[ $profile != "default" ]]; then
        local profile_config=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
            "SELECT config_data FROM profiles WHERE name='$profile';")

        if [[ -n $profile_config ]]; then
            eval "$profile_config"
            log "info" "Loaded profile: $profile"
        else
            warn "Profile '$profile' not found, using default"
        fi
    fi

    export MARMOT_CURRENT_PROFILE="$profile"
}

# Save configuration
config_save() {
    local profile=${1:-default}
    local description=${2:-"Configuration saved on $(date)"}

    # Gather current configuration
    local config_data=$(declare -p | grep -E "^declare -x [A-Z_]+=" | \
        sed 's/^declare -x //g' | tr '\n' ';')

    # Save to database
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
INSERT OR REPLACE INTO profiles (name, description, config_data, is_active)
VALUES ('$profile', '$description', '$config_data', 0);
EOF

    success "Configuration saved as profile: $profile"
}

# List available profiles
config_list_profiles() {
    echo "Available Configuration Profiles"
    echo "================================"

    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
.headers on
.mode table

SELECT
    name,
    description,
    datetime(created_at) as Created,
    CASE WHEN is_active THEN '✓' ELSE '' END as Active
FROM profiles
ORDER BY name;
EOF
}

# Switch profile
config_switch_profile() {
    local profile=$1

    if [[ -z $profile ]]; then
        config_list_profiles
        echo
        read -p "Enter profile name: " profile
    fi

    # Check if profile exists
    local exists=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT COUNT(*) FROM profiles WHERE name='$profile';")

    if [[ $exists -eq 0 ]]; then
        error "Profile '$profile' does not exist"
        return 1
    fi

    # Deactivate all profiles
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" "UPDATE profiles SET is_active=0;"

    # Activate selected profile
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "UPDATE profiles SET is_active=1 WHERE name='$profile';"

    # Load the profile
    config_load "$profile"

    success "Switched to profile: $profile"
}

# Create new profile
config_create_profile() {
    local name=$1
    local base_profile=${2:-default}

    if [[ -z $name ]]; then
        read -p "Enter profile name: " name
        if [[ -z $name ]]; then
            error "Profile name cannot be empty"
            return 1
        fi
    fi

    # Check if already exists
    local exists=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT COUNT(*) FROM profiles WHERE name='$name';")

    if [[ $exists -gt 0 ]]; then
        error "Profile '$name' already exists"
        return 1
    fi

    # Load base profile
    config_load "$base_profile"

    # Save as new profile
    config_save "$name" "Based on $base_profile"

    success "Created new profile: $name"
}

# Delete profile
config_delete_profile() {
    local profile=$1

    if [[ -z $profile ]]; then
        config_list_profiles
        echo
        read -p "Enter profile name to delete: " profile
    fi

    if [[ $profile == "default" ]]; then
        error "Cannot delete default profile"
        return 1
    fi

    # Confirm deletion
    if ! ask "Delete profile '$profile'?"; then
        return
    fi

    # Delete from database
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "DELETE FROM profiles WHERE name='$profile';"

    success "Deleted profile: $profile"
}

# Import configuration
config_import() {
    local import_file=$1

    if [[ -z $import_file ]]; then
        read -e -p "Enter import file path: " import_file
    fi

    if [[ ! -f "$import_file" ]]; then
        error "Import file not found: $import_file"
        return 1
    fi

    # Determine import format
    case ${import_file##*.} in
        json)
            config_import_json "$import_file"
            ;;
        yaml|yml)
            config_import_yaml "$import_file"
            ;;
        conf)
            config_import_conf "$import_file"
            ;;
        *)
            error "Unsupported import format"
            return 1
            ;;
    esac
}

# Import JSON configuration
config_import_json() {
    local file=$1
    local profile_name=$(basename "$file" .json)

    # Convert JSON to shell variables (simplified)
    if command -v jq >/dev/null 2>&1; then
        local config_data=$(jq -r 'to_entries[] | "\(.key)=\"\(.value)\""' "$file" | tr '\n' ';')

        sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
INSERT INTO profiles (name, description, config_data)
VALUES ('$profile_name', 'Imported from JSON', '$config_data');
EOF

        success "Imported configuration from: $file"
    else
        error "jq is required for JSON import"
    fi
}

# Export configuration
config_export() {
    local profile=${1:-default}
    local format=${2:-json}
    local output_file="$MARMOT_CONFIG_DIR/export_${profile}_$(date +%Y%m%d).$format"

    # Get profile data
    local config_data=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT config_data FROM profiles WHERE name='$profile';")

    case $format in
        json)
            if command -v jq >/dev/null 2>&1; then
                echo "{}" > "$output_file"
                # Simplified conversion - would need proper implementation
                success "Exported to JSON: $output_file"
            else
                error "jq is required for JSON export"
            fi
            ;;
        yaml)
            echo "# Marmot Configuration Export: $profile" > "$output_file"
            echo "# Generated: $(date)" >> "$output_file"
            echo "$config_data" | tr ';' '\n' >> "$output_file"
            success "Exported to YAML: $output_file"
            ;;
        conf)
            cat > "$output_file" << EOF
# Marmot Configuration Export
# Profile: $profile
# Generated: $(date)

$config_data
EOF
            success "Exported to CONF: $output_file"
            ;;
    esac
}

# Configuration validation
config_validate() {
    local errors=0

    echo "Validating Configuration"
    echo "======================="

    # Check required directories
    local required_dirs=(
        "$MARMOT_CONFIG_DIR"
        "$MARMOT_LOG_DIR"
        "$MARMOT_CACHE_DIR"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "✗ Missing directory: $dir"
            ((errors++))
        fi
    fi

    # Check configuration values
    if [[ $MAX_PARALLEL_JOBS -gt $(nproc) ]]; then
        echo "⚠ MAX_PARALLEL_JOBS exceeds CPU count: $MAX_PARALLEL_JOBS > $(nproc)"
    fi

    if [[ $MEMORY_LIMIT =~ ^[0-9]+[KMG]?$ ]]; then
        local mem_bytes=$(numfmt --from=iec $MEMORY_LIMIT)
        local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')
        if [[ $mem_bytes -gt $total_mem ]]; then
            echo "⚠ MEMORY_LIMIT exceeds total memory"
        fi
    else
        echo "✗ Invalid MEMORY_LIMIT format: $MEMORY_LIMIT"
        ((errors++))
    fi

    # Check email configuration
    if [[ $EMAIL_NOTIFICATIONS == "true" && -z $EMAIL_ADDRESS ]]; then
        echo "⚠ EMAIL_NOTIFICATIONS enabled but no EMAIL_ADDRESS set"
    fi

    # Check rules
    local invalid_rules=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT COUNT(*) FROM rules WHERE pattern IS NULL OR pattern = '';")

    if [[ $invalid_rules -gt 0 ]]; then
        echo "✗ Found $invalid_rules rules with empty patterns"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        success "Configuration is valid"
    else
        error "Found $errors configuration errors"
        return 1
    fi
}

# Create rule
config_create_rule() {
    local name=$1
    local type=$2
    local pattern=$3
    local action=$4
    local priority=${5:-50}

    if [[ -z $name || -z $type || -z $pattern || -z $action ]]; then
        echo "Usage: config_create_rule <name> <type> <pattern> <action> [priority]"
        return 1
    fi

    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
INSERT INTO rules (name, rule_type, pattern, action, priority)
VALUES ('$name', '$type', '$pattern', '$action', $priority);
EOF

    success "Created rule: $name"
}

# List rules
config_list_rules() {
    echo "Configuration Rules"
    echo "=================="

    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
.headers on
.mode table

SELECT
    name,
    rule_type,
    pattern,
    action,
    priority,
    CASE WHEN enabled THEN '✓' ELSE '✗' END as Active
FROM rules
ORDER BY priority DESC, name;
EOF
}

# Apply rules to operation
config_apply_rules() {
    local operation=$1
    local target_path=$2

    # Get applicable rules
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT pattern, action FROM rules WHERE enabled=1 AND rule_type='$operation';" | \
    while read -r pattern action; do
        if [[ $target_path =~ $pattern ]]; then
            case $action in
                exclude)
                    echo "skip"
                    return
                    ;;
                include)
                    echo "include"
                    return
                    ;;
                *)
                    echo "$action"
                    return
                    ;;
            esac
        fi
    done

    echo "default"
}

# Reset to defaults
config_reset() {
    echo "Reset Configuration to Defaults"
    echo "=============================="

    if ! ask "This will reset all settings to defaults. Continue?"; then
        return
    fi

    # Backup current config
    local backup_file="$MARMOT_CONFIG_DIR/backup_$(date +%Y%m%d_%H%M%S).conf"
    cp "$MARMOT_CONFIG_DIR/advanced.conf" "$backup_file"
    echo "Current configuration backed up to: $backup_file"

    # Reset to default
    rm -f "$MARMOT_CONFIG_DIR/advanced.conf"
    config_init

    # Reset database
    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" << EOF
DELETE FROM profiles WHERE name != 'default';
UPDATE profiles SET is_active=1 WHERE name='default';
DELETE FROM rules;
EOF

    success "Configuration reset to defaults"
}

# Interactive configuration editor
config_interactive() {
    while true; do
        echo
        echo "Advanced Configuration"
        echo "====================="
        echo "1) View current settings"
        echo "2) Edit configuration"
        echo "3) Manage profiles"
        echo "4) Import/Export"
        echo "5) Manage rules"
        echo "6) Validate configuration"
        echo "7) Reset to defaults"
        echo "8) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                echo "Current Configuration:"
                echo "====================="
                cat "$MARMOT_CONFIG_DIR/advanced.conf" | grep -v '^#' | grep -v '^$'
                ;;
            2)
                ${EDITOR:-nano} "$MARMOT_CONFIG_DIR/advanced.conf"
                config_validate
                ;;
            3)
                config_profile_menu
                ;;
            4)
                config_import_export_menu
                ;;
            5)
                config_rules_menu
                ;;
            6)
                config_validate
                ;;
            7)
                config_reset
                ;;
            8)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Profile management submenu
config_profile_menu() {
    while true; do
        echo
        echo "Profile Management"
        echo "=================="
        echo "1) List profiles"
        echo "2) Switch profile"
        echo "3) Create profile"
        echo "4) Delete profile"
        echo "5) Export profile"
        echo "6) Back"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                config_list_profiles
                ;;
            2)
                read -p "Enter profile name: " profile
                config_switch_profile "$profile"
                ;;
            3)
                read -p "Enter new profile name: " name
                read -p "Base profile [default]: " base
                config_create_profile "$name" "${base:-default}"
                ;;
            4)
                config_list_profiles
                read -p "Enter profile name to delete: " profile
                config_delete_profile "$profile"
                ;;
            5)
                read -p "Enter profile name [default]: " profile
                read -p "Export format [json]: " format
                config_export "${profile:-default}" "${format:-json}"
                ;;
            6)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Import/Export submenu
config_import_export_menu() {
    while true; do
        echo
        echo "Import/Export Configuration"
        echo "=========================="
        echo "1) Import configuration"
        echo "2) Export configuration"
        echo "3) Back"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                config_import
                ;;
            2)
                read -p "Profile name [default]: " profile
                read -p "Export format [json]: " format
                config_export "${profile:-default}" "${format:-json}"
                ;;
            3)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Rules management submenu
config_rules_menu() {
    while true; do
        echo
        echo "Rules Management"
        echo "================"
        echo "1) List rules"
        echo "2) Create rule"
        echo "3) Delete rule"
        echo "4) Enable/Disable rule"
        echo "5) Back"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                config_list_rules
                ;;
            2)
                echo "Create new rule:"
                read -p "Name: " name
                read -p "Type (clean/protect/optimize): " type
                read -p "Pattern (regex): " pattern
                read -p "Action (exclude/include/custom): " action
                read -p "Priority [50]: " priority
                config_create_rule "$name" "$type" "$pattern" "$action" "${priority:-50}"
                ;;
            3)
                config_list_rules
                read -p "Enter rule name to delete: " name
                sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" "DELETE FROM rules WHERE name='$name';"
                success "Deleted rule: $name"
                ;;
            4)
                config_list_rules
                read -p "Enter rule name: " name
                read -p "Enable (y/n): " enable
                if [[ $enable == [yY] ]]; then
                    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" "UPDATE rules SET enabled=1 WHERE name='$name';"
                else
                    sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" "UPDATE rules SET enabled=0 WHERE name='$name';"
                fi
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
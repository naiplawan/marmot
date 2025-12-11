#!/bin/bash
# System Configuration Maintenance Module (Cross-platform)
# Fix broken preferences and broken login items

set -euo pipefail

# ============================================================================
# Platform Detection
# ============================================================================

is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

# ============================================================================
# XDG Base Directory Support (Linux)
# ============================================================================

# Get XDG config directory with fallback
get_xdg_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# ============================================================================
# Broken Preferences Detection and Cleanup
# Find and remove corrupted .plist files
# ============================================================================

# Clean broken preference files
# Uses plutil -lint on macOS, checks for malformed config files on Linux
# Returns: count of broken files fixed
fix_broken_preferences() {
    local broken_count=0

    if is_macos; then
        local prefs_dir="$HOME/Library/Preferences"
        [[ -d "$prefs_dir" ]] || return 0

        # Check main preferences directory
        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue

            # Skip system preferences
            local filename
            filename=$(basename "$plist_file")
            case "$filename" in
                com.apple.* | .GlobalPreferences* | loginwindow.plist)
                    continue
                    ;;
            esac

            # Validate plist using plutil
            plutil -lint "$plist_file" > /dev/null 2>&1 && continue

            # Remove broken plist
            rm -f "$plist_file" 2> /dev/null || true
            ((broken_count++))
        done < <(command find "$prefs_dir" -maxdepth 1 -name "*.plist" -type f 2> /dev/null || true)

        # Check ByHost preferences with timeout protection
        local byhost_dir="$prefs_dir/ByHost"
        if [[ -d "$byhost_dir" ]]; then
            while IFS= read -r plist_file; do
                [[ -f "$plist_file" ]] || continue

                local filename
                filename=$(basename "$plist_file")
                case "$filename" in
                    com.apple.* | .GlobalPreferences*)
                        continue
                        ;;
                esac

                plutil -lint "$plist_file" > /dev/null 2>&1 && continue

                rm -f "$plist_file" 2> /dev/null || true
                ((broken_count++))
            done < <(command find "$byhost_dir" -name "*.plist" -type f 2> /dev/null || true)
        fi
    else
        # Linux: Check for broken configuration files
        local xdg_config=$(get_xdg_config_dir)

        # Check for malformed JSON files
        while IFS= read -r json_file; do
            [[ -f "$json_file" ]] || continue

            # Validate JSON using python or jq if available
            if command -v python3 > /dev/null 2>&1; then
                python3 -c "import json; json.load(open('$json_file'))" 2> /dev/null && continue
            elif command -v jq > /dev/null 2>&1; then
                jq . "$json_file" > /dev/null 2>&1 && continue
            else
                # No validation tool available, skip
                continue
            fi

            # Move broken file with .broken extension instead of deleting
            mv "$json_file" "$json_file.broken" 2> /dev/null || true
            ((broken_count++))
        done < <(find "$xdg_config" -name "*.json" -type f 2> /dev/null || true)

        # Check for malformed XML files
        while IFS= read -r xml_file; do
            [[ -f "$xml_file" ]] || continue

            # Validate XML using xmllint if available
            if command -v xmllint > /dev/null 2>&1; then
                xmllint --noout "$xml_file" 2> /dev/null && continue
            else
                # No validation tool available, skip
                continue
            fi

            mv "$xml_file" "$xml_file.broken" 2> /dev/null || true
            ((broken_count++))
        done < <(find "$xdg_config" -name "*.xml" -type f 2> /dev/null || true)

        # Check for malformed INI/config files (basic syntax check)
        while IFS= read -r config_file; do
            [[ -f "$config_file" ]] || continue

            # Skip binary files
            file "$config_file" | grep -q "text" || continue

            # Basic INI syntax check
            python3 -c "
import configparser
try:
    configparser.ConfigParser().read('$config_file')
except:
    exit(1)
" 2> /dev/null && continue

            mv "$config_file" "$config_file.broken" 2> /dev/null || true
            ((broken_count++))
        done < <(find "$xdg_config" \( -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.toml" \) -type f 2> /dev/null || true)
    fi

    echo "$broken_count"
}

# ============================================================================
# Broken Login Items Cleanup
# Find and remove login items pointing to non-existent files
# ============================================================================

# Clean broken login items (LaunchAgents on macOS, systemd/autostart on Linux)
# Returns: count of broken items fixed
fix_broken_login_items() {
    local broken_count=0

    if is_macos; then
        local launch_agents_dir="$HOME/Library/LaunchAgents"
        [[ -d "$launch_agents_dir" ]] || return 0

        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue

            # Skip system items
            local filename
            filename=$(basename "$plist_file")
            case "$filename" in
                com.apple.*)
                    continue
                    ;;
            esac

            # Extract Program or ProgramArguments[0] from plist using plutil
            local program=""
            program=$(plutil -extract Program raw "$plist_file" 2> /dev/null || echo "")

            if [[ -z "$program" ]]; then
                # Try ProgramArguments array (first element)
                program=$(plutil -extract ProgramArguments.0 raw "$plist_file" 2> /dev/null || echo "")
            fi

            # Skip if no program found or program exists
            [[ -z "$program" ]] && continue
            [[ -e "$program" ]] && continue

            # Program doesn't exist - this is a broken login item
            launchctl unload "$plist_file" 2> /dev/null || true
            rm -f "$plist_file" 2> /dev/null || true
            ((broken_count++))
        done < <(command find "$launch_agents_dir" -name "*.plist" -type f 2> /dev/null || true)
    else
        # Linux: Check various autostart mechanisms

        # Check systemd user services
        if command -v systemctl > /dev/null 2>&1; then
            while IFS= read -r service_file; do
                [[ -f "$service_file" ]] || continue

                # Skip if not enabled
                systemctl --user is-enabled "$(basename "$service_file" .service)" 2>/dev/null || continue

                # Extract ExecStart from service file
                local program=""
                program=$(grep -E "^ExecStart=" "$service_file" | head -1 | cut -d'=' -f2- | awk '{print $1}' || true)

                # Skip if no program found or program exists
                [[ -z "$program" ]] && continue
                [[ -e "$program" ]] && continue

                # Disable and remove broken service
                systemctl --user disable "$(basename "$service_file" .service)" 2>/dev/null || true
                rm -f "$service_file" 2> /dev/null || true
                ((broken_count++))
            done < <(find "$HOME/.config/systemd/user" -name "*.service" -type f 2> /dev/null || true)
        fi

        # Check XDG autostart .desktop files
        local autostart_dir="$HOME/.config/autostart"
        if [[ -d "$autostart_dir" ]]; then
            while IFS= read -r desktop_file; do
                [[ -f "$desktop_file" ]] || continue

                # Extract Exec from desktop file
                local program=""
                program=$(grep -E "^Exec=" "$desktop_file" | head -1 | cut -d'=' -f2- | awk '{print $1}' || true)

                # Handle special cases (e.g., env variables)
                if [[ "$program" =~ ^env ]]; then
                    program=$(echo "$program" | awk '{print $NF}')
                fi

                # Skip if no program found or program exists
                [[ -z "$program" ]] && continue
                [[ -e "$program" ]] && continue

                # Move broken desktop file
                mv "$desktop_file" "$desktop_file.broken" 2> /dev/null || true
                ((broken_count++))
            done < <(find "$autostart_dir" -name "*.desktop" -type f 2> /dev/null || true)
        fi

        # Check old-style autostart scripts
        local autostart_scripts=(
            "$HOME/.config/autostart-scripts"
            "$HOME/.config/autostart"
            "$HOME/.config/autostart"
        )

        for script_dir in "${autostart_scripts[@]}"; do
            [[ -d "$script_dir" ]] || continue

            while IFS= read -r script_file; do
                [[ -f "$script_file" ]] || continue
                [[ -x "$script_file" ]] || continue

                # Move non-executable or broken scripts
                mv "$script_file" "$script_file.broken" 2> /dev/null || true
                ((broken_count++))
            done < <(find "$script_dir" -type f 2> /dev/null || true)
        done

        # Check .profile, .bashrc, .zshrc for broken autostart commands
        local shell_configs=(
            "$HOME/.profile"
            "$HOME/.bash_profile"
            "$HOME/.bashrc"
            "$HOME/.zshrc"
            "$HOME/.config/fish/config.fish"
        )

        for config_file in "${shell_configs[@]}"; do
            [[ -f "$config_file" ]] || continue

            # Check for common autostart patterns that might be broken
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line// }" ]] && continue

                # Look for potential autostart commands
                if [[ "$line" =~ ^(exec|start|run)[[:space:]]+ ]]; then
                    local program=$(echo "$line" | awk '{print $2}')

                    # Skip if program exists
                    [[ -e "$program" ]] && continue

                    # Comment out broken autostart line
                    sed -i.bak "s|$(printf '%s\n' "$line" | sed 's/[[\.*^$()+?{|]/\\&/g')|# BROKEN: &|g" "$config_file" 2>/dev/null || true
                    ((broken_count++))
                fi
            done < <(grep -E "^(exec|start|run)" "$config_file" 2>/dev/null || true)
        done
    fi

    echo "$broken_count"
}

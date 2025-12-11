#!/bin/bash
# Application Data Cleanup Module (Cross-platform)

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
# macOS-specific Functions
# ============================================================================

# Clean .DS_Store (Finder metadata), home uses maxdepth 5, excludes slow paths, max 500 files
# Args: $1=target_dir, $2=label
clean_ds_store_tree() {
    # Skip on Linux
    is_macos || return 0

    local target="$1"
    local label="$2"

    [[ -d "$target" ]] || return 0

    local file_count=0
    local total_bytes=0
    local spinner_active="false"

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  "
        start_inline_spinner "Cleaning Finder metadata..."
        spinner_active="true"
    fi

    # Build exclusion paths for find (skip common slow/large directories)
    local -a exclude_paths=(
        -path "*/Library/Application Support/MobileSync" -prune -o
        -path "*/Library/Developer" -prune -o
        -path "*/.Trash" -prune -o
        -path "*/node_modules" -prune -o
        -path "*/.git" -prune -o
        -path "*/Library/Caches" -prune -o
    )

    # Build find command to avoid unbound array expansion with set -u
    local -a find_cmd=("command" "find" "$target")
    if [[ "$target" == "$HOME" ]]; then
        find_cmd+=("-maxdepth" "5")
    fi
    find_cmd+=("${exclude_paths[@]}" "-type" "f" "-name" ".DS_Store" "-print0")

    # Find .DS_Store files with exclusions and depth limit
    while IFS= read -r -d '' ds_file; do
        local size
        size=$(get_file_size "$ds_file")
        total_bytes=$((total_bytes + size))
        ((file_count++))
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -f "$ds_file" 2> /dev/null || true
        fi

        # Stop after 500 files to avoid hanging
        if [[ $file_count -ge 500 ]]; then
            break
        fi
    done < <("${find_cmd[@]}" 2> /dev/null || true)

    if [[ "$spinner_active" == "true" ]]; then
        stop_inline_spinner
        echo -ne "\r\033[K"
    fi

    if [[ $file_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human "$total_bytes")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} $label ${YELLOW}($file_count files, $size_human dry)${NC}"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $label ${GREEN}($file_count files, $size_human)${NC}"
        fi

        local size_kb=$(((total_bytes + 1023) / 1024))
        ((files_cleaned += file_count))
        ((total_size_cleaned += size_kb))
        ((total_items++))
        note_activity
    fi
}

# Clean data for uninstalled apps (macOS only)
# Protects system apps, major vendors, scans /Applications+running processes
# Max 100 items/pattern, 2s du timeout. Env: ORPHAN_AGE_THRESHOLD, DRY_RUN
clean_orphaned_app_data_macos() {
    # Quick permission check - if we can't access Library folders, skip
    if ! ls "$HOME/Library/Caches" > /dev/null 2>&1; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Skipped: No permission to access Library folders"
        return 0
    fi

    # Build list of installed/active apps
    local installed_bundles=$(create_temp_file)

    # Scan all Applications directories
    local -a app_dirs=(
        "/Applications"
        "/System/Applications"
        "$HOME/Applications"
    )

    # Create a temp dir for parallel results to avoid write contention
    local scan_tmp_dir=$(create_temp_dir)
    local -a pids=()

    # Scan apps in parallel (faster than sequential)
    for app_dir in "${app_dirs[@]}"; do
        [[ -d "$app_dir" ]] || continue
        (
            # Extract bundle IDs from app Info.plist files
            find "$app_dir" -maxdepth 3 -name "Info.plist" -exec defaults read {} CFBundleIdentifier 2> /dev/null \; 2> /dev/null | sort -u
        ) > "$scan_tmp_dir/$(basename "$app_dir").bundles" &
        pids+=($!)
    done

    # Wait for all scans
    for pid in "${pids[@]}"; do
        wait "$pid" 2> /dev/null || true
    done

    # Combine results
    cat "$scan_tmp_dir"/*.bundles 2> /dev/null | sort -u > "$installed_bundles"

    # Get running process names for active app detection
    local running_processes=$(create_temp_file)
    ps -e -o comm= | awk '{print $1}' | sort -u > "$running_processes" 2> /dev/null || true

    # Add major vendor patterns to protect
    local -a protected_patterns=(
        # Apple system apps
        "com.apple."
        # Microsoft
        "com.microsoft."
        # Adobe
        "com.adobe."
        # Google
        "com.google."
        # JetBrains
        "com.jetbrains."
        # Mozilla
        "org.mozilla."
        # Valve
        "com.valvesoftware."
        # Epic Games
        "com.epicgames."
        # Other major vendors
        "com.spotify."
        "com.skype."
        "com.spotify."
        "com.spotify.client"
        "com.valvesoftware.steam"
    )

    # Set age threshold (default: 60 days)
    local age_days="${ORPHAN_AGE_THRESHOLD:-60}"
    local threshold_seconds=$((age_days * 86400))

    # Clean up orphaned data
    local cleaned_size=0
    local cleaned_count=0

    # Check Library/Application Support
    local -a search_dirs=(
        "$HOME/Library/Application Support"
        "$HOME/Library/Caches"
        "$HOME/Library/Preferences"
        "$HOME/Library/Saved Application State"
        "$HOME/Library/WebKit"
    )

    for search_dir in "${search_dirs[@]}"; do
        [[ -d "$search_dir" ]] || continue

        marmot_SPINNER_PREFIX="  "
        start_inline_spinner "Scanning $(basename "$search_dir")..."

        # Process each directory
        while IFS= read -r -d '' item; do
            [[ -e "$item" ]] || continue

            # Skip if item is recently modified
            local mtime
            mtime=$(get_path_mtime "$item")
            if [[ $((current_time - mtime)) -lt $threshold_seconds ]]; then
                continue
            fi

            local basename_item
            basename_item=$(basename "$item")

            # Check if protected
            local is_protected=false
            for pattern in "${protected_patterns[@]}"; do
                if [[ "$basename_item" == "$pattern"* ]]; then
                    is_protected=true
                    break
                fi
            done

            # Skip if protected
            [[ "$is_protected" == "true" ]] && continue

            # Check if app is installed or running
            local is_installed=false
            if grep -q "^$basename_item$" "$installed_bundles" 2> /dev/null; then
                is_installed=true
            elif grep -q "^$basename_item$" "$running_processes" 2> /dev/null; then
                is_installed=true
            fi

            # Clean if not installed
            if [[ "$is_installed" == "false" ]]; then
                local size
                size=$(run_with_timeout 2 get_path_size_kb "$item")
                if [[ "$size" -gt 0 ]]; then
                    if [[ "$DRY_RUN" != "true" ]]; then
                        safe_remove "$item" true && {
                            ((cleaned_size += size))
                            ((cleaned_count++))
                        }
                    else
                        ((cleaned_size += size))
                    fi
                fi
            fi
        done < <(find "$search_dir" -maxdepth 1 -type d -print0 2> /dev/null || true)

        stop_inline_spinner
    done

    # Report results
    if [[ $cleaned_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human $((cleaned_size * 1024)))
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Orphaned app data (${cleaned_count} items, $size_human dry)"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Orphaned app data (${cleaned_count} items, $size_human)"
        fi

        ((files_cleaned += cleaned_count))
        ((total_size_cleaned += cleaned_size))
        ((total_items++))
        note_activity
    fi
}

# ============================================================================
# Linux-specific Functions
# ============================================================================

# Clean desktop files and Linux-specific junk
clean_linux_desktop_files() {
    # Skip on Linux
    is_linux || return 0

    local file_count=0
    local total_bytes=0

    # Clean .desktop files in user applications directory
    local desktop_dirs=(
        "$HOME/.local/share/applications"
        "/usr/share/applications"
    )

    for desktop_dir in "${desktop_dirs[@]}"; do
        [[ -d "$desktop_dir" ]] || continue

        # Find broken desktop files (point to non-existent binaries)
        while IFS= read -r desktop_file; do
            [[ -f "$desktop_file" ]] || continue

            # Extract Exec= line and check if binary exists
            local exec_line
            exec_line=$(grep "^Exec=" "$desktop_file" | head -1 || echo "")
            if [[ -n "$exec_line" ]]; then
                # Extract executable name (first word after Exec=)
                local exec_path
                exec_path=$(echo "$exec_line" | cut -d'=' -f2- | cut -d' ' -f1)

                # Skip if it looks like a full path that exists
                if [[ "$exec_path" == /* && -x "$exec_path" ]]; then
                    continue
                fi

                # Check if command exists in PATH
                if ! command -v "$exec_path" > /dev/null 2>&1; then
                    local size
                    size=$(get_file_size "$desktop_file")
                    total_bytes=$((total_bytes + size))
                    ((file_count++))
                    if [[ "$DRY_RUN" != "true" ]]; then
                        rm -f "$desktop_file" 2> /dev/null || true
                    fi
                fi
            fi
        done < <(find "$desktop_dir" -maxdepth 1 -name "*.desktop" -print0 2> /dev/null)
    done

    # Clean .Desktop directories (common on Linux desktops)
    local desktop_files=(
        "$HOME/Desktop"
        "$HOME/.local/share/desktop"
    )

    for desktop_path in "${desktop_files[@]}"; do
        [[ -d "$desktop_path" ]] || continue

        # Clean .lnk files (KDE desktop links)
        while IFS= read -r link_file; do
            [[ -f "$link_file" && "$link_file" == *.lnk ]] || continue

            # Check if target exists
            local target
            target=$(readlink "$link_file" 2> /dev/null || echo "")
            if [[ -n "$target" && ! -e "$target" ]]; then
                local size
                size=$(get_file_size "$link_file")
                total_bytes=$((total_bytes + size))
                ((file_count++))
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$link_file" 2> /dev/null || true
                fi
            fi
        done < <(find "$desktop_path" -maxdepth 1 -name "*.lnk" -print0 2> /dev/null)

        # Clean broken shortcuts (common on some desktops)
        while IFS= read -r shortcut_file; do
            [[ -f "$shortcut_file" && "$shortcut_file" == *.desktop ]] || continue

            # Check if the .desktop file is valid
            if ! grep -q "^Exec=" "$shortcut_file" 2> /dev/null; then
                local size
                size=$(get_file_size "$shortcut_file")
                total_bytes=$((total_bytes + size))
                ((file_count++))
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$shortcut_file" 2> /dev/null || true
                fi
            fi
        done < <(find "$desktop_path" -maxdepth 1 -name "*.desktop" -print0 2> /dev/null)
    done

    # Clean autostart files for removed apps
    local autostart_dirs=(
        "$HOME/.config/autostart"
        "/etc/xdg/autostart"
    )

    for autostart_dir in "${autostart_dirs[@]}"; do
        [[ -d "$autostart_dir" ]] || continue

        # Skip /etc if not root
        [[ "$autostart_dir" == "/etc/xdg/autostart" && "$(id -u)" -ne 0 ]] && continue

        while IFS= read -r autostart_file; do
            [[ -f "$autostart_file" ]] || continue

            # Extract Exec= line and check if binary exists
            local exec_line
            exec_line=$(grep "^Exec=" "$autostart_file" | head -1 || echo "")
            if [[ -n "$exec_line" ]]; then
                local exec_path
                exec_path=$(echo "$exec_line" | cut -d'=' -f2- | cut -d' ' -f1)

                # Check if command exists
                if ! command -v "$exec_path" > /dev/null 2>&1; then
                    local size
                    size=$(get_file_size "$autostart_file")
                    total_bytes=$((total_bytes + size))
                    ((file_count++))
                    if [[ "$DRY_RUN" != "true" ]]; then
                        rm -f "$autostart_file" 2> /dev/null || true
                    fi
                fi
            fi
        done < <(find "$autostart_dir" -maxdepth 1 -name "*.desktop" -print0 2> /dev/null)
    done

    # Report results
    if [[ $file_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human "$total_bytes")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Broken desktop files ($file_count files, $size_human dry)"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Broken desktop files ($file_count files, $size_human)"
        fi

        ((files_cleaned += file_count))
        ((total_size_cleaned += (total_bytes / 1024)))
        ((total_items++))
        note_activity
    fi
}

# Clean package manager debris (Linux only)
clean_package_debris() {
    # Skip on Linux
    is_linux || return 0

    local cleaned_size=0
    local cleaned_count=0

    # Clean dpkg temporary files
    local dpkg_tmp_files=(
        "/var/lib/dpkg/updates/*"
        "/var/lib/dpkg/info/*-templates"
        "/var/lib/dpkg/triggers/Locked"
    )

    for pattern in "${dpkg_tmp_files[@]}"; do
        for file in $pattern; do
            [[ -e "$file" ]] || continue
            local size
            size=$(get_path_size_kb "$file")
            if [[ "$size" -gt 0 ]]; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    safe_remove "$file" true && {
                        ((cleaned_size += size))
                        ((cleaned_count++))
                    }
                else
                    ((cleaned_size += size))
                fi
            fi
        done
    done

    # Clean old kernel packages if root
    if [[ "$(id -u)" -eq 0 ]]; then
        if command -v apt > /dev/null 2>&1; then
            # Remove old kernel packages (keep current + 2 previous)
            local current_kernel
            current_kernel=$(uname -r | cut -d- -f1)
            if [[ "$DRY_RUN" != "true" ]]; then
                # List and remove old kernel packages
                apt list --installed | grep -E "linux-image-.*-[0-9]" | \
                    awk '{print $1}' | grep -v "$current_kernel" | \
                    head -n -3 | while read -r pkg; do
                        apt-get remove "$pkg" -y 2> /dev/null || true
                    done > /dev/null 2>&1
            fi
        fi
    fi

    # Report results
    if [[ $cleaned_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human $((cleaned_size * 1024)))
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Package debris ($cleaned_count items, $size_human dry)"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Package debris ($cleaned_count items, $size_human)"
        fi

        ((files_cleaned += cleaned_count))
        ((total_size_cleaned += cleaned_size))
        ((total_items++))
        note_activity
    fi
}

# Clean temporary files (cross-platform)
clean_temp_files() {
    local cleaned_size=0
    local cleaned_count=0

    # Determine temp directories based on platform
    local -a temp_dirs=()
    if is_macos; then
        temp_dirs=(
            "$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileListApplication"
            "$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileListApplication"
            "/tmp"
            "/var/tmp"
        )
    else
        temp_dirs=(
            "/tmp"
            "/var/tmp"
            "$HOME/.cache/tmp"
            "$HOME/.local/share/Trash"
            "$HOME/.local/share/Trash/files"
        )
    fi

    # Common temp file patterns
    local -a temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.swp"
        "*.swo"
        "*.bak"
        "*~"
        ".#*"
        "#*#"
        ".DS_Store"  # macOS but handled elsewhere
        "Thumbs.db"  # Windows but can appear on WSL
        "desktop.ini"
    )

    for temp_dir in "${temp_dirs[@]}"; do
        [[ -d "$temp_dir" ]] || continue

        # Skip system temp directories if not root
        [[ "$temp_dir" == "/var/tmp" || "$temp_dir" == "/tmp" ]] && [[ "$(id -u)" -ne 0 ]] && continue

        for pattern in "${temp_patterns[@]}"; do
            while IFS= read -r -d '' temp_file; do
                [[ -f "$temp_file" ]] || continue

                # Skip important files
                case "$(basename "$temp_file")" in
                    ".Xauthority"|".ICEauthority"|".X0-lock"|"Xtts-lock"|"gpg-agent.info"|"ssh-agent.sock"|".bash_history"|".zsh_history")
                        continue
                        ;;
                esac

                local size
                size=$(get_file_size "$temp_file")
                if [[ "$size" -gt 0 ]]; then
                    if [[ "$DRY_RUN" != "true" ]]; then
                        rm -f "$temp_file" 2> /dev/null || true
                    fi
                    ((cleaned_size += size))
                    ((cleaned_count++))
                fi

                # Limit to prevent excessive cleaning
                if [[ $cleaned_count -ge 1000 ]]; then
                    break 2
                fi
            done < <(find "$temp_dir" -maxdepth 2 -name "$pattern" -print0 2> /dev/null)
        done
    done

    # Report results
    if [[ $cleaned_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human "$cleaned_size")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Temporary files ($cleaned_count files, $size_human dry)"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Temporary files ($cleaned_count files, $size_human)"
        fi

        ((files_cleaned += cleaned_count))
        ((total_size_cleaned += (cleaned_size / 1024)))
        ((total_items++))
        note_activity
    fi
}

# ============================================================================
# Cross-platform Wrapper Functions
# ============================================================================

# Clean data for uninstalled apps (cross-platform wrapper)
clean_orphaned_app_data() {
    if is_macos; then
        clean_orphaned_app_data_macos
    else
        # Linux doesn't have the same orphaned app issue with bundle IDs
        # But we can clean broken desktop files and package debris
        clean_linux_desktop_files
        clean_package_debris
    fi
}

# Main function to clean application-related junk files
clean_app_junk_files() {
    # Clean .DS_Store on Linux
    clean_ds_store_tree "$HOME" "Home folder .DS_Store"

    # Clean orphaned app data
    clean_orphaned_app_data

    # Clean temporary files
    clean_temp_files

    # Clean trash (if exists and not system trash)
    if [[ -d "$HOME/.Trash" && "$HOME/.Trash" != "/.Trashes" ]]; then
        local size
        size=$(get_path_size_kb "$HOME/.Trash")
        if [[ "$size" -gt 0 ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                safe_remove "$HOME/.Trash"/* true || true
            fi
            local size_human
            size_human=$(bytes_to_human $((size * 1024)))
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "  ${YELLOW}→${NC} User trash ($size_human dry)"
            else
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} User trash ($size_human)"
            fi
            note_activity
        fi
    fi
}

# Legacy function names for backward compatibility
# These were renamed for clarity but old code might still call them
clean_orphaned_app_support() { clean_orphaned_app_data "$@"; }
clean_ds_store() { clean_ds_store_tree "$HOME" "Home folder .DS_Store"; }

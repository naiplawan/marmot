#!/bin/bash
# Optimization Tasks (Cross-platform)

set -euo pipefail

# ============================================================================
# Platform Detection
# ============================================================================

is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]
}

# ============================================================================
# XDG Base Directory Support (Linux)
# ============================================================================

# Get XDG cache directory with fallback
get_xdg_cache_dir() {
    echo "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Get XDG data directory with fallback
get_xdg_data_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# Get XDG config directory with fallback
get_xdg_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# System maintenance: rebuild databases and flush caches
opt_system_maintenance() {
    if is_macos; then
        echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding LaunchServices database..."
        run_with_timeout 10 /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user > /dev/null 2>&1 || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} LaunchServices database rebuilt"

        echo -e "${BLUE}${ICON_ARROW}${NC} Clearing DNS cache..."
        if sudo dscacheutil -flushcache 2> /dev/null && sudo killall -HUP mDNSResponder 2> /dev/null; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} DNS cache cleared"
        else
            echo -e "${RED}${ICON_ERROR}${NC} Failed to clear DNS cache"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Clearing memory cache..."
        if sudo purge 2> /dev/null; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Memory cache cleared"
        else
            echo -e "${RED}${ICON_ERROR}${NC} Failed to clear memory"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding Spotlight index (runs in background)..."
        local md_status
        md_status=$(mdutil -s / 2> /dev/null || echo "")
        if echo "$md_status" | grep -qi "Indexing disabled"; then
            echo -e "${GRAY}-${NC} Spotlight indexing disabled, skipping rebuild"
        else
            # mdutil triggers background indexing - don't wait
            run_with_timeout 10 sudo mdutil -E / > /dev/null 2>&1 || true
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Spotlight rebuild initiated"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing Bluetooth services..."
        sudo pkill -f blued 2> /dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Bluetooth controller refreshed"
    else
        # Linux system maintenance
        echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding application database..."
        # Update desktop database
        if command -v update-desktop-database > /dev/null 2>&1; then
            update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true
        fi
        # Update mime database
        if command -v update-mime-database > /dev/null 2>&1; then
            update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
        fi
        # Rebuild icon cache
        if command -v gtk-update-icon-cache > /dev/null 2>&1; then
            gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons" 2>/dev/null || true
        fi
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Application databases rebuilt"

        echo -e "${BLUE}${ICON_ARROW}${NC} Clearing DNS cache..."
        # Clear systemd-resolved cache
        if command -v resolvectl > /dev/null 2>&1 && resolvectl status > /dev/null 2>&1; then
            resolvectl flush-caches > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} DNS cache cleared"
        # Clear NetworkManager cache
        elif systemctl is-active NetworkManager > /dev/null 2>&1; then
            nmcli general reload > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} DNS cache cleared"
        # Clear dnsmasq cache
        elif pgrep dnsmasq > /dev/null 2>&1; then
            sudo killall -HUP dnsmasq > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} DNS cache cleared"
        else
            echo -e "${GRAY}-${NC} No DNS cache service found"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Clearing page cache..."
        # Clear page cache, dentries and inodes (safe operation)
        if [[ "$(id -u)" -eq 0 ]]; then
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo -e "${GREEN}${ICON_SUCCESS}${NC} Memory cache cleared"
        else
            echo -e "${YELLOW}!${NC} Requires root to clear memory cache"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing font cache..."
        # Rebuild font cache
        if command -v fc-cache > /dev/null 2>&1; then
            fc-cache -f -v > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} Font cache rebuilt"
        else
            echo -e "${GRAY}-${NC} Font cache utility not found"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing Bluetooth services..."
        # Restart bluetooth service
        if systemctl is-active bluetooth > /dev/null 2>&1; then
            sudo systemctl restart bluetooth > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} Bluetooth service refreshed"
        else
            echo -e "${GRAY}-${NC} Bluetooth service not active"
        fi

        echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing systemd user services..."
        # Reload systemd user daemon
        if command -v systemctl > /dev/null 2>&1; then
            systemctl --user daemon-reload > /dev/null 2>&1 && echo -e "${GREEN}${ICON_SUCCESS}${NC} User services reloaded"
        fi
    fi
}

# Cache refresh: update Finder/Safari caches
opt_cache_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Quick Look cache..."
    qlmanage -r cache > /dev/null 2>&1 || true
    qlmanage -r > /dev/null 2>&1 || true

    local -a cache_targets=(
        "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache|Quick Look thumbnails"
        "$HOME/Library/Caches/com.apple.iconservices.store|Icon Services store"
        "$HOME/Library/Caches/com.apple.iconservices|Icon Services cache"
        "$HOME/Library/Caches/com.apple.Safari/WebKitCache|Safari WebKit cache"
        "$HOME/Library/Caches/com.apple.Safari/Favicon|Safari favicon cache"
    )

    for target in "${cache_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Finder and Safari caches updated"
}

# Maintenance scripts: run periodic tasks
opt_maintenance_scripts() {
    local success=true
    local periodic_cmd="/usr/sbin/periodic"

    # Show spinner while running all tasks
    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    # Run periodic scripts silently with timeout
    if [[ -x "$periodic_cmd" ]]; then
        if ! run_with_timeout 180 sudo "$periodic_cmd" daily weekly monthly > /dev/null 2>&1; then
            success=false
        fi
    fi

    # Run newsyslog silently with timeout
    if ! run_with_timeout 120 sudo newsyslog > /dev/null 2>&1; then
        success=false
    fi

    # Run repair_packages silently with timeout
    if [[ -x "/usr/libexec/repair_packages" ]]; then
        if ! run_with_timeout 180 sudo /usr/libexec/repair_packages --repair --standard-pkgs --volume / > /dev/null 2>&1; then
            success=false
        fi
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Complete"
    else
        echo -e "${YELLOW}!${NC} Some tasks timed out or failed"
    fi
}

# Log cleanup: remove diagnostic and crash logs
opt_log_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing diagnostic & crash logs..."
    local -a user_logs=(
        "$HOME/Library/Logs/DiagnosticReports"
        "$HOME/Library/Logs/corecaptured"
    )
    for target in "${user_logs[@]}"; do
        cleanup_path "$target" "$(basename "$target")"
    done

    if [[ -d "/Library/Logs/DiagnosticReports" ]]; then
        safe_sudo_find_delete "/Library/Logs/DiagnosticReports" "*.crash" 0 "f"
        safe_sudo_find_delete "/Library/Logs/DiagnosticReports" "*.panic" 0 "f"
        echo -e "${GREEN}${ICON_SUCCESS}${NC} System diagnostic logs cleared"
    else
        echo -e "${GRAY}-${NC} No system diagnostic logs found"
    fi
}

# Recent items: clear recent file lists
opt_recent_items() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing recent items lists..."
    local shared_dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
    if [[ -d "$shared_dir" ]]; then
        safe_find_delete "$shared_dir" "*.sfl2" 0 "f"
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Shared file lists cleared"
    fi

    rm -f "$HOME/Library/Preferences/com.apple.recentitems.plist" 2> /dev/null || true
    defaults delete NSGlobalDomain NSRecentDocumentsLimit 2> /dev/null || true

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Recent items cleared"
}

# Radio refresh: reset Bluetooth and Wi-Fi (safe mode - no pairing/password loss)
opt_radio_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing Bluetooth controller..."
    # Only restart Bluetooth service, do NOT delete pairing information
    sudo pkill -HUP bluetoothd 2> /dev/null || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Bluetooth controller refreshed"

    echo -e "${BLUE}${ICON_ARROW}${NC} Refreshing Wi-Fi service..."
    # Only restart Wi-Fi service, do NOT delete saved networks
    # Skip: Deleting airport.preferences.plist causes all saved Wi-Fi passwords to be lost
    # sudo rm -f "$sysconfig"/com.apple.airport.preferences.plist

    # Safe alternative: just restart the Wi-Fi interface
    local wifi_interface
    wifi_interface=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}' | head -1)
    if [[ -n "$wifi_interface" ]]; then
        sudo ifconfig "$wifi_interface" down 2> /dev/null || true
        sleep 1
        sudo ifconfig "$wifi_interface" up 2> /dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Wi-Fi interface restarted"
    else
        echo -e "${GRAY}-${NC} Wi-Fi interface not found"
    fi

    # Restart AirDrop interface
    sudo ifconfig awdl0 down 2> /dev/null || true
    sudo ifconfig awdl0 up 2> /dev/null || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Wireless services refreshed"
}

# Mail downloads: clear OLD Mail attachment cache (30+ days)
opt_mail_downloads() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing old Mail attachment downloads (30+ days)..."
    local -a mail_dirs=(
        "$HOME/Library/Mail Downloads"
        "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
    )

    local total_kb=0
    for target_path in "${mail_dirs[@]}"; do
        total_kb=$((total_kb + $(get_path_size_kb "$target_path")))
    done

    if [[ $total_kb -lt $marmot_MAIL_DOWNLOADS_MIN_KB ]]; then
        echo -e "${GRAY}-${NC} Only $(bytes_to_human $((total_kb * 1024))) detected, skipping cleanup"
        return
    fi

    # Only delete old attachments (safety window)
    local cleaned=false
    for target_path in "${mail_dirs[@]}"; do
        if [[ -d "$target_path" ]]; then
            safe_find_delete "$target_path" "*" "$marmot_LOG_AGE_DAYS" "f"
            cleaned=true
        fi
    done

    if [[ "$cleaned" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Cleaned old attachments (> ${marmot_LOG_AGE_DAYS} days)"
    else
        echo -e "${GRAY}-${NC} No old attachments found"
    fi
}

# Saved state: remove OLD app saved states (7+ days)
opt_saved_state_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Removing old saved application states (${marmot_SAVED_STATE_AGE_DAYS}+ days)..."
    local state_dir="$HOME/Library/Saved Application State"

    if [[ ! -d "$state_dir" ]]; then
        echo -e "${GRAY}-${NC} No saved states directory found"
        return
    fi

    # Only delete old saved states (safety window)
    local deleted=0
    while IFS= read -r -d '' state_path; do
        if safe_remove "$state_path" true; then
            ((deleted++))
        fi
    done < <(command find "$state_dir" -type d -name "*.savedState" -mtime "+$marmot_SAVED_STATE_AGE_DAYS" -print0 2> /dev/null)

    if [[ $deleted -gt 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Removed $deleted old saved state(s)"
    else
        echo -e "${GRAY}-${NC} No old saved states found"
    fi
}

# Finder and Dock: refresh interface caches
# REMOVED: Deleting Finder cache causes user configuration loss
# Including window positions, sidebar settings, view preferences, icon sizes
# Users reported losing Finder settings even with .DS_Store whitelist protection
# Keep this function for reference but do not use in default optimizations
opt_finder_dock_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Finder & Dock caches..."
    local -a interface_targets=(
        "$HOME/Library/Caches/com.apple.finder|Finder cache"
        "$HOME/Library/Caches/com.apple.dock.iconcache|Dock icon cache"
    )
    for target in "${interface_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done

    # Warn user before restarting Finder (may lose unsaved work)
    echo -e "${YELLOW}${ICON_WARNING}${NC} About to restart Finder & Dock (save any work in Finder windows)"
    sleep 2

    killall Finder > /dev/null 2>&1 || true
    killall Dock > /dev/null 2>&1 || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Finder & Dock relaunched"
}

# Swap cleanup: reset swap files
opt_swap_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Removing swapfiles and resetting dynamic pager..."
    if sudo launchctl unload /System/Library/LaunchDaemons/com.apple.dynamic_pager.plist > /dev/null 2>&1; then
        sudo rm -f /private/var/vm/swapfile* > /dev/null 2>&1 || true
        sudo touch /private/var/vm/swapfile0 > /dev/null 2>&1 || true
        sudo chmod 600 /private/var/vm/swapfile0 > /dev/null 2>&1 || true
        sudo launchctl load /System/Library/LaunchDaemons/com.apple.dynamic_pager.plist > /dev/null 2>&1 || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Swap cache rebuilt"
    else
        echo -e "${YELLOW}!${NC} Could not unload dynamic_pager"
    fi
}

# Startup cache: rebuild kernel caches
opt_startup_cache() {
    local macos_version
    macos_version=$(sw_vers -productVersion | cut -d '.' -f 1)
    local success=true

    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    if [[ "$macos_version" -ge 11 ]] || [[ "$(uname -m)" == "arm64" ]]; then
        if ! run_with_timeout 120 sudo kextcache -i / > /dev/null 2>&1; then
            success=false
        fi
    else
        if ! run_with_timeout 180 sudo kextcache -i / > /dev/null 2>&1; then
            success=false
        fi

        # Skip: Deleting PrelinkedKernels breaks ScreenSaverEngine and other system components
        # sudo rm -rf /System/Library/PrelinkedKernels/* > /dev/null 2>&1 || true
        run_with_timeout 120 sudo kextcache -system-prelinked-kernel > /dev/null 2>&1 || true
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Complete"
    else
        echo -e "${YELLOW}!${NC} Timed out or failed"
    fi
}

# Local snapshots: thin Time Machine snapshots
opt_local_snapshots() {
    if ! command -v tmutil > /dev/null 2>&1; then
        echo -e "${YELLOW}!${NC} tmutil not available on this system"
        return
    fi

    local before after
    before=$(count_local_snapshots)
    if [[ "$before" -eq 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} No local snapshots to thin"
        return
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    local success=false
    if run_with_timeout 180 sudo tmutil thinlocalsnapshots / 9999999999 4 > /dev/null 2>&1; then
        success=true
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    after=$(count_local_snapshots)
    local removed=$((before - after))
    [[ "$removed" -lt 0 ]] && removed=0

    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Removed $removed snapshots (remaining: $after)"
    else
        echo -e "${YELLOW}!${NC} Timed out or failed"
    fi
}

# Developer cleanup: remove Xcode/simulator cruft
opt_developer_cleanup() {
    local -a dev_targets=(
        "$HOME/Library/Developer/Xcode/DerivedData|Xcode DerivedData"
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport|iOS Device support files"
        "$HOME/Library/Developer/CoreSimulator/Caches|CoreSimulator caches"
    )

    for target in "${dev_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done

    if command -v xcrun > /dev/null 2>&1; then
        echo -e "${BLUE}${ICON_ARROW}${NC} Removing unavailable simulator runtimes..."
        if xcrun simctl delete unavailable > /dev/null 2>&1; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Unavailable simulators removed"
        else
            echo -e "${YELLOW}!${NC} Could not prune simulator runtimes"
        fi
    fi

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Developer caches cleaned"
}

# Fix broken system configurations
# Repairs corrupted preference files and broken login items
opt_fix_broken_configs() {
    local broken_prefs=0
    local broken_items=0

    # Fix broken preferences
    echo -e "${BLUE}${ICON_ARROW}${NC} Checking preference files..."
    broken_prefs=$(fix_broken_preferences)
    if [[ $broken_prefs -gt 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Fixed $broken_prefs broken preference files"
    else
        echo -e "${GREEN}${ICON_SUCCESS}${NC} All preference files valid"
    fi

    # Fix broken login items
    echo -e "${BLUE}${ICON_ARROW}${NC} Checking login items..."
    broken_items=$(fix_broken_login_items)
    if [[ $broken_items -gt 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Removed $broken_items broken login items"
    else
        echo -e "${GREEN}${ICON_SUCCESS}${NC} All login items valid"
    fi

    local total=$((broken_prefs + broken_items))
    if [[ $total -gt 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} System configuration repaired"
    fi
}

# Execute optimization by action name
execute_optimization() {
    local action="$1"
    local path="${2:-}"

    case "$action" in
        system_maintenance) opt_system_maintenance ;;
        cache_refresh) opt_cache_refresh ;;
        maintenance_scripts) opt_maintenance_scripts ;;
        log_cleanup) opt_log_cleanup ;;
        recent_items) opt_recent_items ;;
        radio_refresh) opt_radio_refresh ;;
        mail_downloads) opt_mail_downloads ;;
        saved_state_cleanup) opt_saved_state_cleanup ;;
        finder_dock_refresh) opt_finder_dock_refresh ;;
        swap_cleanup) opt_swap_cleanup ;;
        startup_cache) opt_startup_cache ;;
        local_snapshots) opt_local_snapshots ;;
        developer_cleanup) opt_developer_cleanup ;;
        fix_broken_configs) opt_fix_broken_configs ;;
        *)
            echo -e "${RED}${ICON_ERROR}${NC} Unknown action: $action"
            return 1
            ;;
    esac
}

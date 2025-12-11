#!/bin/bash
# User Data Cleanup Module (Cross-platform)

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

# Get XDG cache directory with fallback
get_xdg_cache_dir() {
    echo "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Get XDG config directory with fallback
get_xdg_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Get XDG data directory with fallback
get_xdg_data_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# Get XDG state directory with fallback (newer XDG spec)
get_xdg_state_dir() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Clean user essentials (caches, logs, trash, crash reports)
clean_user_essentials() {
    if is_macos; then
        # macOS-specific paths
        safe_clean ~/Library/Caches/* "User app cache"
        safe_clean ~/Library/Logs/* "User app logs"
        safe_clean ~/.Trash/* "Trash"

        # Empty trash on mounted volumes
        if [[ -d "/Volumes" ]]; then
            for volume in /Volumes/*; do
                [[ -d "$volume" && -d "$volume/.Trashes" && -w "$volume" ]] || continue

                # Skip network volumes
                local fs_type=$(command df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
                case "$fs_type" in
                    nfs | smbfs | afpfs | cifs | webdav) continue ;;
                esac

                # Verify volume is mounted and not a symlink
                mount | grep -q "on $volume " || continue
                [[ -L "$volume/.Trashes" ]] && continue
                [[ "$DRY_RUN" == "true" ]] && continue

                # Safely iterate and remove each item
                while IFS= read -r -d '' item; do
                    safe_remove "$item" true || true
                done < <(command find "$volume/.Trashes" -mindepth 1 -maxdepth 1 -print0 2> /dev/null || true)
            done
        fi

        safe_clean ~/Library/DiagnosticReports/* "Diagnostic reports"
        safe_clean ~/Library/Caches/com.apple.QuickLook.thumbnailcache "QuickLook thumbnails"
        safe_clean ~/Library/Caches/Quick\ Look/* "QuickLook cache"
        safe_clean ~/Library/Caches/com.apple.iconservices* "Icon services cache"
        safe_clean ~/Library/Caches/CloudKit/* "CloudKit cache"

        # Additional user-level caches (macOS)
        safe_clean ~/Library/Autosave\ Information/* "Autosave information"
        safe_clean ~/Library/IdentityCaches/* "Identity caches"
        safe_clean ~/Library/Suggestions/* "Suggestions cache (Siri)"
        safe_clean ~/Library/Calendars/Calendar\ Cache "Calendar cache"
        safe_clean ~/Library/Application\ Support/AddressBook/Sources/*/Photos.cache "Address Book photo cache"
    else
        # Linux-specific paths using XDG
        local xdg_cache=$(get_xdg_cache_dir)
        local xdg_data=$(get_xdg_data_dir)
        local xdg_config=$(get_xdg_config_dir)

        # Clean user cache directories
        safe_clean "$xdg_cache"/* "User app cache"

        # Clean user logs (various locations)
        safe_clean "$xdg_cache"/*/logs/* "App logs"
        safe_clean "$HOME/.local/share/logs"/* "Local logs"
        safe_clean "$HOME/.local/state"/* "Local state"

        # Clean trash
        safe_clean "$HOME/.local/share/Trash"/* "Trash"

        # Clean diagnostic reports
        safe_clean "$HOME/.cache/diagnostics"/* "Diagnostic reports"
        safe_clean "/var/crash"/* "System crash reports" 2>/dev/null || true

        # Clean icon and thumbnail caches
        safe_clean "$xdg_cache/thumbnails"/* "Thumbnail cache"
        safe_clean "$HOME/.cache/icons"/* "Icon cache"

        # Clean incomplete downloads
        safe_clean "$HOME/.cache/transmission"/* "Incomplete downloads (Transmission)"
        safe_clean "$HOME/.cache/partial"/* "Partial downloads"
    fi

    # Cross-platform incomplete downloads
    safe_clean ~/Downloads/*.download "Incomplete downloads (Safari)"
    safe_clean ~/Downloads/*.crdownload "Incomplete downloads (Chrome)"
    safe_clean ~/Downloads/*.part "Incomplete downloads (partial)"
    safe_clean ~/Downloads/*.tmp "Temporary download files"
    safe_clean ~/Downloads/*.filepart "Partial download files"
}

# Clean Finder metadata (.DS_Store files)
clean_finder_metadata() {
    if is_macos; then
        if [[ "$PROTECT_FINDER_METADATA" == "true" ]]; then
            note_activity
            echo -e "  ${GRAY}${ICON_SUCCESS}${NC} Finder metadata (whitelisted)"
        else
            clean_ds_store_tree "$HOME" "Home directory (.DS_Store)"

            if [[ -d "/Volumes" ]]; then
                for volume in /Volumes/*; do
                    [[ -d "$volume" && -w "$volume" ]] || continue

                    local fs_type=""
                    fs_type=$(command df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
                    case "$fs_type" in
                        nfs | smbfs | afpfs | cifs | webdav) continue ;;
                    esac

                    clean_ds_store_tree "$volume" "$(basename "$volume") volume (.DS_Store)"
                done
            fi
        fi
    else
        # Linux doesn't have .DS_Store files, but can clean similar metadata
        if [[ "$PROTECT_FINDER_METADATA" != "true" ]]; then
            # Clean thumbnail cache files
            local xdg_cache=$(get_xdg_cache_dir)
            safe_clean "$HOME/.thumbnails"/* "Thumbnail cache"
            safe_clean "$xdg_cache/thumbnails"/* "XDG thumbnail cache"

            # Clean recently used files cache
            safe_clean "$HOME/.local/share/recently-used.xbel*" "Recent files cache"

            # Clean Nautilus/Thunar other metadata files
            find "$HOME" -name ".directory" -type f -delete 2>/dev/null || true
        fi
    fi
}

# Clean platform-specific system caches
clean_system_caches() {
    if is_macos; then
        safe_clean ~/Library/Saved\ Application\ State/* "Saved application states"
        safe_clean ~/Library/Caches/com.apple.spotlight "Spotlight cache"

        # Clean Spotlight user caches (CoreSpotlight can grow very large)
        clean_spotlight_caches

        safe_clean ~/Library/Caches/com.apple.photoanalysisd "Photo analysis cache"
        safe_clean ~/Library/Caches/com.apple.akd "Apple ID cache"
        safe_clean ~/Library/Caches/com.apple.Safari/Webpage\ Previews/* "Safari webpage previews"
        safe_clean ~/Library/Application\ Support/CloudDocs/session/db/* "iCloud session cache"
        safe_clean ~/Library/Caches/com.apple.Safari/fsCachedData/* "Safari cached data"
        safe_clean ~/Library/Caches/com.apple.WebKit.WebContent/* "WebKit content cache"
        safe_clean ~/Library/Caches/com.apple.WebKit.Networking/* "WebKit network cache"
    else
        # Linux system cache cleaning
        local xdg_cache=$(get_xdg_cache_dir)
        local xdg_state=$(get_xdg_state_dir)

        # Clean various Linux-specific caches
        safe_clean "$xdg_cache/menus"/* "Menu cache"
        safe_clean "$xdg_cache/desktop-base"/* "Desktop cache"
        safe_clean "$xdg_cache/fontconfig"/* "Font cache"
        safe_clean "$xdg_cache/gtk-*"/* "GTK cache"
        safe_clean "$xdg_cache/gstreamer-*"/* "GStreamer cache"

        # Clean Flatpak runtime caches
        if command -v flatpak > /dev/null 2>&1; then
            safe_clean "$HOME/.var/app/*/cache"/* "Flatpak app caches"
        fi

        # Clean Snap runtime caches
        if command -v snap > /dev/null 2>&1; then
            safe_clean "$HOME/snap/*/common/.cache"/* "Snap app caches"
        fi
    fi
}

# Clean sandboxed app caches
clean_sandboxed_app_caches() {
    if is_macos; then
        safe_clean ~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/* "Wallpaper agent cache"
        safe_clean ~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/* "Media analysis cache"
        safe_clean ~/Library/Containers/com.apple.AppStore/Data/Library/Caches/* "App Store cache"
        safe_clean ~/Library/Containers/com.apple.configurator.xpc.InternetService/Data/tmp/* "Apple Configurator temp files"
        safe_clean ~/Library/Containers/*/Data/Library/Caches/* "Sandboxed app caches"
    else
        # Linux sandboxed applications (Flatpak, Snap, AppImage)
        local xdg_cache=$(get_xdg_cache_dir)

        # Flatpak apps
        safe_clean "$HOME/.var/app"/*/cache/* "Flatpak app caches"
        safe_clean "$HOME/.var/app"/*/tmp/* "Flatpak temp files"

        # Snap apps
        safe_clean "$HOME/snap"/*/common/.cache/* "Snap app caches"
        safe_clean "$HOME/snap"/*/common/tmp/* "Snap temp files"

        # AppImage cache
        safe_clean "$HOME/.cache/appimage-launcher"/* "AppImage cache"
    fi
}

# Clean browser caches (Safari, Chrome, Edge, Firefox, etc.)
clean_browsers() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.apple.Safari/* "Safari cache"

        # Chrome/Chromium
        safe_clean ~/Library/Caches/Google/Chrome/* "Chrome cache"
        safe_clean ~/Library/Application\ Support/Google/Chrome/*/Application\ Cache/* "Chrome app cache"
        safe_clean ~/Library/Application\ Support/Google/Chrome/*/GPUCache/* "Chrome GPU cache"
        safe_clean ~/Library/Caches/Chromium/* "Chromium cache"

        safe_clean ~/Library/Caches/com.microsoft.edgemac/* "Edge cache"
        safe_clean ~/Library/Caches/company.thebrowser.Browser/* "Arc cache"
        safe_clean ~/Library/Caches/company.thebrowser.dia/* "Dia cache"
        safe_clean ~/Library/Caches/BraveSoftware/Brave-Browser/* "Brave cache"
        safe_clean ~/Library/Caches/Firefox/* "Firefox cache"
        safe_clean ~/Library/Caches/com.operasoftware.Opera/* "Opera cache"
        safe_clean ~/Library/Caches/com.vivaldi.Vivaldi/* "Vivaldi cache"
        safe_clean ~/Library/Caches/Comet/* "Comet cache"
        safe_clean ~/Library/Caches/com.kagi.kagimacOS/* "Orion cache"
        safe_clean ~/Library/Caches/zen/* "Zen cache"
        safe_clean ~/Library/Application\ Support/Firefox/Profiles/*/cache2/* "Firefox profile cache"
    else
        # Linux browser paths
        local xdg_cache=$(get_xdg_cache_dir)
        local xdg_config=$(get_xdg_config_dir)

        # Chrome/Chromium
        safe_clean "$xdg_cache/google-chrome"/* "Chrome cache"
        safe_clean "$xdg_cache/chromium"/* "Chromium cache"
        safe_clean "$xdg_config/google-chrome"/*/Cache/* "Chrome app cache"
        safe_clean "$xdg_config/chromium"/*/Cache/* "Chromium app cache"

        # Firefox
        safe_clean "$xdg_cache/mozilla/firefox"/* "Firefox cache"
        safe_clean "$HOME/.mozilla/firefox"/*/cache2/* "Firefox profile cache"

        # Edge (Linux)
        safe_clean "$xdg_cache/microsoft-edge"/* "Edge cache"
        safe_clean "$xdg_config/microsoft-edge"/*/Cache/* "Edge app cache"

        # Opera
        safe_clean "$xdg_cache/opera"/* "Opera cache"
        safe_clean "$xdg_cache/com.operasoftware.Opera"/* "Opera cache"

        # Brave
        safe_clean "$xdg_cache/BraveSoftware"/* "Brave cache"
        safe_clean "$xdg_cache/brave-browser"/* "Brave cache"

        # Vivaldi
        safe_clean "$xdg_cache/vivaldi"/* "Vivaldi cache"
        safe_clean "$xdg_cache/com.vivaldi.Vivaldi"/* "Vivaldi cache"

        # Other browsers
        safe_clean "$xdg_cache/epiphany"/* "Epiphany cache"
        safe_clean "$xdg_cache/min"/* "Min browser cache"
        safe_clean "$xdg_cache/qutebrowser"/* "Qutebrowser cache"
        safe_clean "$xdg_cache/falkon"/* "Falkon cache"
    fi

    # DISABLED: Service Worker CacheStorage scanning (find can hang on large browser profiles)
    # Browser caches are already cleaned by the safe_clean calls above
}

# Clean cloud storage app caches
clean_cloud_storage() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.dropbox.* "Dropbox cache"
        safe_clean ~/Library/Caches/com.getdropbox.dropbox "Dropbox cache"
        safe_clean ~/Library/Caches/com.google.GoogleDrive "Google Drive cache"
        safe_clean ~/Library/Caches/com.baidu.netdisk "Baidu Netdisk cache"
        safe_clean ~/Library/Caches/com.alibaba.teambitiondisk "Alibaba Cloud cache"
        safe_clean ~/Library/Caches/com.box.desktop "Box cache"
        safe_clean ~/Library/Caches/com.microsoft.OneDrive "OneDrive cache"
    else
        # Linux cloud storage paths
        local xdg_cache=$(get_xdg_cache_dir)
        local xdg_config=$(get_xdg_config_dir)

        # Dropbox
        safe_clean "$xdg_cache/dropbox"/* "Dropbox cache"
        safe_clean "$HOME/.dropbox"/* "Dropbox data"

        # Google Drive
        safe_clean "$xdg_cache/google-drive-ocamlfuse"/* "Google Drive cache"
        safe_clean "$xdg_cache/insync"/* "Insync cache"

        # OneDrive
        safe_clean "$xdg_cache/onedrive"/* "OneDrive cache"
        safe_clean "$HOME/.local/share/onedrive"/* "OneDrive data"

        # Nextcloud/OwnCloud
        safe_clean "$xdg_cache/nextcloud"/* "Nextcloud cache"
        safe_clean "$xdg_cache/owncloud"/* "OwnCloud cache"
        safe_clean "$HOME/.local/share/nextcloud"/* "Nextcloud data"
        safe_clean "$HOME/.local/share/owncloud"/* "OwnCloud data"

        # Mega
        safe_clean "$xdg_cache/megasync"/* "Mega cache"

        # Seafile
        safe_clean "$xdg/cache/seafile"/* "Seafile cache"
    fi
}

# Clean office application caches
clean_office_applications() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.microsoft.Word "Microsoft Word cache"
        safe_clean ~/Library/Caches/com.microsoft.Excel "Microsoft Excel cache"
        safe_clean ~/Library/Caches/com.microsoft.Powerpoint "Microsoft PowerPoint cache"
        safe_clean ~/Library/Caches/com.microsoft.Outlook/* "Microsoft Outlook cache"
        safe_clean ~/Library/Caches/com.apple.iWork.* "Apple iWork cache"
        safe_clean ~/Library/Caches/com.kingsoft.wpsoffice.mac "WPS Office cache"
        safe_clean ~/Library/Caches/org.mozilla.thunderbird/* "Thunderbird cache"
        safe_clean ~/Library/Caches/com.apple.mail/* "Apple Mail cache"
    else
        # Linux office applications
        local xdg_cache=$(get_xdg_cache_dir)
        local xdg_config=$(get_xdg_config_dir)

        # LibreOffice
        safe_clean "$HOME/.config/libreoffice"/*/user/cache/* "LibreOffice cache"
        safe_clean "$xdg_cache/libreoffice"/* "LibreOffice cache"

        # Microsoft Office (Linux)
        safe_clean "$xdg_cache/Microsoft"/* "Microsoft Office cache"
        safe_clean "$xdg_config/Microsoft"/* "Microsoft Office config"

        # OnlyOffice
        safe_clean "$xdg_cache/onlyoffice"/* "OnlyOffice cache"

        # WPS Office
        safe_clean "$xdg_cache/kingsoft"/* "WPS Office cache"
        safe_clean "$HOME/.config/wps-office"/*/cache/* "WPS Office cache"

        # Thunderbird
        safe_clean "$xdg_cache/thunderbird"/* "Thunderbird cache"
        safe_clean "$HOME/.thunderbird"/*/cache2/* "Thunderbird profile cache"

        # Evolution
        safe_clean "$xdg_cache/evolution"/* "Evolution cache"
        safe_clean "$HOME/.local/share/evolution"/*/cache/* "Evolution data cache"

        # Geary
        safe_clean "$xdg_cache/geary"/* "Geary cache"

        # Mutt/Neomutt cache
        safe_clean "$HOME/.cache/mutt"/* "Mutt cache"
    fi
}

# Clean virtualization tools
clean_virtualization_tools() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.vmware.fusion "VMware Fusion cache"
        safe_clean ~/Library/Caches/com.parallels.* "Parallels cache"
        safe_clean ~/VirtualBox\ VMs/.cache "VirtualBox cache"
        safe_clean ~/.vagrant.d/tmp/* "Vagrant temporary files"
    else
        # Linux virtualization tools
        # VirtualBox
        safe_clean "$HOME/.cache/VirtualBox"/* "VirtualBox cache"
        safe_clean "$HOME/VirtualBox VMs"/*.cache "VirtualBox VM cache"

        # VMware
        safe_clean "$HOME/.cache/vmware"/* "VMware cache"

        # Libvirt/QEMU
        safe_clean "$HOME/.cache/libvirt"/* "Libvirt cache"
        safe_clean "/var/cache/libvirt"/* "System libvirt cache" 2>/dev/null || true

        # Docker
        if command -v docker > /dev/null 2>&1; then
            # Only clean if docker is not running
            if ! docker info > /dev/null 2>&1; then
                safe_clean "$HOME/.docker"/*/tmp/* "Docker temp files"
            fi
        fi

        # Vagrant
        safe_clean "$HOME/.vagrant.d/tmp"/* "Vagrant temporary files"
        safe_clean "$HOME/.cache/vagrant"/* "Vagrant cache"

        # LXC
        safe_clean "$HOME/.cache/lxc"/* "LXC cache"

        # Minikube
        safe_clean "$HOME/.minikube/cache"/* "Minikube cache"
    fi
}

# Clean Application Support logs and caches
clean_application_support_logs() {
    if is_macos; then
        # Check permission
        if [[ ! -d "$HOME/Library/Application Support" ]] || ! ls "$HOME/Library/Application Support" > /dev/null 2>&1; then
            note_activity
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} Skipped: No permission to access Application Support"
            return 0
        fi

        # Clean log directories and cache patterns with iteration limit
        # Reduced from 200 to 50 to prevent hanging on large directories
        local iteration_count=0
        local max_iterations=50

        for app_dir in ~/Library/Application\ Support/*; do
            [[ -d "$app_dir" ]] || continue

            # Safety: limit iterations
            ((iteration_count++))
            if [[ $iteration_count -gt $max_iterations ]]; then
                break
            fi

            app_name=$(basename "$app_dir")

            # Skip system and protected apps (case-insensitive)
            local app_name_lower
            app_name_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
            case "$app_name_lower" in
                com.apple.* | adobe* | jetbrains* | 1password | claude | *clashx* | *clash* | mihomo* | *surge* | iterm* | warp* | kitty* | alacritty* | wezterm* | ghostty*)
                    continue
                    ;;
            esac

            # Clean log directories - simple direct removal without deep scanning
            [[ -d "$app_dir/log" ]] && safe_clean "$app_dir/log"/* "App logs: $app_name"
            [[ -d "$app_dir/logs" ]] && safe_clean "$app_dir/logs"/* "App logs: $app_name"
            [[ -d "$app_dir/activitylog" ]] && safe_clean "$app_dir/activitylog"/* "Activity logs: $app_name"

            # Clean common cache patterns - skip complex patterns that might hang
            [[ -d "$app_dir/Cache/Cache_Data" ]] && safe_clean "$app_dir/Cache/Cache_Data" "Cache data: $app_name"
            [[ -d "$app_dir/Crashpad/completed" ]] && safe_clean "$app_dir/Crashpad/completed"/* "Crash reports: $app_name"

            # DISABLED: Service Worker and update scanning (too slow, causes hanging)
            # These are covered by browser-specific cleaning in clean_browsers()
        done

        # Clean Group Containers logs - only scan known containers to avoid hanging
        # Direct path access is fast and won't cause performance issues
        # Add new containers here as users report them
        local known_group_containers=(
            "group.com.apple.contentdelivery" # Issue #104: Can accumulate 4GB+ in Library/Logs/Transporter
        )

        for container in "${known_group_containers[@]}"; do
            local container_path="$HOME/Library/Group Containers/$container"

            # Check both direct Logs and Library/Logs patterns
            if [[ -d "$container_path/Logs" ]]; then
                debug_log "Scanning Group Container: $container/Logs"
                safe_clean "$container_path/Logs"/* "Group container logs: $container"
            fi
            if [[ -d "$container_path/Library/Logs" ]]; then
                debug_log "Scanning Group Container: $container/Library/Logs"
                safe_clean "$container_path/Library/Logs"/* "Group container logs: $container"
            fi
        done
    else
        # Linux equivalent of Application Support
        local xdg_config=$(get_xdg_config_dir)
        local xdg_data=$(get_xdg_data_dir)
        local xdg_cache=$(get_xdg_cache_dir)

        # Clean application logs and caches
        local iteration_count=0
        local max_iterations=50

        # Clean logs from XDG config directories
        for app_dir in "$xdg_config"/*; do
            [[ -d "$app_dir" ]] || continue

            # Safety: limit iterations
            ((iteration_count++))
            if [[ $iteration_count -gt $max_iterations ]]; then
                break
            fi

            app_name=$(basename "$app_dir")

            # Skip system and protected apps (case-insensitive)
            local app_name_lower
            app_name_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
            case "$app_name_lower" in
                *system* | *gnome* | *kde* | *xfce* | *pulse* | *dbus* | *gtk* | *qt* | *xorg* | *wayland*)
                    continue
                    ;;
            esac

            # Clean log directories
            [[ -d "$app_dir/log" ]] && safe_clean "$app_dir/log"/* "App logs: $app_name"
            [[ -d "$app_dir/logs" ]] && safe_clean "$app_dir/logs"/* "App logs: $app_name"
            [[ -d "$app_dir/cache" ]] && safe_clean "$app_dir/cache"/* "App cache: $app_name"
            [[ -d "$app_dir/tmp" ]] && safe_clean "$app_dir/tmp"/* "App temp: $app_name"
        done

        # Clean data directories
        for app_dir in "$xdg_data"/*; do
            [[ -d "$app_dir" ]] || continue

            # Safety: limit iterations
            ((iteration_count++))
            if [[ $iteration_count -gt $max_iterations ]]; then
                break
            fi

            app_name=$(basename "$app_dir")

            # Clean cache and crash reports
            [[ -d "$app_dir/cache" ]] && safe_clean "$app_dir/cache"/* "Data cache: $app_name"
            [[ -d "$app_dir/crash" ]] && safe_clean "$app_dir/crash"/* "Crash reports: $app_name"
        done
    fi
}

# Check and show device backup info
check_device_backups() {
    if is_macos; then
        local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
        # Simplified check without find to avoid hanging
        if [[ -d "$backup_dir" ]]; then
            local backup_kb=$(get_path_size_kb "$backup_dir")
            if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then
                local backup_human=$(command du -sh "$backup_dir" 2> /dev/null | awk '{print $1}')
                if [[ -n "$backup_human" ]]; then
                    note_activity
                    echo -e "  Found ${GREEN}${backup_human}${NC} iOS backups"
                    echo -e "  You can delete them manually: ${backup_dir}"
                fi
            fi
        fi
    else
        # Linux equivalent - check for mobile device backups
        local xdg_data=$(get_xdg_data_dir)

        # Android backups (if any)
        if [[ -d "$HOME/.android/backup" ]]; then
            local backup_kb=$(get_path_size_kb "$HOME/.android/backup")
            if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then
                local backup_human=$(command du -sh "$HOME/.android/backup" 2> /dev/null | awk '{print $1}')
                if [[ -n "$backup_human" ]]; then
                    note_activity
                    echo -e "  Found ${GREEN}${backup_human}${NC} Android backups"
                    echo -e "  You can delete them manually: $HOME/.android/backup"
                fi
            fi
        fi

        # Check for iOS-like backups in Linux
        if [[ -d "$xdg_data/mobilesync/backup" ]]; then
            local backup_kb=$(get_path_size_kb "$xdg_data/mobilesync/backup")
            if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then
                local backup_human=$(command du -sh "$xdg_data/mobilesync/backup" 2> /dev/null | awk '{print $1}')
                if [[ -n "$backup_human" ]]; then
                    note_activity
                    echo -e "  Found ${GREEN}${backup_human}${NC} mobile device backups"
                    echo -e "  You can delete them manually: $xdg_data/mobilesync/backup"
                fi
            fi
        fi
    fi
}

# Clean architecture-specific caches
clean_architecture_caches() {
    if is_macos; then
        # Clean Apple Silicon specific caches
        # Env: IS_M_SERIES
        if [[ "$IS_M_SERIES" == "true" ]]; then
            safe_clean /Library/Apple/usr/share/rosetta/rosetta_update_bundle "Rosetta 2 cache"
            safe_clean ~/Library/Caches/com.apple.rosetta.update "Rosetta 2 user cache"
            safe_clean ~/Library/Caches/com.apple.amp.mediasevicesd "Apple Silicon media service cache"
        fi

        # Clean Intel-specific caches
        if [[ "$IS_M_SERIES" != "true" ]]; then
            safe_clean ~/Library/Caches/com.apple.homed "HomeKit cache (Intel)"
        fi
    else
        # Linux architecture-specific caches

        # ARM/AArch64 specific
        if [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]]; then
            safe_clean "$HOME/.cache/arm-optimized-binaries"/* "ARM optimized cache"
            safe_clean "$HOME/.cache/qemu-aarch64"/* "QEMU ARM cache"
        fi

        # x86_64 specific
        if [[ "$(uname -m)" == "x86_64" ]]; then
            safe_clean "$HOME/.cache/ia-32-libs"/* "x86 compatibility cache"
            safe_clean "$HOME/.cache/wine"/*/temp/* "Wine temp files"
        fi

        # Clean gstreamer codec caches (architecture-specific)
        safe_clean "$HOME/.cache/gstreamer-*"/* "GStreamer codec cache"

        # Clean LLVM/Clang caches
        safe_clean "$HOME/.cache/clang"/* "Clang cache"
        safe_clean "$HOME/.cache/llvm"/* "LLVM cache"
    fi
}

#!/bin/bash
# System-Level Cleanup Module (Cross-platform)
# Deep system cleanup (requires sudo) and backup cleanup

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

# Deep system cleanup (requires sudo)
clean_deep_system() {
    if is_macos; then
        # Clean old system caches
        safe_sudo_find_delete "/Library/Caches" "*.cache" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/Library/Caches" "*.tmp" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/Library/Caches" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true

        # Clean temp files - use real paths (macOS /tmp is symlink to /private/tmp)
        local tmp_cleaned=0
        safe_sudo_find_delete "/private/tmp" "*" "${marmot_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
        safe_sudo_find_delete "/private/var/tmp" "*" "${marmot_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
        [[ $tmp_cleaned -eq 1 ]] && log_success "System temp files"

        # Clean crash reports
        safe_sudo_find_delete "/Library/Logs/DiagnosticReports" "*" "$marmot_CRASH_REPORT_AGE_DAYS" "f" || true
        log_success "System crash reports"

        # Clean system logs - use real path (macOS /var is symlink to /private/var)
        safe_sudo_find_delete "/private/var/log" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/private/var/log" "*.gz" "$marmot_LOG_AGE_DAYS" "f" || true
        log_success "System logs"

        # Clean Library Updates safely - skip if SIP is enabled to avoid error messages
        # SIP-protected files in /Library/Updates cannot be deleted even with sudo
        if [[ -d "/Library/Updates" && ! -L "/Library/Updates" ]]; then
            if is_sip_enabled; then
                # SIP is enabled, skip /Library/Updates entirely to avoid error messages
                # These files are system-protected and cannot be removed
                : # No-op, silently skip
            else
                # SIP is disabled, attempt cleanup with restricted flag check
                local updates_cleaned=0
                while IFS= read -r -d '' item; do
                    # Skip system-protected files (restricted flag)
                    local item_flags
                    item_flags=$(command stat -f%Sf "$item" 2> /dev/null || echo "")
                    if [[ "$item_flags" == *"restricted"* ]]; then
                        continue
                    fi

                    if safe_sudo_remove "$item"; then
                        ((updates_cleaned++))
                    fi
                done < <(find /Library/Updates -mindepth 1 -maxdepth 1 -print0 2> /dev/null || true)
                [[ $updates_cleaned -gt 0 ]] && log_success "System library updates"
            fi
        fi

        # Clean macOS Install Data (system upgrade leftovers)
        # Only remove if older than 30 days to ensure system stability
        if [[ -d "/macOS Install Data" ]]; then
            local mtime=$(get_file_mtime "/macOS Install Data")
            local age_days=$((($(date +%s) - mtime) / 86400))

            debug_log "Found macOS Install Data (age: ${age_days} days)"

            if [[ $age_days -ge 30 ]]; then
                local size_kb=$(get_path_size_kb "/macOS Install Data")
                if [[ -n "$size_kb" && "$size_kb" -gt 0 ]]; then
                    local size_human=$(bytes_to_human "$((size_kb * 1024))")
                    debug_log "Cleaning macOS Install Data: $size_human (${age_days} days old)"

                    if safe_sudo_remove "/macOS Install Data"; then
                        log_success "macOS Install Data ($size_human)"
                    fi
                fi
            else
                debug_log "Keeping macOS Install Data (only ${age_days} days old, needs 30+)"
            fi
        fi

        # Clean browser code signature caches
        # These are regenerated automatically when needed
        local code_sign_cleaned=0
        while IFS= read -r -d '' cache_dir; do
            debug_log "Found code sign cache: $cache_dir"
            if safe_remove "$cache_dir" true; then
                ((code_sign_cleaned++))
            fi
        done < <(find /private/var/folders -type d -name "*.code_sign_clone" -path "*/X/*" -print0 2> /dev/null || true)

        [[ $code_sign_cleaned -gt 0 ]] && log_success "Browser code signature caches ($code_sign_cleaned items)"

        # Clean system diagnostics logs
        safe_sudo_find_delete "/private/var/db/diagnostics/Special" "*" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/private/var/db/diagnostics/Persist" "*" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/private/var/db/DiagnosticPipeline" "*" "$marmot_LOG_AGE_DAYS" "f" || true
        log_success "System diagnostic logs"

        # Clean power logs
        safe_sudo_find_delete "/private/var/db/powerlog" "*" "$marmot_LOG_AGE_DAYS" "f" || true
        log_success "Power logs"
    else
        # Linux system cleanup
        # Only run if we have sudo privileges
        if [[ "$(id -u)" -ne 0 ]]; then
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} System cleanup requires sudo privileges"
            return 0
        fi

        # Clean old system caches
        safe_sudo_find_delete "/var/cache" "*.cache" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/cache" "*.tmp" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/cache" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true

        # Clean temp files
        local tmp_cleaned=0
        safe_sudo_find_delete "/tmp" "*" "${marmot_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
        safe_sudo_find_delete "/var/tmp" "*" "${marmot_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
        [[ $tmp_cleaned -eq 1 ]] && log_success "System temp files"

        # Clean crash reports
        safe_sudo_find_delete "/var/crash" "*" "$marmot_CRASH_REPORT_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/lib/apport/coredump" "*.crash" "$marmot_CRASH_REPORT_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/lib/systemd/coredump" "*.core" "$marmot_CRASH_REPORT_AGE_DAYS" "f" || true
        log_success "System crash reports"

        # Clean system logs
        safe_sudo_find_delete "/var/log" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/log" "*.log.*" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/log" "*.gz" "$marmot_LOG_AGE_DAYS" "f" || true
        log_success "System logs"

        # Clean journal logs (systemd)
        if command -v journalctl > /dev/null 2>&1; then
            # Rotate and vacuum old journal entries
            if journalctl --vacuum-time="${marmot_LOG_AGE_DAYS}days" > /dev/null 2>&1; then
                log_success "System journal logs"
            fi
        fi

        # Clean kernel module caches
        safe_sudo_find_delete "/lib/modules" "modules.*" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/usr/lib/modules" "modules.*" "$marmot_LOG_AGE_DAYS" "f" || true
        log_success "Kernel module caches"

        # Clean man page caches
        safe_sudo_find_delete "/var/cache/man" "*" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        log_success "Man page caches"

        # Clean font caches
        safe_sudo_find_delete "/var/cache/fontconfig" "*" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        log_success "Font caches"

        # Clean ld.so cache (rebuild after cleaning)
        safe_sudo_find_delete "/etc/ld.so.cache" "*" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        ldconfig > /dev/null 2>&1 || true
        log_success "Dynamic linker cache"

        # Clean package manager lock files (stale ones)
        safe_sudo_find_delete "/var/lib/dpkg" "lock-frontend" "1" "f" || true
        safe_sudo_find_delete "/var/lib/dpkg" "lock" "1" "f" || true
        safe_sudo_find_delete "/var/lib/apt/lists/lock" "lock" "1" "f" || true

        # Clean installer caches
        safe_sudo_find_delete "/var/cache/apt/archives" "*.deb" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/cache/dnf" "*.rpm" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/cache/pacman/pkg" "*.pkg.tar.*" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true

        # Clean container runtime caches
        safe_sudo_find_delete "/var/lib/docker" "*.tmp" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/lib/containerd" "*.tmp" "$marmot_TEMP_FILE_AGE_DAYS" "f" || true

        # Clean application logs
        safe_sudo_find_delete "/var/log" "app*.log" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/log" "daemon*.log" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/log" "syslog" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true
        safe_sudo_find_delete "/var/log" "messages" "*.log" "$marmot_LOG_AGE_DAYS" "f" || true
    fi
}

# Clean failed backups (Time Machine on macOS, various backup tools on Linux)
clean_failed_backups() {
    if is_macos; then
        clean_time_machine_failed_backups
    else
        clean_linux_failed_backups
    fi
}

# Clean Time Machine failed backups (macOS only)
clean_time_machine_failed_backups() {
    local tm_cleaned=0

    # Check if Time Machine is configured
    if command -v tmutil > /dev/null 2>&1; then
        if tmutil destinationinfo 2>&1 | grep -q "No destinations configured"; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
            return 0
        fi
    fi

    if [[ ! -d "/Volumes" ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
        return 0
    fi

    # Skip if backup is running
    if pgrep -x "backupd" > /dev/null 2>&1; then
        echo -e "  ${YELLOW}!${NC} Time Machine backup in progress, skipping cleanup"
        return 0
    fi

    for volume in /Volumes/*; do
        [[ -d "$volume" ]] || continue

        # Skip system and network volumes
        [[ "$volume" == "/Volumes/MacintoshHD" || "$volume" == "/" ]] && continue

        # Skip if volume is a symlink (security check)
        [[ -L "$volume" ]] && continue

        # Check if this is a Time Machine destination
        if command -v tmutil > /dev/null 2>&1; then
            if ! tmutil destinationinfo 2> /dev/null | grep -q "$(basename "$volume")"; then
                continue
            fi
        fi

        local fs_type=$(command df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
        case "$fs_type" in
            nfs | smbfs | afpfs | cifs | webdav) continue ;;
        esac

        # HFS+ style backups (Backups.backupdb)
        local backupdb_dir="$volume/Backups.backupdb"
        if [[ -d "$backupdb_dir" ]]; then
            while IFS= read -r inprogress_file; do
                [[ -d "$inprogress_file" ]] || continue

                # Only delete old failed backups (safety window)
                local file_mtime=$(get_file_mtime "$inprogress_file")
                local current_time=$(date +%s)
                local hours_old=$(((current_time - file_mtime) / 3600))

                if [[ $hours_old -lt $marmot_TM_BACKUP_SAFE_HOURS ]]; then
                    continue
                fi

                local size_kb=$(get_path_size_kb "$inprogress_file")
                [[ "$size_kb" -le 0 ]] && continue

                local backup_name=$(basename "$inprogress_file")
                local size_human=$(bytes_to_human "$((size_kb * 1024))")

                if [[ "$DRY_RUN" == "true" ]]; then
                    echo -e "  ${YELLOW}→${NC} Failed backup: $backup_name ${YELLOW}($size_human dry)${NC}"
                    ((tm_cleaned++))
                    note_activity
                    continue
                fi

                # Real deletion
                if ! command -v tmutil > /dev/null 2>&1; then
                    echo -e "  ${YELLOW}!${NC} tmutil not available, skipping: $backup_name"
                    continue
                fi

                if tmutil delete "$inprogress_file" 2> /dev/null; then
                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed backup: $backup_name ${GREEN}($size_human)${NC}"
                    ((tm_cleaned++))
                    ((files_cleaned++))
                    ((total_size_cleaned += size_kb))
                    ((total_items++))
                    note_activity
                else
                    echo -e "  ${YELLOW}!${NC} Could not delete: $backup_name (try manually with sudo)"
                fi
            done < <(run_with_timeout 15 find "$backupdb_dir" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
        fi

        # APFS style backups (.backupbundle or .sparsebundle)
        for bundle in "$volume"/*.backupbundle "$volume"/*.sparsebundle; do
            [[ -e "$bundle" ]] || continue
            [[ -d "$bundle" ]] || continue

            # Check if bundle is mounted
            local bundle_name=$(basename "$bundle")
            local mounted_path=$(hdiutil info 2> /dev/null | grep -A 5 "image-path.*$bundle_name" | grep "/Volumes/" | awk '{print $1}' | head -1 || echo "")

            if [[ -n "$mounted_path" && -d "$mounted_path" ]]; then
                while IFS= read -r inprogress_file; do
                    [[ -d "$inprogress_file" ]] || continue

                    # Only delete old failed backups (safety window)
                    local file_mtime=$(get_file_mtime "$inprogress_file")
                    local current_time=$(date +%s)
                    local hours_old=$(((current_time - file_mtime) / 3600))

                    if [[ $hours_old -lt $marmot_TM_BACKUP_SAFE_HOURS ]]; then
                        continue
                    fi

                    local size_kb=$(get_path_size_kb "$inprogress_file")
                    [[ "$size_kb" -le 0 ]] && continue

                    local backup_name=$(basename "$inprogress_file")
                    local size_human=$(bytes_to_human "$((size_kb * 1024))")

                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "  ${YELLOW}→${NC} Failed APFS backup in $bundle_name: $backup_name ${YELLOW}($size_human dry)${NC}"
                        ((tm_cleaned++))
                        note_activity
                        continue
                    fi

                    # Real deletion
                    if ! command -v tmutil > /dev/null 2>&1; then
                        continue
                    fi

                    if tmutil delete "$inprogress_file" 2> /dev/null; then
                        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed APFS backup in $bundle_name: $backup_name ${GREEN}($size_human)${NC}"
                        ((tm_cleaned++))
                        ((files_cleaned++))
                        ((total_size_cleaned += size_kb))
                        ((total_items++))
                        note_activity
                    else
                        echo -e "  ${YELLOW}!${NC} Could not delete from bundle: $backup_name"
                    fi
                done < <(run_with_timeout 15 find "$mounted_path" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
            fi
        done
    done

    if [[ $tm_cleaned -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
    fi
}

# Clean Linux failed backups (rsnapshot, deja-dup, etc.)
clean_linux_failed_backups() {
    local backup_cleaned=0

    # Clean rsnapshot failed/incomplete backups
    if [[ -d "/var/cache/rsnapshot" ]]; then
        while IFS= read -r incomplete_dir; do
            [[ -d "$incomplete_dir" ]] || continue

            # Check directory age
            local mtime=$(get_file_mtime "$incomplete_dir")
            local age_days=$((($(date +%s) - mtime) / 86400))

            # Only delete if older than 7 days
            if [[ $age_days -lt 7 ]]; then
                continue
            fi

            local size_kb=$(get_path_size_kb "$incomplete_dir")
            [[ "$size_kb" -le 0 ]] && continue

            if [[ "$DRY_RUN" != "true" ]]; then
                if sudo rm -rf "$incomplete_dir" 2> /dev/null; then
                    local size_human=$(bytes_to_human "$((size_kb * 1024))")
                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed incomplete rsnapshot backup ($size_human)"
                    ((backup_cleaned++))
                    note_activity
                fi
            else
                echo -e "  ${YELLOW}→${NC} Would remove incomplete rsnapshot backup"
                ((backup_cleaned++))
            fi
        done < <(find /var/cache/rsnapshot -name "*.incomplete" -type d 2> /dev/null || true)
    fi

    # Clean deja-dup failed backups
    local deja_dup_cache="$HOME/.cache/deja-dup"
    if [[ -d "$deja_dup_cache" ]]; then
        # Clean old metadata files
        while IFS= read -r metadata_file; do
            local mtime=$(get_file_mtime "$metadata_file")
            local age_days=$((($(date +%s) - mtime) / 86400))

            if [[ $age_days -gt 30 ]]; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$metadata_file" 2> /dev/null || true
                    ((backup_cleaned++))
                fi
            fi
        done < <(find "$deja_dup_cache" -name "*.metadata" -type f 2> /dev/null || true)
    fi

    # Clean Borg backup temporary files
    local borg_cache="$HOME/.cache/borg"
    if [[ -d "$borg_cache" ]]; then
        while IFS= read -r tmp_file; do
            local mtime=$(get_file_mtime "$tmp_file")
            local age_days=$((($(date +%s) - mtime) / 86400))

            if [[ $age_days -gt 1 ]]; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$tmp_file" 2> /dev/null || true
                    ((backup_cleaned++))
                fi
            fi
        done < <(find "$borg_cache" -name "tmp.*" -type f 2> /dev/null || true)
    fi

    # Clean restic temporary files
    local restic_cache="$HOME/.cache/restic"
    if [[ -d "$restic_cache" ]]; then
        while IFS= read -r tmp_file; do
            local mtime=$(get_file_mtime "$tmp_file")
            local age_days=$((($(date +%s) - mtime) / 86400))

            if [[ $age_days -gt 1 ]]; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$tmp_file" 2> /dev/null || true
                    ((backup_cleaned++))
                fi
            fi
        done < <(find "$restic_cache" -name "tmp-*" -type f 2> /dev/null || true)
    fi

    # Clean timeshift failed snapshots
    if [[ -d "/var/timeshift" ]]; then
        while IFS= read -r failed_snapshot; do
            [[ -d "$failed_snapshot" ]] || continue

            # Check if snapshot is incomplete (missing essential files)
            if [[ -f "$failed_snapshot/info.json" ]]; then
                # Valid snapshot, skip
                continue
            fi

            if [[ "$DRY_RUN" != "true" ]]; then
                if sudo rm -rf "$failed_snapshot" 2> /dev/null; then
                    local size_kb=$(get_path_size_kb "$failed_snapshot")
                    local size_human=$(bytes_to_human "$((size_kb * 1024))")
                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed failed timeshift snapshot ($size_human)"
                    ((backup_cleaned++))
                    note_activity
                fi
            else
                echo -e "  ${YELLOW}→${NC} Would remove failed timeshift snapshot"
                ((backup_cleaned++))
            fi
        done < <(find /var/timeshift -maxdepth 2 -type d 2> /dev/null || true)
    fi

    if [[ $backup_cleaned -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Linux backups found"
    fi
}

#!/bin/bash

# Privacy & Security Module for Marmot
# Provides secure file deletion and privacy cleanup

security_init() {
    # Ensure security directory exists
    mkdir -p "$MARMOT_SECURITY_DIR"

    # Create secure delete log
    touch "$MARMOT_LOG_DIR/secure_delete.log"
}

# Secure file deletion with multiple passes
security_shred_file() {
    local file_path=$1
    local passes=${2:-3}
    local verify=${3:-true}

    if [[ ! -f "$file_path" ]]; then
        error "File not found: $file_path"
        return 1
    fi

    # Get original size for logging
    local original_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    log "info" "Securely deleting: $file_path ($passes passes)"

    # Use shred if available (most secure)
    if command -v shred >/dev/null 2>&1; then
        shred -vfz -n "$passes" "$file_path"
    else
        # Fallback: custom secure deletion
        local file_size=$(stat -c%s "$file_path")

        for ((i=1; i<=passes; i++)); do
            # Write random data
            dd if=/dev/urandom of="$file_path" bs=1k count=$((file_size/1024+1)) 2>/dev/null
            sync

            # Write zeros
            dd if=/dev/zero of="$file_path" bs=1k count=$((file_size/1024+1)) 2>/dev/null
            sync

            # Write ones
            dd if=/dev/zero bs=1k count=$((file_size/1024+1)) 2>/dev/null | tr '\0' '\377' > "$file_path"
            sync
        done
    fi

    # Remove the file
    rm -f "$file_path"

    # Verify deletion
    if $verify && [[ -e "$file_path" ]]; then
        error "Failed to securely delete: $file_path"
        return 1
    fi

    # Log deletion
    echo "$(date): SECURE_DELETE - $file_path (${original_size} bytes, ${passes} passes)" \
        >> "$MARMOT_LOG_DIR/secure_delete.log"

    success "Securely deleted: $file_path"
}

# Wipe free space on disk
security_wipe_free() {
    local mount_point=${1:-/}
    local passes=${2:-1}
    local temp_file="$MARMOT_SECURITY_DIR/wipe_temp.$$"

    log "info" "Wiping free space on $mount_point ($passes passes)"

    # Get available space
    local available=$(df -BG "$mount_point" | tail -1 | awk '{print $4}' | sed 's/G//')
    local file_size="${available}G"

    for ((i=1; i<=passes; i++)); do
        log "info" "Pass $i of $passes"

        # Fill free space with zeros
        dd if=/dev/zero of="$temp_file" bs=1M 2>/dev/null || true
        sync

        # Remove the file
        rm -f "$temp_file"
        sync
    done

    success "Free space wiped on $mount_point"
}

# Clean browser privacy data
privacy_clean_browsers() {
    local browsers=("firefox" "chrome" "chromium" "opera" "brave")
    local total_freed=0

    echo "Cleaning Browser Privacy Data"
    echo "============================"

    for browser in "${browsers[@]}"; do
        echo -n "Checking $browser... "

        case $browser in
            firefox)
                local ff_dir="$HOME/.mozilla/firefox"
                if [[ -d "$ff_dir" ]]; then
                    # Find all profiles
                    find "$ff_dir" -name "*.default*" -type d | while read -r profile; do
                        # Clear history, cookies, cache
                        rm -rf "$profile"/{places.sqlite*,formhistory.sqlite,cookies.sqlite,webappsstore.sqlite}
                        rm -rf "$profile"/{cache2,offlineCache,thumbnails}
                        # Clear session data
                        rm -rf "$profile"/sessionstore-backups
                    done
                    echo "✓"
                else
                    echo "not found"
                fi
                ;;
            chrome|chromium|brave)
                local chrome_dir="$HOME/.config/$browser"
                if [[ -d "$chrome_dir" ]]; then
                    # Clear history, cookies, cache
                    rm -rf "$chrome_dir"/Default/{History,History-journal,Cookies,Cookies-journal}
                    rm -rf "$chrome_dir"/Default/{Cache,Code Cache,GPUCache}
                    rm -rf "$chrome_dir"/Default/{Login Data,Login Data-journal}
                    rm -rf "$chrome_dir"/Default/{Preferences,Secure Preferences}
                    # Clear session storage
                    rm -rf "$chrome_dir"/Default/Session\ Storage
                    echo "✓"
                else
                    echo "not found"
                fi
                ;;
            opera)
                local opera_dir="$HOME/.config/opera"
                if [[ -d "$opera_dir" ]]; then
                    rm -rf "$opera_dir"/{History,History-journal,Cookies,Cookies-journal}
                    rm -rf "$opera_dir"/{Cache,GPUCache,Media Cache}
                    echo "✓"
                else
                    echo "not found"
                fi
                ;;
        esac
    done

    success "Browser privacy data cleaned"
}

# Clean system logs with sensitive data
privacy_clean_logs() {
    local days_to_keep=${1:-7}

    log "info" "Cleaning system logs older than $days_to_keep days"

    # System logs
    sudo journalctl --vacuum-time="${days_to_keep}d" 2>/dev/null || true

    # Remove old log files
    sudo find /var/log -type f -name "*.log.*" -mtime +$days_to_keep -delete 2>/dev/null || true
    sudo find /var/log -type f -name "*.log.[0-9]*" -mtime +$days_to_keep -delete 2>/dev/null || true

    # User logs
    find "$HOME/.local/share" -name "*.log" -mtime +$days_to_keep -delete 2>/dev/null || true

    success "System logs cleaned"
}

# Clean temporary files securely
privacy_clean_temp() {
    log "info" "Securely cleaning temporary files"

    # System temp
    sudo find /tmp -type f -atime +7 -exec security_shred_file {} \; 2>/dev/null || true
    sudo find /var/tmp -type f -atime +7 -exec security_shred_file {} \; 2>/dev/null || true

    # User temp
    find "$HOME/tmp" -type f -atime +7 -exec security_shred_file {} \; 2>/dev/null || true
    find "$HOME/.cache" -type f -atime +30 -exec security_shred_file {} \; 2>/dev/null || true

    # Application temp files
    find "$HOME/.local/share" -name "tmp*" -type f -atime +7 -exec security_shred_file {} \; 2>/dev/null || true

    success "Temporary files securely cleaned"
}

# Permission audit
security_audit_permissions() {
    local report_file="$MARMOT_LOG_DIR/permission_audit_$(date +%Y%m%d).txt"

    log "info" "Running permission audit..."

    {
        echo "Permission Audit Report"
        echo "======================"
        echo "Generated: $(date)"
        echo ""

        echo "=== World-Writable Files ==="
        find / -type f -perm -002 2>/dev/null | grep -v -E "^/proc|^/sys|^/dev" | head -20
        echo ""

        echo "=== SUID Files ==="
        find / -type f -perm -4000 2>/dev/null | head -20
        echo ""

        echo "=== SGID Files ==="
        find / -type f -perm -2000 2>/dev/null | head -20
        echo ""

        echo "=== User Home Permissions ==="
        find "$HOME" -type f -perm -o+r 2>/dev/null | grep -E "(key|pass|secret|token)" | head -10
        echo ""

        echo "=== SSH Directory Permissions ==="
        if [[ -d "$HOME/.ssh" ]]; then
            ls -la "$HOME/.ssh"
        fi

    } > "$report_file"

    success "Permission audit completed: $report_file"
}

# Generate entropy for secure operations
security_generate_entropy() {
    local duration=${1:-30}  # seconds

    log "info" "Generating entropy for $duration seconds"

    # Use multiple entropy sources
    (
        # Keyboard/mouse activity
        cat /dev/input/mice 2>/dev/null >/dev/null &
        local mouse_pid=$!

        # Disk activity
        dd if=/dev/sda of=/dev/null bs=1M count=1 2>/dev/null &
        local disk_pid=$!

        # CPU activity
        openssl rand -hex 1000000 >/dev/null &
        local cpu_pid=$!

        # Wait for specified duration
        sleep "$duration"

        # Kill background processes
        kill $mouse_pid $disk_pid $cpu_pid 2>/dev/null || true
    ) &

    # Show progress
    for ((i=duration; i>0; i--)); do
        printf "\rGenerating entropy: %d seconds remaining..." "$i"
        sleep 1
    done
    echo ""

    success "Entropy generation completed"
}

# Check file permissions
security_check_permissions() {
    local path=${1:-$HOME}

    echo "Checking File Permissions"
    echo "========================"

    # Check for sensitive files with weak permissions
    find "$path" -type f \( -name "*.key" -o -name "*.pem" -o -name "*rsa*" -o -name "*ssh*" \) \
        -exec ls -la {} \; 2>/dev/null | grep -E "rw....r.." && echo "⚠️  Found readable private keys"

    # Check for world-writable directories
    find "$path" -type d -perm -o+w 2>/dev/null | head -10

    # Check for suspicious executables
    find "$path" -type f -executable -user root 2>/dev/null | grep -v -E "^/usr|^/bin|^/sbin" | head -10
}

# Create encrypted container
security_create_container() {
    local container_path=$1
    local size=${2:-1G}

    if [[ -z "$container_path" ]]; then
        error "Please specify container path"
        return 1
    fi

    # Check if cryptsetup is available
    if ! command -v cryptsetup >/dev/null 2>&1; then
        error "cryptsetup is required but not installed"
        return 1
    fi

    log "info" "Creating encrypted container: $container_path ($size)"

    # Create sparse file
    fallocate -l "$size" "$container_path"

    # Setup encryption
    echo "Setting up LUKS encryption..."
    sudo cryptsetup luksFormat "$container_path"
    sudo cryptsetup open "$container_path" marmot_crypt

    # Create filesystem
    sudo mkfs.ext4 /dev/mapper/marmot_crypt

    # Mount
    sudo mkdir -p "/mnt/marmot_secure"
    sudo mount /dev/mapper/marmot_crypt "/mnt/marmot_secure"
    sudo chown "$USER:$USER" "/mnt/marmot_secure"

    success "Encrypted container created and mounted at /mnt/marmot_secure"
    echo "To unmount: sudo umount /mnt/marmot_secure && sudo cryptsetup close marmot_crypt"
}

# Verify secure deletion
security_verify_shred() {
    local file_path=$1
    local sample_size=${2:-1024}  # bytes to sample

    if [[ -f "$file_path" ]]; then
        error "File still exists: $file_path"
        return 1
    fi

    # Try to recover with forensic tools (if available)
    if command -v foremost >/dev/null 2>&1; then
        echo "Attempting recovery test..."
        # This would need the original disk device
        echo "⚠️  Full recovery test requires disk device access"
    fi

    success "File appears to be securely deleted"
}

# Privacy cleanup for specific applications
privacy_clean_app() {
    local app_name=$1

    case $app_name in
        discord)
            rm -rf "$HOME/.config/discord/Cache"
            rm -rf "$HOME/.config/discord/Code Cache"
            ;;
        slack)
            rm -rf "$HOME/.config/Slack/Cache"
            rm -rf "$HOME/.config/Slack/Code Cache"
            ;;
        telegram)
            rm -rf "$HOME/.local/share/TelegramDesktop/tdata/user_data"
            ;;
        vscode)
            rm -rf "$HOME/.config/Code/logs"
            rm -rf "$HOME/.config/Code/CachedExtensions"
            ;;
        *)
            echo "Unknown application: $app_name"
            return 1
            ;;
    esac

    success "Cleaned privacy data for $app_name"
}

# Generate secure password
security_generate_password() {
    local length=${1:-16}
    local include_symbols=${2:-true}

    local charset="A-Za-z0-9"
    $include_symbols && charset="${charset}!@#$%^&*()_+-=[]{}|;:,.<>?"

    openssl rand -base64 48 | tr -dc "$charset" | head -c "$length"
    echo
}

# Check for rootkits and malware
security_scan_malware() {
    # Use chkrootkit if available
    if command -v chkrootkit >/dev/null 2>&1; then
        log "info" "Running chkrootkit scan..."
        sudo chkrootkit 2>&1 | tee "$MARMOT_LOG_DIR/chkrootkit_$(date +%Y%m%d).txt"
    fi

    # Use rkhunter if available
    if command -v rkhunter >/dev/null 2>&1; then
        log "info" "Running rkhunter scan..."
        sudo rkhunter --check --skip-keypress 2>&1 | tee "$MARMOT_LOG_DIR/rkhunter_$(date +%Y%m%d).txt"
    fi

    # Check for suspicious processes
    echo "Checking for suspicious processes..."
    ps aux | grep -E "(bash.*sh|/dev/shm|/tmp/.*)" | grep -v grep
}

# Interactive security menu
security_menu() {
    while true; do
        echo
        echo "Privacy & Security Tools"
        echo "======================="
        echo "1) Secure file shredder"
        echo "2) Wipe free space"
        echo "3) Clean browser data"
        echo "4) Clean system logs"
        echo "5) Clean temporary files"
        echo "6) Permission audit"
        echo "7) Check file permissions"
        echo "8) Generate entropy"
        echo "9) Scan for malware"
        echo "10) Generate password"
        echo "11) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                read -p "Enter file path: " file
                security_shred_file "$file"
                ;;
            2)
                read -p "Enter mount point [/$]: " mount
                security_wipe_free "${mount:-/}"
                ;;
            3)
                privacy_clean_browsers
                ;;
            4)
                privacy_clean_logs
                ;;
            5)
                privacy_clean_temp
                ;;
            6)
                security_audit_permissions
                ;;
            7)
                read -p "Enter path to check [$HOME]: " path
                security_check_permissions "${path:-$HOME}"
                ;;
            8)
                read -p "Duration in seconds [30]: " duration
                security_generate_entropy "${duration:-30}"
                ;;
            9)
                security_scan_malware
                ;;
            10)
                read -p "Password length [16]: " length
                security_generate_password "${length:-16}"
                ;;
            11)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}
#!/bin/bash
# Sudo Session Manager
# Unified sudo authentication and keepalive management

set -euo pipefail

# ============================================================================
# Platform-specific helper functions
# ============================================================================

# Check if we're on macOS
is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

# Check if we're on Linux
is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

# ============================================================================
# Password Request Function
# ============================================================================

_request_password() {
    local tty_path="$1"
    local attempts=0

    # Clear sudo cache before password input
    sudo -k 2> /dev/null

    while ((attempts < 3)); do
        local password=""

        printf "${PURPLE}${ICON_ARROW}${NC} Password: " > "$tty_path"
        IFS= read -r -s password < "$tty_path" || password=""
        printf "\n" > "$tty_path"

        if [[ -z "$password" ]]; then
            unset password
            ((attempts++))
            if [[ $attempts -lt 3 ]]; then
                echo -e "${YELLOW}${ICON_WARNING}${NC} Password cannot be empty" > "$tty_path"
            fi
            continue
        fi

        # Verify password with sudo
        if printf '%s\n' "$password" | sudo -S -p "" -v > /dev/null 2>&1; then
            unset password
            return 0
        fi

        unset password
        ((attempts++))
        if [[ $attempts -lt 3 ]]; then
            echo -e "${YELLOW}${ICON_WARNING}${NC} Incorrect password, try again" > "$tty_path"
        fi
    done

    return 1
}

request_sudo_access() {
    local prompt_msg="${1:-Admin access required}"

    # Check if already have sudo access
    if sudo -n true 2> /dev/null; then
        return 0
    fi

    # Get TTY path
    local tty_path="/dev/tty"
    if [[ ! -r "$tty_path" || ! -w "$tty_path" ]]; then
        tty_path=$(tty 2> /dev/null || echo "")
        if [[ -z "$tty_path" || ! -r "$tty_path" || ! -w "$tty_path" ]]; then
            log_error "No interactive terminal available"
            return 1
        fi
    fi

    sudo -k

    # Standard password prompt for both platforms
    echo -e "${PURPLE}${ICON_ARROW}${NC} ${prompt_msg}"
    _request_password "$tty_path"
    return $?
}

# ============================================================================
# Sudo Session Management
# ============================================================================

# Global state
marmot_SUDO_KEEPALIVE_PID=""
marmot_SUDO_ESTABLISHED="false"

# Start sudo keepalive background process
# Returns: PID of keepalive process
_start_sudo_keepalive() {
    # Start background keepalive process with all outputs redirected
    (
        # Initial delay to let sudo cache stabilize after password entry
        sleep 2

        local retry_count=0
        while true; do
            if ! sudo -n -v 2> /dev/null; then
                ((retry_count++))
                if [[ $retry_count -ge 3 ]]; then
                    exit 1
                fi
                sleep 5
                continue
            fi
            retry_count=0
            sleep 30
            kill -0 "$$" 2> /dev/null || exit
        done
    ) > /dev/null 2>&1 &

    local pid=$!
    echo $pid
}

# Stop sudo keepalive process
# Args: $1 - PID of keepalive process
_stop_sudo_keepalive() {
    local pid="${1:-}"
    if [[ -n "$pid" ]]; then
        kill "$pid" 2> /dev/null || true
        wait "$pid" 2> /dev/null || true
    fi
}

# Check if sudo session is active
has_sudo_session() {
    sudo -n true 2> /dev/null
}

# Request sudo access (wrapper for common.sh function)
# Args: $1 - prompt message
request_sudo() {
    local prompt_msg="${1:-Admin access required}"

    if has_sudo_session; then
        return 0
    fi

    # Use the robust implementation from common.sh
    if request_sudo_access "$prompt_msg"; then
        return 0
    else
        return 1
    fi
}

# Ensure sudo session is established with keepalive
# Args: $1 - prompt message
ensure_sudo_session() {
    local prompt="${1:-Admin access required}"

    # Check if already established
    if has_sudo_session && [[ "$marmot_SUDO_ESTABLISHED" == "true" ]]; then
        return 0
    fi

    # Stop old keepalive if exists
    if [[ -n "$marmot_SUDO_KEEPALIVE_PID" ]]; then
        _stop_sudo_keepalive "$marmot_SUDO_KEEPALIVE_PID"
        marmot_SUDO_KEEPALIVE_PID=""
    fi

    # Request sudo access
    if ! request_sudo "$prompt"; then
        marmot_SUDO_ESTABLISHED="false"
        return 1
    fi

    # Start keepalive
    marmot_SUDO_KEEPALIVE_PID=$(_start_sudo_keepalive)

    marmot_SUDO_ESTABLISHED="true"
    return 0
}

# Stop sudo session and cleanup
stop_sudo_session() {
    if [[ -n "$marmot_SUDO_KEEPALIVE_PID" ]]; then
        _stop_sudo_keepalive "$marmot_SUDO_KEEPALIVE_PID"
        marmot_SUDO_KEEPALIVE_PID=""
    fi
    marmot_SUDO_ESTABLISHED="false"
}

# Register cleanup on script exit
register_sudo_cleanup() {
    trap stop_sudo_session EXIT INT TERM
}

# Check if sudo is likely needed for given operations
# Args: $@ - list of operations to check
will_need_sudo() {
    local -a operations=("$@")
    for op in "${operations[@]}"; do
        case "$op" in
            system_update | apt_update | system_update | firewall | system_fix | service_restart)
                return 0
                ;;
            # macOS-specific operations
            macos_update | appstore_update | touchid | rosetta)
                if is_macos; then
                    return 0
                fi
                ;;
            # Linux-specific operations
            apt_update | dnf_update | pacman_update | systemd_service)
                if is_linux; then
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# ============================================================================
# Legacy Touch ID functions (no-op on Linux)
# ============================================================================

# Check Touch ID support (macOS only)
check_touchid_support() {
    if is_macos && [[ -f /etc/pam.d/sudo ]]; then
        grep -q "pam_tid.so" /etc/pam.d/sudo 2> /dev/null
        return $?
    fi
    return 1
}

# Enable Touch ID for sudo (macOS only)
enable_touchid() {
    if ! is_macos; then
        log_error "Touch ID is only available on macOS"
        return 1
    fi

    if [[ ! -f /etc/pam.d/sudo ]]; then
        log_error "sudo PAM configuration not found"
        return 1
    fi

    if grep -q "pam_tid.so" /etc/pam.d/sudo; then
        log_success "Touch ID is already enabled for sudo"
        return 0
    fi

    # Add Touch ID authentication to sudo
    # Note: This uses macOS sed syntax
    if sudo sed -i '' '2i\
auth       sufficient     pam_tid.so' /etc/pam.d/sudo; then
        log_success "Touch ID enabled for sudo"
        return 0
    else
        log_error "Failed to enable Touch ID for sudo"
        return 1
    fi
}

# Disable Touch ID for sudo (macOS only)
disable_touchid() {
    if ! is_macos; then
        log_error "Touch ID is only available on macOS"
        return 1
    fi

    if [[ ! -f /etc/pam.d/sudo ]]; then
        log_error "sudo PAM configuration not found"
        return 1
    fi

    if ! grep -q "pam_tid.so" /etc/pam.d/sudo; then
        log_success "Touch ID is already disabled for sudo"
        return 0
    fi

    # Remove Touch ID authentication from sudo
    if sudo sed -i '' '/pam_tid.so/d' /etc/pam.d/sudo; then
        log_success "Touch ID disabled for sudo"
        return 0
    else
        log_error "Failed to disable Touch ID for sudo"
        return 1
    fi
}

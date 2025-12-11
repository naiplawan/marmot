#!/bin/bash
# Marmot Installation Script for Linux

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Simple spinner
_SPINNER_PID=""
start_line_spinner() {
    local msg="$1"
    [[ ! -t 1 ]] && {
        echo -e "${BLUE}|${NC} $msg"
        return
    }
    local chars="${MO_SPINNER_CHARS:-|/-\\}"
    [[ -z "$chars" ]] && chars='|/-\\'
    local i=0
    (while true; do
        c="${chars:$((i % ${#chars})):1}"
        printf "\r${BLUE}%s${NC} %s" "$c" "$msg"
        ((i++))
        sleep 0.12
    done) &
    _SPINNER_PID=$!
}
stop_line_spinner() { if [[ -n "$_SPINNER_PID" ]]; then
    kill "$_SPINNER_PID" 2> /dev/null || true
    wait "$_SPINNER_PID" 2> /dev/null || true
    _SPINNER_PID=""
    printf "\r\033[K"
fi; }

# Verbosity (0 = quiet, 1 = verbose)
VERBOSE=1

# Icons (duplicated from lib/core/common.sh - necessary as install.sh runs standalone)
readonly ICON_SUCCESS="✓"
readonly ICON_ADMIN="●"
readonly ICON_CONFIRM="◎"
readonly ICON_ERROR="☻"

# Logging functions
log_info() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${BLUE}$1${NC}"; }
log_success() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${GREEN}${ICON_SUCCESS}${NC} $1"; }
log_warning() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}${ICON_ERROR}${NC} $1"; }
log_admin() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${BLUE}${ICON_ADMIN}${NC} $1"; }
log_confirm() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${BLUE}${ICON_CONFIRM}${NC} $1"; }

# Default installation directory
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/marmot"
SOURCE_DIR=""

# Default action (install|update)
ACTION="install"

show_help() {
    cat << 'EOF'
marmot Installation Script for Linux
=================================

USAGE:
    ./install-linux.sh [OPTIONS]

OPTIONS:
    --prefix PATH       Install to custom directory (default: /usr/local/bin)
    --config PATH       Config directory (default: ~/.config/marmot)
    --update            Update marmot to the latest version
    --uninstall         Uninstall marmot
    --help, -h          Show this help

EXAMPLES:
    ./install-linux.sh                    # Install to /usr/local/bin
    ./install-linux.sh --prefix ~/.local/bin  # Install to custom directory
    ./install-linux.sh --update           # Update marmot in place
    ./install-linux.sh --uninstall       # Uninstall marmot

REQUIREMENTS:
    - Ubuntu 18.04 or later
    - Bash 4.0+
    - Standard Linux utilities (coreutils, find, etc.)
    - Optional: sudo for system-wide installation

The installer will:
1. Copy marmot binary and scripts to the install directory
2. Set up config directory with all modules
3. Make the marmot command available system-wide
EOF
    echo ""
}

# Resolve the directory containing source files (supports curl | bash)
resolve_source_dir() {
    if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" && -f "$SOURCE_DIR/marmot" ]]; then
        return 0
    fi

    # 1) If script is on disk, use its directory (only when marmot executable present)
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$script_dir/marmot" ]]; then
            SOURCE_DIR="$script_dir"
            return 0
        fi
    fi

    # 2) If CLEAN_SOURCE_DIR env is provided, honor it
    if [[ -n "${CLEAN_SOURCE_DIR:-}" && -d "$CLEAN_SOURCE_DIR" && -f "$CLEAN_SOURCE_DIR/marmot" ]]; then
        SOURCE_DIR="$CLEAN_SOURCE_DIR"
        return 0
    fi

    # 3) Fallback: fetch repository to a temp directory (works for curl | bash)
    local tmp
    tmp="$(mktemp -d)"
    # Expand tmp now so trap doesn't depend on local scope
    trap "rm -rf '$tmp'" EXIT

    start_line_spinner "Fetching marmot source..."
    if command -v curl > /dev/null 2>&1; then
        if curl -fsSL -o "$tmp/marmot.tar.gz" "https://github.com/tw93/marmot/archive/refs/heads/main.tar.gz"; then
            stop_line_spinner
            tar -xzf "$tmp/marmot.tar.gz" -C "$tmp"
            # Extracted folder name: marmot-main
            if [[ -d "$tmp/marmot-main" ]]; then
                SOURCE_DIR="$tmp/marmot-main"
                return 0
            fi
        fi
    fi
    stop_line_spinner

    start_line_spinner "Cloning marmot source..."
    if command -v git > /dev/null 2>&1; then
        if git clone --depth=1 https://github.com/tw93/marmot.git "$tmp/marmot" > /dev/null 2>&1; then
            stop_line_spinner
            SOURCE_DIR="$tmp/marmot"
            return 0
        fi
    fi
    stop_line_spinner

    log_error "Failed to fetch source files. Ensure curl or git is available."
    exit 1
}

get_source_version() {
    local source_marmot="$SOURCE_DIR/marmot"
    if [[ -f "$source_marmot" ]]; then
        sed -n 's/^VERSION="\(.*\)"$/\1/p' "$source_marmot" | head -n1
    fi
}

get_installed_version() {
    local binary="$INSTALL_DIR/marmot"
    if [[ -x "$binary" ]]; then
        # Try running the binary first (preferred method)
        local version
        version=$("$binary" --version 2> /dev/null | awk 'NF {print $NF; exit}')
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            # Fallback: parse VERSION from file (in case binary is broken)
            sed -n 's/^VERSION="\(.*\)"$/\1/p' "$binary" | head -n1
        fi
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --prefix)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --update)
                ACTION="update"
                shift 1
                ;;
            --uninstall)
                uninstall_marmot
                exit 0
                ;;
            --verbose | -v)
                VERBOSE=1
                shift 1
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check system requirements
check_requirements() {
    # Check if running on Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "This Linux version is designed for Linux systems only"
        log_info "For macOS, use install.sh instead"
        exit 1
    fi

    # Check for bash 4.0+
    local bash_version
    bash_version=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
    if [[ $(echo "$bash_version < 4.0" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        log_error "Bash 4.0 or later is required (found: $bash_version)"
        exit 1
    fi

    # Check if installed via package manager
    if command -v dpkg > /dev/null 2>&1 && dpkg -l marmot > /dev/null 2>&1; then
        if [[ "$ACTION" == "update" ]]; then
            return 0
        fi

        echo -e "${YELLOW}marmot is installed via dpkg/apt${NC}"
        echo ""
        echo "Choose one:"
        echo -e "  1. Update via apt: ${GREEN}sudo apt update && sudo apt install marmot${NC}"
        echo -e "  2. Switch to manual: ${GREEN}sudo dpkg -r marmot${NC} then re-run this"
        echo ""
        exit 1
    fi

    # Check if install directory exists and is writable
    if [[ ! -d "$(dirname "$INSTALL_DIR")" ]]; then
        log_error "Parent directory $(dirname "$INSTALL_DIR") does not exist"
        exit 1
    fi

    # Check for required dependencies
    local missing_deps=()
    for cmd in find xargs stat rm chmod; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Install with: sudo apt install coreutils findutils"
        exit 1
    fi
}

# Create installation directories
create_directories() {
    # Create install directory if it doesn't exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$(dirname "$INSTALL_DIR")" ]]; then
            log_admin "Admin access required for /usr/local/bin"
            sudo mkdir -p "$INSTALL_DIR"
        else
            mkdir -p "$INSTALL_DIR"
        fi
    fi

    # Create config directory
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/bin"
    mkdir -p "$CONFIG_DIR/lib"

}

# Install files
install_files() {
    resolve_source_dir

    local source_dir_abs
    local install_dir_abs
    local config_dir_abs
    source_dir_abs="$(cd "$SOURCE_DIR" && pwd)"
    install_dir_abs="$(cd "$INSTALL_DIR" && pwd)"
    config_dir_abs="$(cd "$CONFIG_DIR" && pwd)"

    # Copy main executable when destination differs
    if [[ -f "$SOURCE_DIR/marmot" ]]; then
        if [[ "$source_dir_abs" != "$install_dir_abs" ]]; then
            if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
                log_admin "Admin access required for /usr/local/bin"
                sudo cp "$SOURCE_DIR/marmot" "$INSTALL_DIR/marmot"
                sudo chmod +x "$INSTALL_DIR/marmot"
            else
                cp "$SOURCE_DIR/marmot" "$INSTALL_DIR/marmot"
                chmod +x "$INSTALL_DIR/marmot"
            fi
            log_success "Installed marmot to $INSTALL_DIR"
        fi
    else
        log_error "marmot executable not found in ${SOURCE_DIR:-unknown}"
        exit 1
    fi

    # Install marmot alias for marmot if available
    if [[ -f "$SOURCE_DIR/marmot" ]]; then
        if [[ "$source_dir_abs" == "$install_dir_abs" ]]; then
            log_success "marmot alias already present"
        else
            if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
                sudo cp "$SOURCE_DIR/marmot" "$INSTALL_DIR/marmot"
                sudo chmod +x "$INSTALL_DIR/marmot"
            else
                cp "$SOURCE_DIR/marmot" "$INSTALL_DIR/marmot"
                chmod +x "$INSTALL_DIR/marmot"
            fi
            log_success "Installed marmot alias"
        fi
    fi

    # Copy configuration and modules
    if [[ -d "$SOURCE_DIR/bin" ]]; then
        local source_bin_abs="$(cd "$SOURCE_DIR/bin" && pwd)"
        local config_bin_abs="$(cd "$CONFIG_DIR/bin" && pwd)"
        if [[ "$source_bin_abs" == "$config_bin_abs" ]]; then
            log_success "Modules already synced"
        else
            cp -r "$SOURCE_DIR/bin"/* "$CONFIG_DIR/bin/"
            chmod +x "$CONFIG_DIR/bin"/*
            log_success "Installed modules"
        fi
    fi

    if [[ -d "$SOURCE_DIR/lib" ]]; then
        local source_lib_abs="$(cd "$SOURCE_DIR/lib" && pwd)"
        local config_lib_abs="$(cd "$CONFIG_DIR/lib" && pwd)"
        if [[ "$source_lib_abs" == "$config_lib_abs" ]]; then
            log_success "Libraries already synced"
        else
            cp -r "$SOURCE_DIR/lib"/* "$CONFIG_DIR/lib/"
            log_success "Installed libraries"
        fi
    fi

    # Copy other files if they exist and directories differ
    if [[ "$config_dir_abs" != "$source_dir_abs" ]]; then
        for file in README.md LICENSE install-linux.sh; do
            if [[ -f "$SOURCE_DIR/$file" ]]; then
                cp -f "$SOURCE_DIR/$file" "$CONFIG_DIR/"
            fi
        done
    fi

    if [[ -f "$CONFIG_DIR/install-linux.sh" ]]; then
        chmod +x "$CONFIG_DIR/install-linux.sh"
    fi

    # Update the marmot script to use the config directory when installed elsewhere
    if [[ "$source_dir_abs" != "$install_dir_abs" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
            sudo sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$CONFIG_DIR\"|" "$INSTALL_DIR/marmot"
        else
            sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$CONFIG_DIR\"|" "$INSTALL_DIR/marmot"
        fi
    fi
}

# Verify installation
verify_installation() {
    if [[ -x "$INSTALL_DIR/marmot" ]] && [[ -f "$CONFIG_DIR/lib/core/common.sh" ]]; then
        # Test if marmot command works
        if "$INSTALL_DIR/marmot" --help > /dev/null 2>&1; then
            return 0
        else
            log_warning "marmot command installed but may not be working properly"
        fi
    else
        log_error "Installation verification failed"
        exit 1
    fi
}

# Add to PATH if needed
setup_path() {
    # Check if install directory is in PATH
    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        return
    fi

    # Only suggest PATH setup for custom directories
    if [[ "$INSTALL_DIR" != "/usr/local/bin" ]]; then
        log_warning "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "To use marmot from anywhere, add this line to your shell profile:"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
        echo "For example, add it to ~/.bashrc or ~/.zshrc"
    fi
}

print_usage_summary() {
    local action="$1"
    local new_version="$2"
    local previous_version="${3:-}"

    if [[ ${VERBOSE} -ne 1 ]]; then
        return
    fi

    echo ""

    local message="marmot ${action} successfully"

    if [[ "$action" == "updated" && -n "$previous_version" && -n "$new_version" && "$previous_version" != "$new_version" ]]; then
        message+=" (${previous_version} -> ${new_version})"
    elif [[ -n "$new_version" ]]; then
        message+=" (version ${new_version})"
    fi

    log_confirm "$message"

    echo ""
    echo "Usage:"
    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        echo "  marmot                # Interactive menu"
        echo "  marmot clean          # System cleanup"
        echo "  marmot uninstall      # Remove applications"
        echo "  marmot update         # Update marmot to the latest version"
        echo "  marmot remove         # Remove marmot from the system"
        echo "  marmot --version      # Show installed version"
        echo "  marmot --help         # Show this help message"
    else
        echo "  $INSTALL_DIR/marmot                # Interactive menu"
        echo "  $INSTALL_DIR/marmot clean          # System cleanup"
        echo "  $INSTALL_DIR/marmot uninstall      # Remove applications"
        echo "  $INSTALL_DIR/marmot update         # Update marmot to the latest version"
        echo "  $INSTALL_DIR/marmot remove         # Remove marmot from the system"
        echo "  $INSTALL_DIR/marmot --version      # Show installed version"
        echo "  $INSTALL_DIR/marmot --help         # Show this help message"
    fi
    echo ""
}

# Uninstall function
uninstall_marmot() {
    log_confirm "Uninstalling marmot"
    echo ""

    # Remove executable
    if [[ -f "$INSTALL_DIR/marmot" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
            log_admin "Admin access required"
            sudo rm -f "$INSTALL_DIR/marmot"
        else
            rm -f "$INSTALL_DIR/marmot"
        fi
        log_success "Removed marmot executable"
    fi

    if [[ -f "$INSTALL_DIR/marmot" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
            sudo rm -f "$INSTALL_DIR/marmot"
        else
            rm -f "$INSTALL_DIR/marmot"
        fi
        log_success "Removed marmot alias"
    fi

    # SAFETY CHECK: Verify config directory is safe to remove
    # Only allow removal of marmot-specific directories
    local is_safe=0

    # Additional safety: never delete system critical paths (check first)
    case "$CONFIG_DIR" in
        / | /usr | /usr/local | /usr/local/bin | /usr/local/lib | /usr/local/share | \
            /bin | /sbin | /etc | /var | /opt | "$HOME")
            is_safe=0
            ;;
        *)
            # Safe patterns: must be in user's home and end with 'marmot'
            if [[ "$CONFIG_DIR" == "$HOME/.config/marmot" ]] ||
                [[ "$CONFIG_DIR" == "$HOME"/.*/marmot ]]; then
                is_safe=1
            fi
            ;;
    esac

    # Ask before remarmotving config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        if [[ $is_safe -eq 0 ]]; then
            log_warning "Config directory $CONFIG_DIR is not safe to auto-remove"
            log_warning "Skipping automatic removal for safety"
            echo ""
            echo "Please manually review and remove marmot-specific files from:"
            echo "  $CONFIG_DIR"
        else
            echo ""
            read -p "Remove configuration directory $CONFIG_DIR? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$CONFIG_DIR"
                log_success "Removed configuration"
            else
                log_success "Configuration preserved"
            fi
        fi
    fi

    echo ""
    log_confirm "marmot uninstalled successfully"
}

# Main installation function
perform_install() {
    resolve_source_dir
    local source_version
    source_version="$(get_source_version || true)"

    check_requirements
    create_directories
    install_files
    verify_installation
    setup_path

    local installed_version
    installed_version="$(get_installed_version || true)"

    if [[ -z "$installed_version" ]]; then
        installed_version="$source_version"
    fi

    print_usage_summary "installed" "$installed_version"
}

perform_update() {
    check_requirements

    if command -v dpkg > /dev/null 2>&1 && dpkg -l marmot > /dev/null 2>&1; then
        # Try to use shared function if available (when running from installed marmot)
        resolve_source_dir 2> /dev/null || true
        if [[ -f "$SOURCE_DIR/lib/core/common.sh" ]]; then
            # shellcheck disable=SC1090,SC1091
            source "$SOURCE_DIR/lib/core/common.sh"
            # Update via apt would be here when implemented
            log_info "marmot is installed via package manager. Use apt to update."
        else
            log_info "Update via package manager:"
            echo "  sudo apt update"
            echo "  sudo apt install marmot"
        fi
        exit 0
    fi

    local installed_version
    installed_version="$(get_installed_version || true)"

    if [[ -z "$installed_version" ]]; then
        log_warning "marmot is not currently installed in $INSTALL_DIR. Running fresh installation."
        perform_install
        return
    fi

    resolve_source_dir
    local target_version
    target_version="$(get_source_version || true)"

    if [[ -z "$target_version" ]]; then
        log_error "Unable to determine the latest marmot version."
        exit 1
    fi

    if [[ "$installed_version" == "$target_version" ]]; then
        echo -e "${GREEN}✓${NC} Already on latest version ($installed_version)"
        exit 0
    fi

    # Update with minimal output (suppress info/success, show errors only)
    local old_verbose=$VERBOSE
    VERBOSE=0
    create_directories || {
        VERBOSE=$old_verbose
        log_error "Failed to create directories"
        exit 1
    }
    install_files || {
        VERBOSE=$old_verbose
        log_error "Failed to install files"
        exit 1
    }
    verify_installation || {
        VERBOSE=$old_verbose
        log_error "Failed to verify installation"
        exit 1
    }
    setup_path
    VERBOSE=$old_verbose

    local updated_version
    updated_version="$(get_installed_version || true)"

    if [[ -z "$updated_version" ]]; then
        updated_version="$target_version"
    fi

    echo -e "${GREEN}✓${NC} Updated to latest version ($updated_version)"
}

# Run requested action
parse_args "$@"

case "$ACTION" in
    update)
        perform_update
        ;;
    *)
        perform_install
        ;;
esac

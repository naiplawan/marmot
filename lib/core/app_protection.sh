#!/bin/bash
# marmot - Application Protection
# System critical and data-protected application lists

set -euo pipefail

if [[ -n "${marmot_APP_PROTECTION_LOADED:-}" ]]; then
    return 0
fi
readonly marmot_APP_PROTECTION_LOADED=1

_marmot_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${marmot_BASE_LOADED:-}" ]] && source "$_marmot_CORE_DIR/base.sh"

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
# macOS System Critical Components
# ============================================================================

readonly MACOS_SYSTEM_CRITICAL_BUNDLES=(
    "com.apple.*" # System essentials
    "loginwindow"
    "dock"
    "systempreferences"
    "finder"
    "safari"
    "keychain*"
    "security*"
    "bluetooth*"
    "wifi*"
    "network*"
    "tcc"
    "notification*"
    "accessibility*"
    "universalaccess*"
    "HIToolbox*"
    "textinput*"
    "TextInput*"
    "keyboard*"
    "Keyboard*"
    "inputsource*"
    "InputSource*"
    "keylayout*"
    "KeyLayout*"
    "GlobalPreferences"
    ".GlobalPreferences"
    # Input methods (critical for international users)
    "com.tencent.inputmethod.QQInput"
    "com.sogou.inputmethod.*"
    "com.baidu.inputmethod.*"
    "com.apple.inputmethod.*"
    "com.googlecode.rimeime.*"
    "im.rime.*"
    "org.pqrs.Karabiner*"
    "*.inputmethod"
    "*.InputMethod"
    "*IME"
    "com.apple.inputsource*"
    "com.apple.TextInputMenuAgent"
    "com.apple.TextInputSwitcher"
)

# ============================================================================
# Linux System Critical Components
# ============================================================================

readonly LINUX_CRITICAL_PACKAGES=(
    # Core system packages (apt/debian based)
    "apt"                     # Package manager
    "dpkg"                    # Package management
    "gnome-shell"             # Desktop shell
    "gnome-session"           # Session management
    "systemd"                 # Init system
    "linux-base"              # Kernel packages
    "coreutils"               # Essential utilities
    "bash"                    # Shell
    "sudo"                    # Privilege escalation
    "login"                   # Login manager
    "passwd"                  # Password management
    "shadow"                  # Password files
    "polkitd"                 # PolicyKit daemon

    # Desktop environment components
    "*gnome*"                 # GNOME components
    "*kde*"                   # KDE components
    "*xfce*"                  # XFCE components
    "*mate*"                  # MATE components

    # Display server
    "xorg-server*"
    "x11-*"
    "*wayland*"

    # Network management
    "network-manager*"
    "networkmanager*"
    "wicd*"
    "connman*"

    # Audio system
    "pulseaudio*"
    "alsa*"
    "pipewire*"
    "jackd*"

    # Package managers
    "apt*"
    "dpkg*"
    "snap*"
    "flatpak*"

    # Security
    "apparmor*"
    "selinux*"
    "firewalld*"
    "ufw*"

    # Virtualization
    "kvm*"
    "qemu*"
    "libvirt*"
    "virtualbox*"
    "docker*"
    "containerd*"
    "podman*"
)

# ============================================================================
# Common Protected Applications (both platforms)
# ============================================================================

# Apps with important data/licenses - protect during cleanup but allow uninstall
readonly DATA_PROTECTED_APPS=(
    # Password Managers & Security
    "1password"
    "1password-cli"
    "bitwarden"
    "bitwarden-cli"
    "keepassxc"
    "lastpass"
    "dashlane"
    "authy"
    "yubico-authenticator"
    "protonvpn"
    "nordvpn"
    "expressvpn"
    "openvpn"
    "wireguard"

    # Development Tools - IDEs & Editors
    "vscode"
    "code"
    "code-insiders"
    "intellij-idea"
    "pycharm"
    "webstorm"
    "goland"
    "clion"
    "datagrip"
    "rider"
    "sublime-text"
    "sublime-merge"
    "atom"
    "vim"
    "nvim"
    "emacs"
    "nano"
    "gedit"
    "kate"
    "xcode"
    "android-studio"
    "eclipse"
    "netbeans"

    # Development Tools - Database Clients
    "sequel-pro"
    "sequel-ace"
    "tableplus"
    "dbeaver"
    "navicat"
    "mongodb-compass"
    "redis-insight"
    "pgadmin"
    "mysql-workbench"
    "postbird"

    # Development Tools - API & Network
    "postman"
    "insomnia"
    "charles"
    "proxyman"
    "wireshark"
    "nmap"
    "burp-suite"
    "fiddler"

    # Development Tools - Git & Version Control
    "github-desktop"
    "gitkraken"
    "sourcetree"
    "tower"
    "git-cola"
    "gitg"
    "smartgit"

    # Development Tools - Terminal & Shell
    "iterm2"
    "alacritty"
    "kitty"
    "wezterm"
    "hyper"
    "warp"
    "termius"
    "putty"

    # Development Tools - Docker & Virtualization
    "docker"
    "docker-desktop"
    "virtualbox"
    "vmware"
    "parallels"
    "vagrant"
    "minikube"
    "kubernetes"

    # System Monitoring & Performance
    "istat-menus"
    "stats"
    "htop"
    "glances"
    "neofetch"
    "screenfetch"
    "monitorcontrol"
    "tinker tool"

    # Window Management & Productivity
    "bettertouchtool"
    "better-snap-tool"
    "moom"
    "spectacle"
    "rectangle"
    "amethyst"
    "caffeine"
    "alfred"
    "raycast"
    "quicksilver"
    "karabiner"
    "keyboard-maestro"

    # Note-Taking & Documentation
    "obsidian"
    "notion"
    "evernote"
    "onenote"
    "bear"
    "typora"
    "ulysses"
    "scrivener"
    "day-one"
    "logseq"
    "marginnote"
    "goodnotes"

    # Design & Creative Tools
    "adobe-creative-cloud"
    "photoshop"
    "illustrator"
    "figma"
    "sketch"
    "pixelmator"
    "affinity-designer"
    "affinity-photo"
    "blender"
    "gimp"
    "inkscape"
    "canva"
    "cinema-4d"
    "autodesk"

    # Communication & Collaboration
    "slack"
    "discord"
    "zoom"
    "teams"
    "telegram"
    "whatsapp"
    "skype"
    "webex"
    "spark"
    "airmail"

    # Task Management & Productivity
    "things"
    "todoist"
    "omnifocus"
    "trello"
    "asana"
    "clickup"
    "notion"
    "linear"

    # File Transfer & Sync
    "dropbox"
    "google-drive"
    "onedrive"
    "transmit"
    "forklift"
    "cyberduck"
    "filezilla"
    "synology-drive"

    # Media & Entertainment
    "spotify"
    "vlc"
    "plex"
    "iina"
    "mpv"
    "davinci-resolve"
    "final-cut-pro"
    "adobe-premiere-pro"
    "obs-studio"
    "audacity"
    "handbrake"
)

# ============================================================================
# Helper Functions
# ============================================================================

# Check if we're on macOS
is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

# Check if we're on Linux
is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

# Check whether a pattern matches (supports globs)
matches_pattern() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    # Use bash [[  ]] for glob pattern matching (works with variables in bash 3.2+)
    # shellcheck disable=SC2053  # allow glob pattern matching
    if [[ "$string" == $pattern ]]; then
        return 0
    fi
    return 1
}

# Check if app is a system component that should never be uninstalled (macOS)
should_protect_from_uninstall_macos() {
    local bundle_id="$1"
    for pattern in "${MACOS_SYSTEM_CRITICAL_BUNDLES[@]}"; do
        if matches_pattern "$bundle_id" "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check if package is critical on Linux
should_protect_from_uninstall_linux() {
    local package_name="$1"
    for pattern in "${LINUX_CRITICAL_PACKAGES[@]}"; do
        if matches_pattern "$package_name" "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check if app is a system component that should never be uninstalled
should_protect_from_uninstall() {
    local app_identifier="$1"

    if is_macos; then
        should_protect_from_uninstall_macos "$app_identifier"
    else
        should_protect_from_uninstall_linux "$app_identifier"
    fi
}

# Check if app data should be protected during cleanup (but app can be uninstalled)
should_protect_data() {
    local app_name="$1"

    # Convert to lowercase for case-insensitive comparison
    local app_lower="${app_name,,}"

    for pattern in "${DATA_PROTECTED_APPS[@]}"; do
        local pattern_lower="${pattern,,}"
        if matches_pattern "$app_lower" "$pattern_lower"; then
            return 0
        fi
    done

    # Also check system critical components
    if should_protect_from_uninstall "$app_identifier"; then
        return 0
    fi

    return 1
}

# ============================================================================
# macOS-specific Functions
# ============================================================================

# Find and list macOS app-related files
find_app_files_macos() {
    local bundle_id="$1"
    local app_name="$2"
    local -a files_to_clean=()

    # User-level files (no sudo required)

    # Application Support
    [[ -d ~/Library/Application\ Support/"$app_name" ]] && files_to_clean+=("$HOME/Library/Application Support/$app_name")
    [[ -d ~/Library/Application\ Support/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Application Support/$bundle_id")

    # Caches
    [[ -d ~/Library/Caches/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Caches/$bundle_id")
    [[ -d ~/Library/Caches/"$app_name" ]] && files_to_clean+=("$HOME/Library/Caches/$app_name")

    # Preferences
    [[ -f ~/Library/Preferences/"$bundle_id".plist ]] && files_to_clean+=("$HOME/Library/Preferences/$bundle_id.plist")
    [[ -d ~/Library/Preferences/ByHost ]] && while IFS= read -r -d '' pref; do
        files_to_clean+=("$pref")
    done < <(find ~/Library/Preferences/ByHost \( -name "$bundle_id*.plist" \) -print0 2> /dev/null)

    # Logs
    [[ -d ~/Library/Logs/"$app_name" ]] && files_to_clean+=("$HOME/Library/Logs/$app_name")
    [[ -d ~/Library/Logs/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Logs/$bundle_id")

    # Containers (sandboxed apps)
    [[ -d ~/Library/Containers/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Containers/$bundle_id")

    # Launch Agents (user-level)
    [[ -f ~/Library/LaunchAgents/"$bundle_id".plist ]] && files_to_clean+=("$HOME/Library/LaunchAgents/$bundle_id.plist")

    # Only print if array has elements
    if [[ ${#files_to_clean[@]} -gt 0 ]]; then
        printf '%s\n' "${files_to_clean[@]}"
    fi
}

# ============================================================================
# Linux-specific Functions
# ============================================================================

# Find and list Linux app-related files
find_app_files_linux() {
    local package_name="$1"
    local app_name="$2"
    local -a files_to_clean=()

    # Convert to lowercase for better matching
    local pkg_lower="${package_name,,}"
    local app_lower="${app_name,,}"

    # XDG Base Directory specification paths
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"

    # Configuration files
    [[ -d "$config_dir/$app_name" ]] && files_to_clean+=("$config_dir/$app_name")
    [[ -d "$config_dir/$package_name" ]] && files_to_clean+=("$config_dir/$package_name")

    # Match common variations
    for var in "$app_lower" "$pkg_lower"; do
        [[ -d "$config_dir" ]] && while IFS= read -r -d '' dir; do
            files_to_clean+=("$dir")
        done < <(find "$config_dir" -maxdepth 1 -type d -iname "*$var*" -print0 2> /dev/null)
    done

    # Data files
    [[ -d "$data_dir/$app_name" ]] && files_to_clean+=("$data_dir/$app_name")
    [[ -d "$data_dir/$package_name" ]] && files_to_clean+=("$data_dir/$package_name")

    for var in "$app_lower" "$pkg_lower"; do
        [[ -d "$data_dir" ]] && while IFS= read -r -d '' dir; do
            files_to_clean+=("$dir")
        done < <(find "$data_dir" -maxdepth 1 -type d -iname "*$var*" -print0 2> /dev/null)
    done

    # Cache files
    [[ -d "$cache_dir/$app_name" ]] && files_to_clean+=("$cache_dir/$app_name")
    [[ -d "$cache_dir/$package_name" ]] && files_to_clean+=("$cache_dir/$package_name")

    for var in "$app_lower" "$pkg_lower"; do
        [[ -d "$cache_dir" ]] && while IFS= read -r -d '' dir; do
            files_to_clean+=("$dir")
        done < <(find "$cache_dir" -maxdepth 1 -type d -iname "*$var*" -print0 2> /dev/null)
    done

    # State files
    [[ -d "$state_dir/$app_name" ]] && files_to_clean+=("$state_dir/$app_name")
    [[ -d "$state_dir/$package_name" ]] && files_to_clean+=("$state_dir/$package_name")

    for var in "$app_lower" "$pkg_lower"; do
        [[ -d "$state_dir" ]] && while IFS= read -r -d '' dir; do
            files_to_clean+=("$dir")
        done < <(find "$state_dir" -maxdepth 1 -type d -iname "*$var*" -print0 2> /dev/null)
    done

    # Traditional Unix-style dotfiles
    [[ -d "$HOME/.$app_name" ]] && files_to_clean+=("$HOME/.$app_name")
    [[ -d "$HOME/.$package_name" ]] && files_to_clean+=("$HOME/.$package_name")
    [[ -f "$HOME/.${app_name}rc" ]] && files_to_clean+=("$HOME/.${app_name}rc")
    [[ -f "$HOME/.${package_name}rc" ]] && files_to_clean+=("$HOME/.${package_name}rc")

    # Match common config file variations
    for var in "$app_lower" "$pkg_lower"; do
        [[ -f "$HOME/.$var" ]] && files_to_clean+=("$HOME/.$var")
        [[ -f "$HOME/.$var"rc ]] && files_to_clean+=("$HOME/.$var"rc")
        [[ -f "$HOME/.$var"rc ]] && files_to_clean+=("$HOME/.$var"rc")
        [[ -f "$HOME/.$var"conf ]] && files_to_clean+=("$HOME/.$var"conf")
        [[ -f "$HOME/.$var"config ]] && files_to_clean+=("$HOME/.$var"config")
    done

    # Desktop entries
    [[ -f "$HOME/.local/share/applications/$app_name.desktop" ]] && files_to_clean+=("$HOME/.local/share/applications/$app_name.desktop")
    [[ -f "$HOME/.local/share/applications/$package_name.desktop" ]] && files_to_clean+=("$HOME/.local/share/applications/$package_name.desktop")

    for var in "$app_lower" "$pkg_lower"; do
        [[ -d "$HOME/.local/share/applications" ]] && while IFS= read -r -d '' file; do
            files_to_clean+=("$file")
        done < <(find "$HOME/.local/share/applications" -maxdepth 1 -name "*$var*.desktop" -print0 2> /dev/null)
    done

    # Application-specific data
    case "$app_lower" in
        "vscode"|"code"|"visual-studio-code")
            [[ -d "$HOME/.vscode" ]] && files_to_clean+=("$HOME/.vscode")
            [[ -d "$HOME/.config/Code" ]] && files_to_clean+=("$HOME/.config/Code")
            [[ -d "$HOME/.config/Code - OSS" ]] && files_to_clean+=("$HOME/.config/Code - OSS")
            [[ -d "$HOME/.vscode-oss" ]] && files_to_clean+=("$HOME/.vscode-oss")
            ;;
        "slack"|"discord"|"telegram"|"whatsapp")
            [[ -d "$HOME/.config/$app_lower" ]] && files_to_clean+=("$HOME/.config/$app_lower")
            [[ -d "$cache_dir/$app_lower" ]] && files_to_clean+=("$cache_dir/$app_lower")
            [[ -d "$data_dir/$app_lower" ]] && files_to_clean+=("$data_dir/$app_lower")
            ;;
        "spotify")
            [[ -d "$HOME/.cache/spotify" ]] && files_to_clean+=("$HOME/.cache/spotify")
            [[ -d "$HOME/.config/spotify" ]] && files_to_clean+=("$HOME/.config/spotify")
            [[ -d "$HOME/.local/share/spotify" ]] && files_to_clean+=("$HOME/.local/share/spotify")
            ;;
        "docker")
            [[ -d "$HOME/.docker" ]] && files_to_clean+=("$HOME/.docker")
            [[ -f "$HOME/.docker/config.json" ]] && files_to_clean+=("$HOME/.docker/config.json")
            ;;
        "git"|"github-desktop")
            [[ -f "$HOME/.gitconfig" ]] && files_to_clean+=("$HOME/.gitconfig")
            [[ -d "$HOME/.config/git" ]] && files_to_clean+=("$HOME/.config/git")
            [[ -d "$HOME/.github-desktop" ]] && files_to_clean+=("$HOME/.github-desktop")
            ;;
        "firefox"|"mozilla")
            [[ -d "$HOME/.mozilla" ]] && files_to_clean+=("$HOME/.mozilla")
            [[ -d "$HOME/.cache/mozilla" ]] && files_to_clean+=("$HOME/.cache/mozilla")
            [[ -d "$HOME/.config/mozilla" ]] && files_to_clean+=("$HOME/.config/mozilla")
            ;;
        "chrome"|"google-chrome")
            [[ -d "$HOME/.config/google-chrome" ]] && files_to_clean+=("$HOME/.config/google-chrome")
            [[ -d "$HOME/.cache/google-chrome" ]] && files_to_clean+=("$HOME/.cache/google-chrome")
            [[ -d "$HOME/.config/google-chrome-beta" ]] && files_to_clean+=("$HOME/.config/google-chrome-beta")
            [[ -d "$HOME/.cache/google-chrome-beta" ]] && files_to_clean+=("$HOME/.cache/google-chrome-beta")
            ;;
    esac

    # Only print if array has elements
    if [[ ${#files_to_clean[@]} -gt 0 ]]; then
        printf '%s\n' "${files_to_clean[@]}"
    fi
}

# Find system-level Linux package files (requires sudo)
find_app_system_files_linux() {
    local package_name="$1"
    local app_name="$2"
    local -a system_files=()

    # System configuration
    [[ -d "/etc/$package_name" ]] && system_files+=("/etc/$package_name")
    [[ -d "/etc/$app_name" ]] && system_files+=("/etc/$app_name")

    # System data
    [[ -d "/usr/share/$package_name" ]] && system_files+=("/usr/share/$package_name")
    [[ -d "/usr/share/$app_name" ]] && system_files+=("/usr/share/$app_name")

    # System libraries
    [[ -d "/usr/lib/$package_name" ]] && system_files+=("/usr/lib/$package_name")
    [[ -d "/usr/lib64/$package_name" ]] && system_files+=("/usr/lib64/$package_name")

    # System config files
    [[ -f "/etc/$package_name.conf" ]] && system_files+=("/etc/$package_name.conf")
    [[ -f "/etc/$app_name.conf" ]] && system_files+=("/etc/$app_name.conf")
    [[ -f "/etc/default/$package_name" ]] && system_files+=("/etc/default/$package_name")

    # systemd service files
    [[ -f "/etc/systemd/system/$package_name.service" ]] && system_files+=("/etc/systemd/system/$package_name.service")
    [[ -f "/etc/systemd/user/$package_name.service" ]] && system_files+=("/etc/systemd/user/$package_name.service")
    [[ -f "/lib/systemd/system/$package_name.service" ]] && system_files+=("/lib/systemd/system/$package_name.service")

    # System logs
    [[ -d "/var/log/$package_name" ]] && system_files+=("/var/log/$package_name")
    [[ -d "/var/log/$app_name" ]] && system_files+=("/var/log/$app_name")

    # Temporary files
    [[ -d "/tmp/$package_name" ]] && system_files+=("/tmp/$package_name")
    [[ -d "/tmp/$app_name" ]] && system_files+=("/tmp/$app_name")

    # Only print if array has elements
    if [[ ${#system_files[@]} -gt 0 ]]; then
        printf '%s\n' "${system_files[@]}"
    fi
}

# ============================================================================
# Cross-platform Wrapper Functions
# ============================================================================

# Find and list app-related files (platform-agnostic wrapper)
find_app_files() {
    local app_identifier="$1"
    local app_name="$2"

    if is_macos; then
        find_app_files_macos "$app_identifier" "$app_name"
    else
        find_app_files_linux "$app_identifier" "$app_name"
    fi
}

# Find system-level app files (platform-agnostic wrapper)
find_app_system_files() {
    local app_identifier="$1"
    local app_name="$2"

    if is_macos; then
        find_app_system_files_macos "$app_identifier" "$app_name"
    else
        find_app_system_files_linux "$app_identifier" "$app_name"
    fi
}

# Force quit an application (cross-platform)
force_kill_app() {
    local app_name="$1"

    # Try process name first
    if pgrep -x "$app_name" > /dev/null 2>&1; then
        pkill -x "$app_name" 2> /dev/null || true
        sleep 2

        # Force kill if still running
        if pgrep -x "$app_name" > /dev/null 2>&1; then
            pkill -9 -x "$app_name" 2> /dev/null || true
        fi
    fi

    # Try common variations
    local -a variations=("$app_name" "${app_name,,}" "${app_name^}" "${app_name,,}"-bin)
    for proc in "${variations[@]}"; do
        if pgrep "$proc" > /dev/null 2>&1; then
            pkill "$proc" 2> /dev/null || true
            sleep 1
            pkill -9 "$proc" 2> /dev/null || true
        fi
    done
}

# Calculate total size of files
calculate_total_size() {
    local files="$1"
    local total_kb=0

    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local size_kb
            size_kb=$(get_path_size_kb "$file")
            ((total_kb += size_kb))
        fi
    done <<< "$files"

    echo "$total_kb"
}

# ============================================================================
# Legacy Functions (for backward compatibility)
# ============================================================================

# Legacy function - preserved for backward compatibility
readonly PRESERVED_BUNDLE_PATTERNS=("${MACOS_SYSTEM_CRITICAL_BUNDLES[@]}" "${DATA_PROTECTED_APPS[@]}")

# Check whether a bundle ID matches a pattern (legacy function)
bundle_matches_pattern() {
    local bundle_id="$1"
    local pattern="$2"
    matches_pattern "$bundle_id" "$pattern"
}

# Find system-level app files (macOS specific - for backward compatibility)
find_app_system_files_macos() {
    local bundle_id="$1"
    local app_name="$2"
    local -a system_files=()

    # System Application Support
    [[ -d /Library/Application\ Support/"$app_name" ]] && system_files+=("/Library/Application Support/$app_name")
    [[ -d /Library/Application\ Support/"$bundle_id" ]] && system_files+=("/Library/Application Support/$bundle_id")

    # System Launch Agents
    [[ -f /Library/LaunchAgents/"$bundle_id".plist ]] && system_files+=("/Library/LaunchAgents/$bundle_id.plist")

    # System Launch Daemons
    [[ -f /Library/LaunchDaemons/"$bundle_id".plist ]] && system_files+=("/Library/LaunchDaemons/$bundle_id.plist")

    # Only print if array has elements
    if [[ ${#system_files[@]} -gt 0 ]]; then
        printf '%s\n' "${system_files[@]}"
    fi
}

#!/bin/bash
# Package Manager Cleanup Module (Cross-platform)

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
# Homebrew Cleanup (macOS)
# ============================================================================

# Clean orphaned cask records (apps manually deleted but cask record remains)
# Uses 2-day cache to avoid expensive brew info calls
# Cache format: cask_name|AppName.app
clean_orphaned_casks() {
    is_macos || return 0
    command -v brew > /dev/null 2>&1 || return 0

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Scanning orphaned casks..."
    fi

    local cache_dir="$HOME/.cache/marmot"
    local cask_cache="$cache_dir/cask_apps.cache"
    local use_cache=false

    # Check if cache is valid (less than 2 days old)
    if [[ -f "$cask_cache" ]]; then
        local cache_age=$(($(date +%s) - $(get_file_mtime "$cask_cache")))
        if [[ $cache_age -lt 172800 ]]; then
            use_cache=true
        fi
    fi

    local orphaned_casks=()
    if [[ "$use_cache" == "true" ]]; then
        # Use cached cask → app mapping to avoid expensive brew info calls
        while IFS='|' read -r cask app_name; do
            [[ ! -e "/Applications/$app_name" ]] && orphaned_casks+=("$cask")
        done < "$cask_cache"
    else
        # Rebuild cache: query all installed casks and extract app names
        mkdir -p "$cache_dir"
        # Remove stale cache if it exists but has permission issues
        rm -f "$cask_cache" 2> /dev/null || true
        true > "$cask_cache"

        while IFS= read -r cask; do
            # Get app path from cask info with timeout protection (expensive call, hence caching)
            local cask_info
            cask_info=$(run_with_timeout 10 brew info --cask "$cask" 2> /dev/null || true)

            # Extract app name from "AppName.app (App)" format in cask info output
            local app_name
            app_name=$(echo "$cask_info" | grep -E '\.app \(App\)' | head -1 | sed -E 's/^[[:space:]]*//' | sed -E 's/ \(App\).*//' || true)

            # Skip if no app artifact (might be a utility package like fonts)
            [[ -z "$app_name" ]] && continue

            # Save to cache for future runs
            echo "$cask|$app_name" >> "$cask_cache"

            # Check if app exists in /Applications
            [[ ! -e "/Applications/$app_name" ]] && orphaned_casks+=("$cask")
        done < <(brew list --cask 2> /dev/null || true)
    fi

    # Remove orphaned casks if found and sudo session is still valid
    if [[ ${#orphaned_casks[@]} -gt 0 ]]; then
        # Check if sudo session is still valid (without prompting)
        if sudo -n true 2> /dev/null; then
            if [[ -t 1 ]]; then
                stop_inline_spinner
                echo -e "  ${BLUE}${ICON_ARROW}${NC} Removing orphaned Homebrew casks (may require password for certain apps)"
                marmot_SPINNER_PREFIX="    " start_inline_spinner "Cleaning..."
            fi

            local removed_casks=0
            for cask in "${orphaned_casks[@]}"; do
                if brew uninstall --cask "$cask" --force > /dev/null 2>&1; then
                    ((removed_casks++))
                fi
            done

            if [[ -t 1 ]]; then stop_inline_spinner; fi

            [[ $removed_casks -gt 0 ]] && echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Removed $removed_casks orphaned cask(s)"
        else
            # Sudo session expired - inform user to run brew manually
            if [[ -t 1 ]]; then stop_inline_spinner; fi
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} Found ${#orphaned_casks[@]} orphaned casks (sudo expired, run ${GRAY}brew list --cask${NC} to check)"
        fi
    else
        if [[ -t 1 ]]; then stop_inline_spinner; fi
    fi
}

# Clean Homebrew caches and remove orphaned dependencies
# Skips if run within 2 days, runs cleanup/autoremove in parallel with 120s timeout
# Env: MO_BREW_TIMEOUT, DRY_RUN
clean_homebrew() {
    is_macos || return 0
    command -v brew > /dev/null 2>&1 || return 0

    # Dry run mode - just indicate what would happen
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}→${NC} Homebrew (would cleanup and autoremove)"
        return 0
    fi

    # Smart caching: check if brew cleanup was run recently (within 2 days)
    local brew_cache_file="${HOME}/.cache/marmot/brew_last_cleanup"
    local cache_valid_days=2
    local should_skip=false

    if [[ -f "$brew_cache_file" ]]; then
        local last_cleanup
        last_cleanup=$(cat "$brew_cache_file" 2> /dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local time_diff=$((current_time - last_cleanup))
        local days_diff=$((time_diff / 86400))

        if [[ $days_diff -lt $cache_valid_days ]]; then
            should_skip=true
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew (cleaned ${days_diff}d ago, skipped)"
        fi
    fi

    [[ "$should_skip" == "true" ]] && return 0

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Homebrew cleanup and autoremove..."
    fi

    local timeout_seconds=${MO_BREW_TIMEOUT:-120}

    # Run brew cleanup and autoremove in parallel for performance
    local brew_tmp_file autoremove_tmp_file
    brew_tmp_file=$(create_temp_file)
    autoremove_tmp_file=$(create_temp_file)

    (brew cleanup > "$brew_tmp_file" 2>&1) &
    local brew_pid=$!

    (brew autoremove > "$autoremove_tmp_file" 2>&1) &
    local autoremove_pid=$!

    local elapsed=0
    local brew_done=false
    local autoremove_done=false

    # Wait for both to complete or timeout
    while [[ "$brew_done" == "false" ]] || [[ "$autoremove_done" == "false" ]]; do
        if [[ $elapsed -ge $timeout_seconds ]]; then
            kill -TERM $brew_pid $autoremove_pid 2> /dev/null || true
            break
        fi

        kill -0 $brew_pid 2> /dev/null || brew_done=true
        kill -0 $autoremove_pid 2> /dev/null || autoremove_done=true

        sleep 1
        ((elapsed++))
    done

    # Wait for processes to finish
    local brew_success=false
    if wait $brew_pid 2> /dev/null; then
        brew_success=true
    fi

    local autoremove_success=false
    if wait $autoremove_pid 2> /dev/null; then
        autoremove_success=true
    fi

    if [[ -t 1 ]]; then stop_inline_spinner; fi

    # Process cleanup output and extract metrics
    if [[ "$brew_success" == "true" && -f "$brew_tmp_file" ]]; then
        local brew_output
        brew_output=$(cat "$brew_tmp_file" 2> /dev/null || echo "")
        local removed_count freed_space
        removed_count=$(printf '%s\n' "$brew_output" | grep -c "Removing:" 2> /dev/null || true)
        freed_space=$(printf '%s\n' "$brew_output" | grep -o "[0-9.]*[KMGT]B freed" 2> /dev/null | tail -1 || true)

        if [[ $removed_count -gt 0 ]] || [[ -n "$freed_space" ]]; then
            if [[ -n "$freed_space" ]]; then
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew cleanup ${GREEN}($freed_space)${NC}"
            else
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew cleanup (${removed_count} items)"
            fi
        fi
    elif [[ $elapsed -ge $timeout_seconds ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Homebrew cleanup timed out (run ${GRAY}brew cleanup${NC} manually)"
    fi

    # Process autoremove output - only show if packages were removed
    if [[ "$autoremove_success" == "true" && -f "$autoremove_tmp_file" ]]; then
        local autoremove_output
        autoremove_output=$(cat "$autoremove_tmp_file" 2> /dev/null || echo "")
        local removed_packages
        removed_packages=$(printf '%s\n' "$autoremove_output" | grep -c "^Uninstalling" 2> /dev/null || true)

        if [[ $removed_packages -gt 0 ]]; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed orphaned dependencies (${removed_packages} packages)"
        fi
    elif [[ $elapsed -ge $timeout_seconds ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Autoremove timed out (run ${GRAY}brew autoremove${NC} manually)"
    fi

    # Update cache timestamp on successful completion
    if [[ "$brew_success" == "true" || "$autoremove_success" == "true" ]]; then
        mkdir -p "$(dirname "$brew_cache_file")"
        date +%s > "$brew_cache_file"
    fi
}

# ============================================================================
# APT Package Manager Cleanup (Linux)
# ============================================================================

# Clean APT package cache and remove obsolete packages
clean_apt() {
    is_linux || return 0
    command -v apt > /dev/null 2>&1 || return 0

    # Only run if we have sudo privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} APT cleanup requires sudo privileges"
        return 0
    fi

    # Dry run mode - just indicate what would happen
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}→${NC} APT (would clean cache and autoremove)"
        return 0
    fi

    # Smart caching: check if apt cleanup was run recently (within 2 days)
    local apt_cache_file="${HOME}/.cache/marmot/apt_last_cleanup"
    local cache_valid_days=2
    local should_skip=false

    if [[ -f "$apt_cache_file" ]]; then
        local last_cleanup
        last_cleanup=$(cat "$apt_cache_file" 2> /dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local time_diff=$((current_time - last_cleanup))
        local days_diff=$((time_diff / 86400))

        if [[ $days_diff -lt $cache_valid_days ]]; then
            should_skip=true
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} APT (cleaned ${days_diff}d ago, skipped)"
        fi
    fi

    [[ "$should_skip" == "true" ]] && return 0

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "APT cleanup and autoremove..."
    fi

    local timeout_seconds=${MO_BREW_TIMEOUT:-120}

    # Run apt commands in parallel for performance
    local clean_tmp_file autoremove_tmp_file
    clean_tmp_file=$(create_temp_file)
    autoremove_tmp_file=$(create_temp_file)

    # Update package list first
    if [[ -t 1 ]]; then
        stop_inline_spinner
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Updating package list..."
    fi
    (apt-get update > /dev/null 2>&1) &
    local update_pid=$!

    local elapsed=0
    while kill -0 $update_pid 2> /dev/null && [[ $elapsed -lt 30 ]]; do
        sleep 1
        ((elapsed++))
    done

    # Kill if still running after timeout
    if kill -0 $update_pid 2> /dev/null; then
        kill -TERM $update_pid 2> /dev/null || true
        wait $update_pid 2> /dev/null || true
    else
        wait $update_pid 2> /dev/null || true
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Cleaning APT cache..."
    fi

    # Run apt clean and autoremove
    (apt-get clean > "$clean_tmp_file" 2>&1) &
    local clean_pid=$!

    (apt-get autoremove -y > "$autoremove_tmp_file" 2>&1) &
    local autoremove_pid=$!

    elapsed=0
    local clean_done=false
    local autoremove_done=false

    # Wait for both to complete or timeout
    while [[ "$clean_done" == "false" ]] || [[ "$autoremove_done" == "false" ]]; do
        if [[ $elapsed -ge $timeout_seconds ]]; then
            kill -TERM $clean_pid $autoremove_pid 2> /dev/null || true
            break
        fi

        kill -0 $clean_pid 2> /dev/null || clean_done=true
        kill -0 $autoremove_pid 2> /dev/null || autoremove_done=true

        sleep 1
        ((elapsed++))
    done

    # Wait for processes to finish
    local clean_success=false
    if wait $clean_pid 2> /dev/null; then
        clean_success=true
    fi

    local autoremove_success=false
    if wait $autoremove_pid 2> /dev/null; then
        autoremove_success=true
    fi

    if [[ -t 1 ]]; then stop_inline_spinner; fi

    # Process clean output
    if [[ "$clean_success" == "true" ]]; then
        # Calculate space freed from cache
        local cache_size
        cache_size=$(du -sh /var/cache/apt/archives 2> /dev/null | awk '{print $1}' || echo "0")
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} APT cache cleaned (${cache_size} freed)"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} APT clean failed (run ${GRAY}sudo apt-get clean${NC} manually)"
    fi

    # Process autoremove output
    if [[ "$autoremove_success" == "true" && -f "$autoremove_tmp_file" ]]; then
        local autoremove_output
        autoremove_output=$(cat "$autoremove_tmp_file" 2> /dev/null || echo "")
        local removed_packages
        removed_packages=$(printf '%s\n' "$autoremove_output" | grep -c "^Removing" 2> /dev/null || echo "0")

        if [[ $removed_packages -gt 0 ]]; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed ${removed_packages} obsolete packages"
        fi
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} APT autoremove failed (run ${GRAY}sudo apt-get autoremove${NC} manually)"
    fi

    # Update cache timestamp on successful completion
    if [[ "$clean_success" == "true" || "$autoremove_success" == "true" ]]; then
        mkdir -p "$(dirname "$apt_cache_file")"
        date +%s > "$apt_cache_file"
    fi
}

# ============================================================================
# Other Package Managers (Linux)
# ============================================================================

# Clean DNF package manager (Fedora/RHEL)
clean_dnf() {
    is_linux || return 0
    command -v dnf > /dev/null 2>&1 || return 0

    # Only run if we have sudo privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} DNF cleanup requires sudo privileges"
        return 0
    fi

    # Dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}→${NC} DNF (would clean cache)"
        return 0
    fi

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "DNF cleanup..."
    fi

    if sudo dnf clean all -y > /dev/null 2>&1; then
        if [[ -t 1 ]]; then stop_inline_spinner; fi
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} DNF cache cleaned"
    else
        if [[ -t 1 ]]; then stop_inline_spinner; fi
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} DNF clean failed"
    fi
}

# Clean Pacman package manager (Arch Linux)
clean_pacman() {
    is_linux || return 0
    command -v pacman > /dev/null 2>&1 || return 0

    # Only run if we have sudo privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Pacman cleanup requires sudo privileges"
        return 0
    fi

    # Dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}→${NC} Pacman (would clean cache and remove orphans)"
        return 0
    fi

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Pacman cleanup..."
    fi

    local cleaned=false

    # Clean package cache
    if sudo pacman -Scc --noconfirm > /dev/null 2>&1; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Pacman cache cleaned"
        cleaned=true
    fi

    # Remove orphan packages
    local orphans
    orphans=$(pacman -Qtdq 2> /dev/null || true)
    if [[ -n "$orphans" ]]; then
        if sudo pacman -Rns $orphans --noconfirm > /dev/null 2>&1; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed orphan packages"
            cleaned=true
        fi
    fi

    if [[ -t 1 ]]; then stop_inline_spinner; fi

    if [[ "$cleaned" == "false" ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Pacman cleanup failed"
    fi
}

# Clean Zypper package manager (openSUSE)
clean_zypper() {
    is_linux || return 0
    command -v zypper > /dev/null 2>&1 || return 0

    # Only run if we have sudo privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Zypper cleanup requires sudo privileges"
        return 0
    fi

    # Dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}→${NC} Zypper (would clean cache)"
        return 0
    fi

    if [[ -t 1 ]]; then
        marmot_SPINNER_PREFIX="  " start_inline_spinner "Zypper cleanup..."
    fi

    if sudo zypper clean -a > /dev/null 2>&1; then
        if [[ -t 1 ]]; then stop_inline_spinner; fi
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Zypper cache cleaned"
    else
        if [[ -t 1 ]]; then stop_inline_spinner; fi
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Zypper clean failed"
    fi
}

# ============================================================================
# Main Package Manager Cleanup Function
# ============================================================================

# Clean all package managers based on platform
clean_package_managers() {
    if is_macos; then
        # macOS: Use Homebrew
        clean_orphaned_casks
        clean_homebrew
    else
        # Linux: Use appropriate package manager
        clean_apt
        clean_dnf
        clean_pacman
        clean_zypper
    fi
}

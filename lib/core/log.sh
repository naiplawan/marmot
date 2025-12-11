#!/bin/bash
# marmot - Logging System
# Centralized logging with rotation support

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${marmot_LOG_LOADED:-}" ]]; then
    return 0
fi
readonly marmot_LOG_LOADED=1

# Ensure base.sh is loaded for colors and icons
if [[ -z "${marmot_BASE_LOADED:-}" ]]; then
    _marmot_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/core/base.sh
    source "$_marmot_CORE_DIR/base.sh"
fi

# ============================================================================
# Logging Configuration
# ============================================================================

readonly LOG_FILE="${HOME}/.config/marmot/marmot.log"
readonly LOG_MAX_SIZE_DEFAULT=1048576 # 1MB

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2> /dev/null || true

# ============================================================================
# Log Rotation
# ============================================================================

# Rotate log file if it exceeds max size
# Called once at module load, not per log entry
rotate_log_once() {
    # Skip if already checked this session
    [[ -n "${marmot_LOG_ROTATED:-}" ]] && return 0
    export marmot_LOG_ROTATED=1

    local max_size="${marmot_MAX_LOG_SIZE:-$LOG_MAX_SIZE_DEFAULT}"
    if [[ -f "$LOG_FILE" ]] && [[ $(get_file_size "$LOG_FILE") -gt "$max_size" ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old" 2> /dev/null || true
        touch "$LOG_FILE" 2> /dev/null || true
    fi
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log informational message
# Args: $1 - message
log_info() {
    echo -e "${BLUE}$1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2> /dev/null || true
}

# Log success message
# Args: $1 - message
log_success() {
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE" 2> /dev/null || true
}

# Log warning message
# Args: $1 - message
log_warning() {
    echo -e "${YELLOW}$1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2> /dev/null || true
}

# Log error message
# Args: $1 - message
log_error() {
    echo -e "${RED}${ICON_ERROR}${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2> /dev/null || true
}

# Debug logging - only shown when MAR_DEBUG=1
# Args: $@ - debug message components
debug_log() {
    if [[ "${MAR_DEBUG:-}" == "1" ]]; then
        echo -e "${GRAY}[DEBUG]${NC} $*" >&2
    fi
}

# ============================================================================
# Command Execution Wrappers
# ============================================================================

# Run command silently, ignore errors
# Args: $@ - command and arguments
run_silent() {
    "$@" > /dev/null 2>&1 || true
}

# Run command with error logging
# Args: $@ - command and arguments
# Returns: command exit code
run_logged() {
    local cmd="$1"
    if ! "$@" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
        log_warning "Command failed: $cmd"
        return 1
    fi
    return 0
}

# ============================================================================
# Formatted Output
# ============================================================================

# Print formatted summary block with heading and details
# Args: $1=status (ignored), $2=heading, $@=details
print_summary_block() {
    local heading=""
    local -a details=()
    local saw_heading=false

    # Parse arguments
    for arg in "$@"; do
        if [[ "$saw_heading" == "false" ]]; then
            saw_heading=true
            heading="$arg"
        else
            details+=("$arg")
        fi
    done

    local divider="======================================================================"

    # Print with dividers
    echo ""
    echo "$divider"
    if [[ -n "$heading" ]]; then
        echo -e "${BLUE}${heading}${NC}"
    fi

    # Print details
    for detail in "${details[@]}"; do
        [[ -z "$detail" ]] && continue
        echo -e "${detail}"
    done
    echo "$divider"
}

# ============================================================================
# Initialize Logging
# ============================================================================

# Perform log rotation check on module load
rotate_log_once

#!/bin/bash
# System Health Check - JSON Generator (Cross-platform)
# Extracted from tasks.sh

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

# Ensure dependencies are loaded (only if running standalone)
if [[ -z "${marmot_FILE_OPS_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    source "$SCRIPT_DIR/lib/core/file_ops.sh"
fi

# Get memory info in GB
get_memory_info() {
    local total_bytes used_gb total_gb

    if is_macos; then
        # macOS memory info
        # Total memory
        total_bytes=$(sysctl -n hw.memsize 2> /dev/null || echo "0")
        total_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes / (1024*1024*1024)}" 2> /dev/null || echo "0")
        [[ -z "$total_gb" || "$total_gb" == "" ]] && total_gb="0"

        # Used memory from vm_stat
        local vm_output active wired compressed page_size
        vm_output=$(vm_stat 2> /dev/null || echo "")
        page_size=4096

        active=$(echo "$vm_output" | awk '/Pages active:/ {print $NF}' | tr -d '.' 2> /dev/null || echo "0")
        wired=$(echo "$vm_output" | awk '/Pages wired down:/ {print $NF}' | tr -d '.' 2> /dev/null || echo "0")
        compressed=$(echo "$vm_output" | awk '/Pages occupied by compressor:/ {print $NF}' | tr -d '.' 2> /dev/null || echo "0")

        active=${active:-0}
        wired=${wired:-0}
        compressed=${compressed:-0}

        local used_bytes=$(((active + wired + compressed) * page_size))
        used_gb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / (1024*1024*1024)}" 2> /dev/null || echo "0")
        [[ -z "$used_gb" || "$used_gb" == "" ]] && used_gb="0"
    else
        # Linux memory info from /proc/meminfo
        local meminfo_file="/proc/meminfo"
        if [[ -f "$meminfo_file" ]]; then
            local memtotal memavailable
            memtotal=$(awk '/^MemTotal:/ {print $2}' "$meminfo_file" 2> /dev/null || echo "0")
            memavailable=$(awk '/^MemAvailable:/ {print $2}' "$meminfo_file" 2> /dev/null || echo "0")

            # Fallback if MemAvailable not available (older kernels)
            if [[ "$memavailable" == "0" ]]; then
                local memfree buffers cached
                memfree=$(awk '/^MemFree:/ {print $2}' "$meminfo_file" 2> /dev/null || echo "0")
                buffers=$(awk '/^Buffers:/ {print $2}' "$meminfo_file" 2> /dev/null || echo "0")
                cached=$(awk '/^Cached:/ {print $2}' "$meminfo_file" 2> /dev/null || echo "0")
                memavailable=$((memfree + buffers + cached))
            fi

            # Convert from KB to GB
            total_gb=$(awk "BEGIN {printf \"%.2f\", $memtotal / 1024 / 1024}" 2> /dev/null || echo "0")
            local available_gb=$(awk "BEGIN {printf \"%.2f\", $memavailable / 1024 / 1024}" 2> /dev/null || echo "0")
            used_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb - $available_gb}" 2> /dev/null || echo "0")

            [[ -z "$total_gb" || "$total_gb" == "" ]] && total_gb="0"
            [[ -z "$used_gb" || "$used_gb" == "" ]] && used_gb="0"
        else
            total_gb="0"
            used_gb="0"
        fi
    fi

    echo "$used_gb $total_gb"
}

# Get disk info
get_disk_info() {
    local home="${HOME:-/}"
    local df_output total_gb used_gb used_percent

    df_output=$(command df -k "$home" 2> /dev/null | tail -1)

    local total_kb used_kb
    total_kb=$(echo "$df_output" | awk '{print $2}' 2> /dev/null || echo "0")
    used_kb=$(echo "$df_output" | awk '{print $3}' 2> /dev/null || echo "0")

    total_kb=${total_kb:-0}
    used_kb=${used_kb:-0}
    [[ "$total_kb" == "0" ]] && total_kb=1 # Avoid division by zero

    total_gb=$(awk "BEGIN {printf \"%.2f\", $total_kb / (1024*1024)}" 2> /dev/null || echo "0")
    used_gb=$(awk "BEGIN {printf \"%.2f\", $used_kb / (1024*1024)}" 2> /dev/null || echo "0")
    used_percent=$(awk "BEGIN {printf \"%.1f\", ($used_kb / $total_kb) * 100}" 2> /dev/null || echo "0")

    [[ -z "$total_gb" || "$total_gb" == "" ]] && total_gb="0"
    [[ -z "$used_gb" || "$used_gb" == "" ]] && used_gb="0"
    [[ -z "$used_percent" || "$used_percent" == "" ]] && used_percent="0"

    echo "$used_gb $total_gb $used_percent"
}

# Get uptime in days
get_uptime_days() {
    local uptime_days

    if is_macos; then
        # macOS uptime
        local boot_output boot_time
        boot_output=$(sysctl -n kern.boottime 2> /dev/null || echo "")
        boot_time=$(echo "$boot_output" | sed -n 's/.*sec = \([0-9]*\).*/\1/p' 2> /dev/null || echo "")

        if [[ -n "$boot_time" && "$boot_time" =~ ^[0-9]+$ ]]; then
            local now=$(date +%s 2> /dev/null || echo "0")
            local uptime_sec=$((now - boot_time))
            uptime_days=$(awk "BEGIN {printf \"%.1f\", $uptime_sec / 86400}" 2> /dev/null || echo "0")
        else
            uptime_days="0"
        fi
    else
        # Linux uptime
        local uptime_file="/proc/uptime"
        if [[ -f "$uptime_file" ]]; then
            # First field is uptime in seconds, second is idle time
            local uptime_sec=$(awk '{print int($1)}' "$uptime_file" 2> /dev/null || echo "0")
            uptime_days=$(awk "BEGIN {printf \"%.1f\", $uptime_sec / 86400}" 2> /dev/null || echo "0")
        else
            # Fallback to uptime command
            local uptime_output
            uptime_output=$(uptime 2> /dev/null || echo "")
            # Extract "up X days, Y hours" format
            if echo "$uptime_output" | grep -q "day"; then
                local days=$(echo "$uptime_output" | awk '{print $3}' 2> /dev/null || echo "0")
                uptime_days=$days
            elif echo "$uptime_output" | grep -q "up"; then
                # Parse "up H:M" or "up HH:MM"
                local time_part=$(echo "$uptime_output" | sed 's/.*up \([0-9]\+:[0-9]\+\).*/\1/' 2> /dev/null || echo "0:0")
                local hours=${time_part%:*}
                local minutes=${time_part#*:}
                uptime_days=$(awk "BEGIN {printf \"%.1f\", ($hours + $minutes/60) / 24}" 2> /dev/null || echo "0")
            else
                uptime_days="0"
            fi
        fi
    fi

    [[ -z "$uptime_days" || "$uptime_days" == "" ]] && uptime_days="0"
    echo "$uptime_days"
}

# JSON escape helper
json_escape() {
    # Escape backslash, double quote, tab, and newline
    echo -n "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '
}

# Generate JSON output
generate_health_json() {
    # System info
    read -r mem_used mem_total <<< "$(get_memory_info)"
    read -r disk_used disk_total disk_percent <<< "$(get_disk_info)"
    local uptime=$(get_uptime_days)

    # Ensure all values are valid numbers (fallback to 0)
    mem_used=${mem_used:-0}
    mem_total=${mem_total:-0}
    disk_used=${disk_used:-0}
    disk_total=${disk_total:-0}
    disk_percent=${disk_percent:-0}
    uptime=${uptime:-0}

    # Start JSON
    cat << EOF
{
  "memory_used_gb": $mem_used,
  "memory_total_gb": $mem_total,
  "disk_used_gb": $disk_used,
  "disk_total_gb": $disk_total,
  "disk_used_percent": $disk_percent,
  "uptime_days": $uptime,
  "optimizations": [
EOF

    # Collect all optimization items
    local -a items=()

    # Always-on items (no size checks - instant)
    if is_macos; then
        items+=('system_maintenance|System Maintenance|Rebuild system databases & flush caches|true')
        items+=('maintenance_scripts|Maintenance Scripts|Run daily/weekly/monthly scripts & rotate logs|true')
        items+=('startup_cache|Startup Cache Rebuild|Rebuild kext caches & prelinked kernel|true')
    else
        items+=('system_maintenance|System Maintenance|Rebuild application databases & flush caches|true')
        items+=('maintenance_scripts|Maintenance Scripts|Run systemd timers & rotate logs|true')
    fi
    items+=('radio_refresh|Bluetooth & Wi-Fi Refresh|Reset wireless preference caches|true')
    items+=('recent_items|Recent Items|Clear recent apps/documents/servers lists|true')
    items+=('log_cleanup|Diagnostics Cleanup|Purge old diagnostic & crash logs|true')

    # Output items as JSON
    local first=true
    for item in "${items[@]}"; do
        IFS='|' read -r action name desc safe <<< "$item"

        # Escape strings
        action=$(json_escape "$action")
        name=$(json_escape "$name")
        desc=$(json_escape "$desc")

        [[ "$first" == "true" ]] && first=false || echo ","

        cat << EOF
    {
      "category": "system",
      "name": "$name",
      "description": "$desc",
      "action": "$action",
      "safe": $safe
    }
EOF
    done

    # Close JSON
    cat << 'EOF'
  ]
}
EOF
}

# Main execution (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_health_json
fi

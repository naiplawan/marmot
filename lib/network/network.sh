#!/bin/bash

# Network Optimization Module for Marmot
# Monitors and optimizes network performance

network_init() {
    # Ensure network directory exists
    mkdir -p "$MARMOT_NETWORK_DIR"

    # Initialize network metrics database
    if [[ ! -f "$MARMOT_NETWORK_DIR/network.db" ]]; then
        sqlite3 "$MARMOT_NETWORK_DIR/network.db" << 'EOF'
CREATE TABLE IF NOT EXISTS bandwidth_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    interface TEXT,
    bytes_sent BIGINT,
    bytes_received BIGINT,
    packets_sent BIGINT,
    packets_received BIGINT
);

CREATE TABLE IF NOT EXISTS connection_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    protocol TEXT,
    local_port INTEGER,
    remote_address TEXT,
    remote_port INTEGER,
    state TEXT,
    process_name TEXT
);

CREATE TABLE IF NOT EXISTS network_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cache_type TEXT,
    cache_size BIGINT,
    location TEXT
);

CREATE INDEX IF NOT EXISTS idx_bandwidth_timestamp ON bandwidth_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_connection_timestamp ON connection_stats(timestamp);
EOF
    fi
}

# Get network interfaces
network_get_interfaces() {
    ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v lo
}

# Monitor network bandwidth
network_monitor_bandwidth() {
    local duration=${1:-60}  # seconds
    local interval=${2:-1}   # seconds

    log "info" "Monitoring bandwidth for $duration seconds..."

    # Get initial stats
    local interfaces=($(network_get_interfaces))
    declare -A initial_rx initial_tx

    for iface in "${interfaces[@]}"; do
        initial_rx[$iface]=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        initial_tx[$iface]=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    done

    # Monitor loop
    local elapsed=0
    while [[ $elapsed -lt $duration ]]; do
        echo -ne "\rMonitoring... $elapsed/$duration seconds"
        sleep "$interval"
        ((elapsed += interval))

        # Record current stats
        for iface in "${interfaces[@]}"; do
            local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
            local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)

            sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
INSERT INTO bandwidth_usage (interface, bytes_received, bytes_sent)
VALUES ('$iface', $rx, $tx);
EOF
        done
    done
    echo ""

    success "Bandwidth monitoring completed"
}

# Show current network usage
network_show_usage() {
    echo "Network Usage Overview"
    echo "====================="

    # Real-time stats
    echo "Current Interfaces:"
    ip addr show | grep -E '^[0-9]+:' | while read line; do
        local iface=$(echo $line | awk -F': ' '{print $2}')
        local status=$(echo $line | grep -o 'UP\|DOWN')
        local ip=$(ip addr show $iface 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)

        echo "  $iface: $status"
        [[ -n $ip ]] && echo "    IP: $ip"
    done

    echo ""
    echo "Bandwidth Usage (last hour):"

    sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
.headers on
.mode table

SELECT
    interface,
    ROUND((MAX(bytes_received) - MIN(bytes_received)) / 1024/1024, 2) || ' MB' as Downloaded,
    ROUND((MAX(bytes_sent) - MIN(bytes_sent)) / 1024/1024, 2) || ' MB' as Uploaded
FROM bandwidth_usage
WHERE timestamp > datetime('now', '-1 hour')
GROUP BY interface;
EOF
}

# Analyze network connections
network_analyze_connections() {
    echo "Network Connections Analysis"
    echo "==========================="

    # Active connections
    echo "Active TCP Connections:"
    ss -tuln | head -20

    echo ""
    echo "Top Processes by Connections:"
    ss -tupn | awk 'NR>1 {print $7}' | sed 's/pid=//; s/,users://; s/"//g' | \
        cut -d: -f1 | sort | uniq -c | sort -nr | head -10

    # Store in database
    ss -tuln | while read line; do
        local protocol=$(echo $line | awk '{print $1}')
        local local_addr=$(echo $line | awk '{print $4}')
        local state=$(echo $line | awk '{print $2}')

        # Parse ports
        local local_port=$(echo $local_addr | sed 's/.*://')

        sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
INSERT OR IGNORE INTO connection_stats (protocol, local_port, state)
VALUES ('$protocol', $local_port, '$state');
EOF
    done
}

# Optimize network settings
network_optimize_settings() {
    echo "Network Optimization"
    echo "==================="

    # Check if running as root for system changes
    if [[ $EUID -ne 0 ]]; then
        echo "Some optimizations require root privileges"
        echo "Running with sudo for system-wide changes..."
    fi

    # TCP settings
    echo "Optimizing TCP settings..."

    # Enable TCP Fast Open
    sudo sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || true

    # Increase TCP buffer sizes
    sudo sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
    sudo sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
    sudo sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null || true
    sudo sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null || true

    # Enable BBR congestion control if available
    if modinfo tcp_bbr >/dev/null 2>&1; then
        sudo sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
        echo "✓ Enabled BBR congestion control"
    fi

    # DNS optimization
    echo "Optimizing DNS settings..."

    # Flush DNS cache
    if command -v systemd-resolve >/dev/null 2>&1; then
        sudo systemd-resolve --flush-caches 2>/dev/null || true
    fi

    # Network cache cleanup
    network_clean_cache

    success "Network optimization completed"
    echo "Note: Some changes may require a reboot to persist"
}

# Clean network caches
network_clean_cache() {
    log "info" "Cleaning network caches..."

    local total_freed=0

    # System DNS cache
    if command -v systemd-resolve >/dev/null 2>&1; then
        sudo systemd-resolve --flush-caches 2>/dev/null || true
    fi

    # Application caches
    local caches=(
        "$HOME/.cache/google-chrome/Default/Cache"
        "$HOME/.cache/mozilla/firefox/*/cache2"
        "$HOME/.cache/Opera/Cache"
        "$HOME/.cache/BraveSoftware/Brave-Browser/Default/Cache"
        "$HOME/.cache/discord"
        "$HOME/.cache/spotify"
    )

    for cache in "${caches[@]}"; do
        if [[ -d $cache ]]; then
            local size=$(du -sb "$cache" 2>/dev/null | cut -f1 || echo 0)
            rm -rf "$cache" 2>/dev/null || true
            ((total_freed += size))
        fi
    done

    # Download manager caches
    find "$HOME" -name ".download_cache" -type d -exec rm -rf {} \; 2>/dev/null || true
    find "$HOME" -name "tmp_downloads" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

    # Log cache cleanup
    sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
INSERT INTO network_cache (cache_type, cache_size, location)
VALUES ('application_cache', $total_freed, 'multiple');
EOF

    success "Network cache cleaned ($(format_bytes $total_freed) freed)"
}

# Monitor network latency
network_test_latency() {
    local host=${1:-8.8.8.8}
    local count=${2:-10}

    echo "Network Latency Test"
    echo "==================="

    if command -v ping >/dev/null 2>&1; then
        echo "Pinging $host ($count packets)..."
        ping -c "$count" "$host"

        echo ""
        echo "Detailed statistics:"
        ping -c "$count" "$host" | tail -2
    else
        error "ping command not available"
    fi
}

# Test download/upload speed
network_test_speed() {
    echo "Network Speed Test"
    echo "=================="

    # Check if speedtest-cli is available
    if command -v speedtest-cli >/dev/null 2>&1; then
        speedtest-cli
    elif command -v curl >/dev/null 2>&1; then
        echo "Basic speed test using curl..."

        # Download test
        echo "Testing download speed..."
        local download_time=$(curl -o /dev/null -s -w '%{time_total}' \
            http://speedtest.tele2.net/10MB.zip)
        local download_speed=$((10 * 8 / download_time / 1024))  # Mbps
        echo "Download speed: ~${download_speed} Mbps"

        # Upload test (small file)
        echo "Testing upload speed..."
        local temp_file=$(mktemp)
        dd if=/dev/urandom of="$temp_file" bs=1M count=1 2>/dev/null
        local upload_time=$(curl -o /dev/null -s -w '%{time_total}' \
            -F "file=@$temp_file" http://httpbin.org/post)
        local upload_speed=$((8 / upload_time / 1024))  # Mbps
        echo "Upload speed: ~${upload_speed} Mbps"
        rm -f "$temp_file"
    else
        error "Neither speedtest-cli nor curl available"
    fi
}

# Find network hogs
network_find_hogs() {
    echo "Network Resource Usage"
    echo "====================="

    # Using nethogs if available
    if command -v nethogs >/dev/null 2>&1; then
        echo "Real-time network usage by process:"
        sudo nethogs -t -c 5
    else
        # Fallback: use /proc/net/tcp
        echo "Processes with network connections:"
        lsof -i -n -P | grep -E 'ESTABLISHED|LISTEN' | awk '{print $1}' | sort | uniq -c | sort -nr
    fi

    # Check for large downloads
    echo ""
    echo "Large download files in progress:"
    find "$HOME" -name "*.part" -o -name "*.download" -o -name "*.tmp" 2>/dev/null | \
        while read -r file; do
            if [[ -f "$file" ]]; then
                local size=$(du -h "$file" 2>/dev/null | cut -f1)
                echo "$file ($size)"
            fi
        done
}

# Network security scan
network_security_scan() {
    echo "Network Security Check"
    echo "====================="

    # Open ports
    echo "Open ports:"
    ss -tuln | grep LISTEN

    # Check for suspicious connections
    echo ""
    echo "Suspicious outbound connections:"
    ss -tupn | grep -E 'ESTABLISHED' | awk -F' +|:' '{print $6}' | \
        grep -v -E '^(127\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.)' | \
        head -10

    # Check for DNS over HTTPS
    echo ""
    echo "DNS configuration:"
    cat /etc/resolv.conf 2>/dev/null || echo "Could not read /etc/resolv.conf"
}

# Generate network report
network_generate_report() {
    local report_file="$MARMOT_LOG_DIR/network_report_$(date +%Y%m%d).txt"

    {
        echo "Network Performance Report"
        echo "=========================="
        echo "Generated: $(date)"
        echo ""

        echo "=== Network Interfaces ==="
        ip addr show | grep -E '^[0-9]+:|inet '

        echo ""
        echo "=== Bandwidth Usage (Last 24 Hours) ==="

        sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
.headers off

SELECT 'Total Downloaded: ' || ROUND(SUM(bytes_received - LAG(bytes_received) OVER (ORDER BY timestamp)) / 1024/1024/1024, 2) || ' GB'
FROM bandwidth_usage
WHERE timestamp > datetime('now', '-1 day')
  AND bytes_received > LAG(bytes_received) OVER (ORDER BY timestamp);

SELECT 'Total Uploaded: ' || ROUND(SUM(bytes_sent - LAG(bytes_sent) OVER (ORDER BY timestamp)) / 1024/1024/1024, 2) || ' GB'
FROM bandwidth_usage
WHERE timestamp > datetime('now', '-1 day')
  AND bytes_sent > LAG(bytes_sent) OVER (ORDER BY timestamp);
EOF

        echo ""
        echo "=== Top Applications by Bandwidth ==="
        # This would need additional monitoring to track per-app usage
        echo "Application monitoring not yet implemented"

        echo ""
        echo "=== Connection Summary ==="
        sqlite3 "$MARMOT_NETWORK_DIR/network.db" << EOF
.headers on
.mode table

SELECT
    protocol,
    COUNT(*) as Connections,
    COUNT(DISTINCT local_port) as Ports
FROM connection_stats
WHERE timestamp > datetime('now', '-1 day')
GROUP BY protocol;
EOF

    } > "$report_file"

    success "Network report generated: $report_file"
}

# Network optimization suggestions
network_suggest_optimizations() {
    echo "Network Optimization Suggestions"
    echo "================================"

    # Check DNS settings
    local dns=$(grep nameserver /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
    echo "Current DNS: $dns"

    case $dns in
        127.*)
            echo "✓ Using local DNS resolver"
            ;;
        8.8.8.8|8.8.4.4)
            echo "✓ Using Google DNS"
            ;;
        1.1.1.1|1.0.0.1)
            echo "✓ Using Cloudflare DNS"
            ;;
        *)
            echo "⚠ Consider using a faster DNS provider (Google 8.8.8.8 or Cloudflare 1.1.1.1)"
            ;;
    esac

    # Check MTU
    local mtu=$(ip link show | grep -m1 -E 'mtu [0-9]+' | awk '{print $5}')
    echo "Current MTU: $mtu"
    if [[ $mtu -lt 1500 ]]; then
        echo "⚠ Low MTU detected, consider increasing to 1500 for better performance"
    fi

    # Check for QoS
    if command -v tc >/dev/null 2>&1; then
        local q=$(tc qdisc show 2>/dev/null | grep -c "fq_codel\|htb")
        if [[ $q -eq 0 ]]; then
            echo "⚠ No QoS detected, consider enabling fq_codel for better latency"
        fi
    fi

    echo ""
    echo "Recommendations:"
    echo "1. Enable BBR congestion control for better throughput"
    echo "2. Use a fast DNS resolver (1.1.1.1 or 8.8.8.8)"
    echo "3. Enable TCP Fast Open for faster connections"
    echo "4. Consider using a ad-blocker like Pi-hole for DNS"
}

# Reset network configuration
network_reset() {
    echo "Resetting Network Configuration"
    echo "=============================="

    read -p "This will reset network settings to defaults. Continue? (y/N): " confirm

    if [[ $confirm != [yY] ]]; then
        echo "Cancelled"
        return
    fi

    # Reset TCP settings to defaults
    sudo sysctl -w net.ipv4.tcp_fastopen=1 2>/dev/null || true
    sudo sysctl -w net.core.rmem_max=212992 2>/dev/null || true
    sudo sysctl -w net.core.wmem_max=212992 2>/dev/null || true

    # Flush DNS
    sudo systemd-resolve --flush-caches 2>/dev/null || true

    # Restart network service
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl restart NetworkManager 2>/dev/null || \
        sudo systemctl restart networking 2>/dev/null || \
        echo "Could not restart network service (please do it manually)"
    fi

    success "Network configuration reset to defaults"
}

# Interactive network menu
network_menu() {
    while true; do
        echo
        echo "Network Optimization Tools"
        echo "========================="
        echo "1) Show network usage"
        echo "2) Monitor bandwidth"
        echo "3) Analyze connections"
        echo "4) Optimize settings"
        echo "5) Clean network cache"
        echo "6) Test latency"
        echo "7) Test speed"
        echo "8) Find network hogs"
        echo "9) Security scan"
        echo "10) Generate report"
        echo "11) Optimization suggestions"
        echo "12) Reset configuration"
        echo "13) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                network_show_usage
                ;;
            2)
                read -p "Duration in seconds [60]: " duration
                network_monitor_bandwidth "${duration:-60}"
                ;;
            3)
                network_analyze_connections
                ;;
            4)
                network_optimize_settings
                ;;
            5)
                network_clean_cache
                ;;
            6)
                read -p "Host to ping [8.8.8.8]: " host
                network_test_latency "${host:-8.8.8.8}"
                ;;
            7)
                network_test_speed
                ;;
            8)
                network_find_hogs
                ;;
            9)
                network_security_scan
                ;;
            10)
                network_generate_report
                ;;
            11)
                network_suggest_optimizations
                ;;
            12)
                network_reset
                ;;
            13)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}
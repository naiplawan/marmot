#!/bin/bash

# App Usage Analytics Module for Marmot
# Tracks and analyzes application usage patterns

appusage_init() {
    # Ensure appusage directory exists
    mkdir -p "$MARMOT_APPUSAGE_DIR"

    # Initialize app usage database
    if [[ ! -f "$MARMOT_APPUSAGE_DIR/appusage.db" ]]; then
        sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << 'EOF'
CREATE TABLE IF NOT EXISTS app_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_name TEXT,
    app_path TEXT,
    cpu_time BIGINT,
    memory_usage BIGINT,
    disk_reads BIGINT,
    disk_writes BIGINT,
    network_usage BIGINT,
    duration INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_name TEXT,
    cache_type TEXT,
    cache_size BIGINT,
    cache_location TEXT,
    last_accessed DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS startup_apps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_name TEXT,
    app_path TEXT,
    enabled BOOLEAN,
    delay INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_name TEXT,
    dependency_name TEXT,
    dependency_type TEXT,
    required BOOLEAN
);

CREATE INDEX IF NOT EXISTS idx_app_usage_name ON app_usage(app_name);
CREATE INDEX IF NOT EXISTS idx_app_usage_timestamp ON app_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_cache_app ON app_cache(app_name);
EOF
    fi
}

# Monitor application usage in real-time
appusage_monitor() {
    local duration=${1:-300}  # 5 minutes default
    local interval=${2:-10}   # 10 seconds default

    log "info" "Monitoring application usage for $duration seconds..."

    local end_time=$((SECONDS + duration))

    while [[ $SECONDS -lt $end_time ]]; do
        # Get running processes
        ps aux --no-headers | while read -r line; do
            local user=$(echo $line | awk '{print $1}')
            local pid=$(echo $line | awk '{print $2}')
            local cpu=$(echo $line | awk '{print $3}')
            local mem=$(echo $line | awk '{print $4}')
            local command=$(echo $line | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')

            # Skip system processes for non-root users
            if [[ $user != "root" && $user != "$USER" ]]; then
                continue
            fi

            # Extract app name from command
            local app_name=$(basename $(echo $command | awk '{print $1}'))

            # Get detailed process info
            local cpu_time=0
            local mem_usage=0
            local io_read=0
            local io_write=0

            if [[ -d /proc/$pid ]]; then
                # CPU time
                local utime=$(cat /proc/$pid/stat 2>/dev/null | awk '{print $14}')
                local stime=$(cat /proc/$pid/stat 2>/dev/null | awk '{print $15}')
                cpu_time=$((utime + stime))

                # Memory in bytes
                mem_usage=$(cat /proc/$pid/status 2>/dev/null | grep VmRSS | awk '{print $2 * 1024}')

                # I/O statistics
                if [[ -f /proc/$pid/io ]]; then
                    io_read=$(cat /proc/$pid/io 2>/dev/null | grep read_bytes | awk '{print $2}')
                    io_write=$(cat /proc/$pid/io 2>/dev/null | grep write_bytes | awk '{print $2}')
                fi
            fi

            # Store in database
            sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
INSERT INTO app_usage
(app_name, app_path, cpu_time, memory_usage, disk_reads, disk_writes, duration)
VALUES ('$app_name', '$command', $cpu_time, $mem_usage, $io_read, $io_write, $interval);
EOF
        done

        printf "\rMonitoring... $((duration - (end_time - SECONDS)))/$duration seconds"
        sleep "$interval"
    done
    echo ""

    success "Application usage monitoring completed"
}

# Analyze app usage patterns
appusage_analyze() {
    local days=${1:-7}

    echo "Application Usage Analysis (Last $days days)"
    echo "=========================================="

    # Top apps by CPU usage
    echo ""
    echo "Top 10 Apps by CPU Time:"
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
.headers on
.mode table

SELECT
    app_name,
    ROUND(SUM(cpu_time) / 60, 2) || ' min' as Total_CPU_Time,
    COUNT(*) as Samples,
    ROUND(AVG(cpu_time) / 60, 2) || ' min' as Avg_CPU_Time
FROM app_usage
WHERE timestamp > datetime('now', '-$days days')
GROUP BY app_name
ORDER BY SUM(cpu_time) DESC
LIMIT 10;
EOF

    # Top apps by memory usage
    echo ""
    echo "Top 10 Apps by Memory Usage:"
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
.headers on
.mode table

SELECT
    app_name,
    ROUND(MAX(memory_usage) / 1024/1024, 2) || ' MB' as Peak_Memory,
    ROUND(AVG(memory_usage) / 1024/1024, 2) || ' MB' as Avg_Memory,
    COUNT(*) as Samples
FROM app_usage
WHERE timestamp > datetime('now', '-$days days')
  AND memory_usage > 0
GROUP BY app_name
ORDER BY MAX(memory_usage) DESC
LIMIT 10;
EOF

    # Top apps by I/O
    echo ""
    echo "Top 10 Apps by Disk I/O:"
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
.headers on
.mode table

SELECT
    app_name,
    ROUND(SUM(disk_reads) / 1024/1024, 2) || ' MB' as Total_Read,
    ROUND(SUM(disk_writes) / 1024/1024, 2) || ' MB' as Total_Write
FROM app_usage
WHERE timestamp > datetime('now', '-$days days')
GROUP BY app_name
ORDER BY (SUM(disk_reads) + SUM(disk_writes)) DESC
LIMIT 10;
EOF
}

# Find rarely used applications
appusage_find_rarely_used() {
    local days=${1:-30}

    echo "Rarely Used Applications (Last $days days)"
    echo "========================================"

    # Get installed packages
    if command -v dpkg >/dev/null 2>&1; then
        # Debian/Ubuntu
        dpkg-query -W -f='${Package}\t${Installed-Size}\n' 2>/dev/null | \
        while read -r package size; do
            # Check if in usage database
            local usage=$(sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" \
                "SELECT COUNT(*) FROM app_usage WHERE app_name LIKE '%$package%' \
                 AND timestamp > datetime('now', '-$days days');")

            if [[ $usage -eq 0 && -n $size && $size -gt 1000 ]]; then
                echo "$package (${size} KB) - Not used in $days days"
            fi
        done
    elif command -v rpm >/dev/null 2>&1; then
        # RedHat/CentOS/Fedora
        rpm -qa --queryformat='%{NAME}\t%{SIZE}\n' 2>/dev/null | \
        while read -r package size; do
            local usage=$(sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" \
                "SELECT COUNT(*) FROM app_usage WHERE app_name LIKE '%$package%' \
                 AND timestamp > datetime('now', '-$days days');")

            if [[ $usage -eq 0 && $((size / 1024)) -gt 1000 ]]; then
                echo "$package ($((size / 1024)) KB) - Not used in $days days"
            fi
        done
    fi
}

# Analyze application cache sizes
appusage_analyze_cache() {
    echo "Application Cache Analysis"
    echo "========================="

    # Scan for app caches
    local cache_locations=(
        "$HOME/.cache"
        "$HOME/.local/share"
        "/var/cache"
        "/tmp"
    )

    for location in "${cache_locations[@]}"; do
        if [[ -d "$location" ]]; then
            find "$location" -maxdepth 2 -type d 2>/dev/null | \
            while read -r cache_dir; do
                if [[ -d "$cache_dir" ]]; then
                    local size=$(du -sb "$cache_dir" 2>/dev/null | cut -f1 || echo 0)
                    local app_name=$(basename "$cache_dir")
                    local last_access=$(stat -c %X "$cache_dir" 2>/dev/null || echo 0)

                    # Store in database
                    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
INSERT OR REPLACE INTO app_cache
(app_name, cache_type, cache_size, cache_location, last_accessed)
VALUES ('$app_name', 'cache', $size, '$cache_dir', datetime($last_access, 'unixepoch'));
EOF
                fi
            done
        fi
    done

    # Show cache statistics
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
.headers on
.mode table

SELECT
    app_name,
    ROUND(cache_size / 1024/1024, 2) || ' MB' as Size,
    datetime(last_accessed) as 'Last Accessed',
    cache_location as Location
FROM app_cache
WHERE cache_size > 1048576  -- > 1MB
ORDER BY cache_size DESC
LIMIT 20;
EOF
}

# Manage startup applications
appusage_manage_startup() {
    echo "Startup Application Manager"
    echo "==========================="

    # Detect desktop environment
    local desktop_env=${XDG_CURRENT_DESKTOP:-unknown}

    case $desktop_env in
        *GNOME*|*ubuntu*)
            appusage_manage_gnome_startup
            ;;
        *KDE*)
            appusage_manage_kde_startup
            ;;
        *XFCE*)
            appusage_manage_xfce_startup
            ;;
        *)
            echo "Generic startup management"
            appusage_manage_generic_startup
            ;;
    esac
}

# Manage GNOME startup apps
appusage_manage_gnome_startup() {
    # List current startup apps
    echo "Current GNOME startup applications:"
    gnome-extensions list --enabled 2>/dev/null | grep -E "startup|autostart" || echo "No startup extensions found"

    echo ""
    echo "Autostart applications:"
    ls -la "$HOME/.config/autostart/"/*.desktop 2>/dev/null | \
    while read -r file; do
        local name=$(grep '^Name=' "$file" 2>/dev/null | cut -d= -f2)
        local enabled=$(grep '^Hidden=' "$file" 2>/dev/null | cut -d= -f2)
        echo "$name - $([ "$enabled" = "true" ] && echo "Disabled" || echo "Enabled")"
    done
}

# Manage KDE startup apps
appusage_manage_kde_startup() {
    echo "Current KDE startup applications:"
    ls -la "$HOME/.config/autostart/" 2>/dev/null || echo "No autostart directory found"
}

# Manage XFCE startup apps
appusage_manage_xfce_startup() {
    echo "Current XFCE startup applications:"
    xfce4-autostart-editor --list 2>/dev/null || echo "XFCE autostart editor not available"
}

# Generic startup management
appusage_manage_generic_startup() {
    echo "Generic autostart locations:"
    echo "User: $HOME/.config/autostart/"
    echo "System: /etc/xdg/autostart/"
    echo "Init scripts: /etc/init.d/, /etc/systemd/system/"

    echo ""
    echo "System services (user):"
    systemctl --user list-unit-files --type=service --state=enabled 2>/dev/null | head -10
}

# Profile application performance
appusage_profile_app() {
    local app_name=$1
    local duration=${2:-60}

    if [[ -z $app_name ]]; then
        echo "Usage: appusage_profile_app <app_name> [duration_seconds]"
        return 1
    fi

    log "info" "Profiling $app_name for $duration seconds..."

    # Start monitoring in background
    (
        local start_time=$(date +%s)
        local end_time=$((start_time + duration))

        while [[ $(date +%s) -lt $end_time ]]; do
            local pid=$(pgrep -f "$app_name" | head -1)
            if [[ -n $pid && -d /proc/$pid ]]; then
                local cpu=$(cat /proc/$pid/stat 2>/dev/null | awk '{print $14 + $15}')
                local mem=$(cat /proc/$pid/status 2>/dev/null | grep VmRSS | awk '{print $2 * 1024}')
                local io_read=$(cat /proc/$pid/io 2>/dev/null | grep read_bytes | awk '{print $2}')
                local io_write=$(cat /proc/$pid/io 2>/dev/null | grep write_bytes | awk '{print $2}')

                echo "$(date +%s),$cpu,$mem,$io_read,$io_write" >> "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv"
            fi
            sleep 1
        done
    ) &

    local monitor_pid=$!

    # Launch the app
    if ! pgrep -f "$app_name" >/dev/null; then
        echo "Starting $app_name..."
        "$app_name" &
        local app_pid=$!
    fi

    # Wait for monitoring to complete
    wait $monitor_pid

    # Generate report
    echo "Performance profile for $app_name:"
    echo "=================================="

    if [[ -f "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv" ]]; then
        echo "CPU Usage:"
        awk -F, 'NR>1 {cpu+=$2; count++} END {print "Average:", cpu/count/100, "seconds"}' \
            "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv"

        echo "Memory Usage:"
        awk -F, 'NR>1 {mem+=$3; if(mem>$4) peak=$4} END {print "Average:", mem/count/1024/1024, "MB"; print "Peak:", peak/1024/1024, "MB"}' \
            "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv"

        echo "I/O Usage:"
        awk -F, 'NR>1 {read+=$4; write+=$5} END {print "Read:", read/1024/1024, "MB"; print "Write:", write/1024/1024, "MB"}' \
            "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv"

        # Clean up
        rm -f "$MARMOT_APPUSAGE_DIR/profile_$app_name.csv"
    else
        echo "No performance data collected"
    fi
}

# Visualize app usage
appusage_visualize() {
    local output_file="$MARMOT_APPUSAGE_DIR/app_usage_$(date +%Y%m%d).html"

    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Marmot App Usage Analytics</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { max-width: 800px; margin: 20px auto; }
        canvas { max-height: 400px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .stat-card { background: #f0f0f0; padding: 20px; border-radius: 8px; text-align: center; }
    </style>
</head>
<body>
    <h1>Application Usage Analytics</h1>

    <div class="stats">
        <div class="stat-card">
            <h3>Total Apps Monitored</h3>
            <p id="total-apps">Loading...</p>
        </div>
        <div class="stat-card">
            <h3>Avg CPU Usage</h3>
            <p id="avg-cpu">Loading...</p>
        </div>
        <div class="stat-card">
            <h3>Total Memory Used</h3>
            <p id="total-mem">Loading...</p>
        </div>
    </div>

    <div class="chart-container">
        <h2>Top Applications by CPU Time</h2>
        <canvas id="cpuChart"></canvas>
    </div>

    <div class="chart-container">
        <h2>Top Applications by Memory Usage</h2>
        <canvas id="memChart"></canvas>
    </div>

    <div class="chart-container">
        <h2>Application Usage Timeline</h2>
        <canvas id="timelineChart"></canvas>
    </div>
EOF

    # Add data from database
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" >> "$output_file" << 'EOF'
<script>
// Get data from database would require server-side processing
// For now, using sample data structure

const topCpuApps = [
$(sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" \
    "SELECT app_name, SUM(cpu_time) FROM app_usage GROUP BY app_name ORDER BY SUM(cpu_time) DESC LIMIT 10" | \
    sed 's/|/,/g' | awk '{print "{x: \"'"$1"'\", y: '"$2"' },"}')
];

const topMemApps = [
$(sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" \
    "SELECT app_name, AVG(memory_usage) FROM app_usage WHERE memory_usage > 0 GROUP BY app_name ORDER BY AVG(memory_usage) DESC LIMIT 10" | \
    sed 's/|/,/g' | awk '{print "{x: \"'"$1"'\", y: '"$2"' },"}')
];

// Create CPU chart
new Chart(document.getElementById('cpuChart'), {
    type: 'bar',
    data: {
        datasets: [{
            label: 'CPU Time (seconds)',
            data: topCpuApps,
            backgroundColor: 'rgba(255, 99, 132, 0.5)'
        }]
    },
    options: {
        responsive: true,
        scales: {
            y: { beginAtZero: true }
        }
    }
});

// Create Memory chart
new Chart(document.getElementById('memChart'), {
    type: 'bar',
    data: {
        datasets: [{
            label: 'Memory Usage (bytes)',
            data: topMemApps,
            backgroundColor: 'rgba(54, 162, 235, 0.5)'
        }]
    },
    options: {
        responsive: true,
        scales: {
            y: { beginAtZero: true }
        }
    }
});
</script>
EOF

    cat >> "$output_file" << 'EOF'
</body>
</html>
EOF

    success "App usage visualization created: $output_file"

    # Open in browser if available
    if command -v xdg-open >/dev/null 2>&1 && ask "Open visualization in browser?"; then
        xdg-open "$output_file"
    fi
}

# Generate app usage recommendations
appusage_recommendations() {
    echo "Application Usage Recommendations"
    echo "================================="

    # Find resource hogs
    echo "Resource Heavy Applications:"
    sqlite3 "$MARMOT_APPUSAGE_DIR/appusage.db" << EOF
.headers on
.mode table

SELECT
    app_name,
    ROUND(AVG(memory_usage) / 1024/1024, 2) || ' MB' as Avg_Memory,
    ROUND(SUM(cpu_time) / 60, 2) || ' min' as Total_CPU
FROM app_usage
WHERE timestamp > datetime('now', '-7 days')
GROUP BY app_name
HAVING AVG(memory_usage) > 100*1024*1024 OR SUM(cpu_time) > 300
ORDER BY (AVG(memory_usage) + SUM(cpu_time)*1024) DESC
LIMIT 5;
EOF

    echo ""
    echo "Optimization Suggestions:"
    echo "1. Consider closing unused applications that consume high memory"
    echo "2. Review startup applications and disable non-essential ones"
    echo "3. Clear application caches regularly"
    echo "4. Consider alternative lightweight applications for frequently used heavy apps"
}

# Interactive menu
appusage_menu() {
    while true; do
        echo
        echo "App Usage Analytics"
        echo "==================="
        echo "1) Monitor current usage"
        echo "2) Analyze usage patterns"
        echo "3) Find rarely used apps"
        echo "4) Analyze cache usage"
        echo "5) Manage startup apps"
        echo "6) Profile specific app"
        echo "7) Generate visualization"
        echo "8) Get recommendations"
        echo "9) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                read -p "Monitor duration in seconds [300]: " duration
                appusage_monitor "${duration:-300}"
                ;;
            2)
                read -p "Analysis period in days [7]: " days
                appusage_analyze "${days:-7}"
                ;;
            3)
                read -p "Look back period in days [30]: " days
                appusage_find_rarely_used "${days:-30}"
                ;;
            4)
                appusage_analyze_cache
                ;;
            5)
                appusage_manage_startup
                ;;
            6)
                read -p "Enter application name: " app
                read -p "Profile duration in seconds [60]: " duration
                appusage_profile_app "$app" "${duration:-60}"
                ;;
            7)
                appusage_visualize
                ;;
            8)
                appusage_recommendations
                ;;
            9)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}
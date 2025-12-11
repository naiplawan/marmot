#!/bin/bash

# Analytics module for Marmot
# Tracks storage usage trends and generates reports

analytics_init() {
    # Ensure analytics directory exists
    mkdir -p "$MARMOT_ANALYTICS_DIR"

    # Initialize analytics database
    if [[ ! -f "$MARMOT_ANALYTICS_DIR/storage.db" ]]; then
        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << 'EOF'
CREATE TABLE IF NOT EXISTS storage_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_space BIGINT,
    used_space BIGINT,
    free_space BIGINT,
    filesystem TEXT,
    mount_point TEXT
);

CREATE TABLE IF NOT EXISTS cleanup_operations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    operation_type TEXT,
    space_freed BIGINT,
    files_removed INTEGER,
    duration_ms INTEGER,
    details TEXT
);

CREATE TABLE IF NOT EXISTS application_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    app_name TEXT,
    cache_size BIGINT,
    last_accessed DATETIME
);

CREATE TABLE IF NOT EXISTS large_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    file_path TEXT,
    file_size BIGINT,
    file_type TEXT,
    last_modified DATETIME
);
EOF
    fi
}

# Take a storage snapshot
analytics_snapshot() {
    local filesystem=${1:-"/"}

    # Get current storage stats
    local stats=$(df -B1 "$filesystem" | tail -n1)
    local total=$(echo $stats | awk '{print $2}')
    local used=$(echo $stats | awk '{print $3}')
    local free=$(echo $stats | awk '{print $4}')
    local fs_name=$(echo $stats | awk '{print $1}')
    local mount_point=$(echo $stats | awk '{print $6}')

    # Store in database
    sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
INSERT INTO storage_snapshots
(total_space, used_space, free_space, filesystem, mount_point)
VALUES ($total, $used, $free, '$fs_name', '$mount_point');
EOF

    log "info" "Storage snapshot taken for $mount_point"
}

# Record cleanup operation
analytics_record_cleanup() {
    local operation_type=$1
    local space_freed=${2:-0}
    local files_removed=${3:-0}
    local duration_ms=${4:-0}
    local details=${5:-""}

    sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
INSERT INTO cleanup_operations
(operation_type, space_freed, files_removed, duration_ms, details)
VALUES ('$operation_type', $space_freed, $files_removed, $duration_ms, '$details');
EOF
}

# Generate storage trend report
analytics_storage_report() {
    local days=${1:-30}
    local output_file="$MARMOT_ANALYTICS_DIR/storage_report_$(date +%Y%m%d).txt"

    {
        echo "Storage Usage Trend Report"
        echo "=========================="
        echo "Period: Last $days days"
        echo "Generated: $(date)"
        echo ""

        # Get trend data
        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
.headers on
.mode table

SELECT
    DATE(timestamp) as Date,
    ROUND(AVG(used_space) / 1024/1024/1024, 2) || ' GB' as Avg_Used,
    ROUND(MIN(used_space) / 1024/1024/1024, 2) || ' GB' as Min_Used,
    ROUND(MAX(used_space) / 1024/1024/1024, 2) || ' GB' as Max_Used
FROM storage_snapshots
WHERE timestamp > datetime('now', '-$days days')
GROUP BY DATE(timestamp)
ORDER BY Date DESC
LIMIT 10;
EOF

        echo ""
        echo "Storage Growth Rate:"
        echo "-------------------"

        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
SELECT
    'Daily Growth' as Metric,
    ROUND(AVG(daily_diff) / 1024/1024/1024, 2) || ' GB/day' as Rate
FROM (
    SELECT
        used_space - LAG(used_space, 1) OVER (ORDER BY timestamp) as daily_diff
    FROM storage_snapshots
    WHERE timestamp > datetime('now', '-$days days')
)
WHERE daily_diff IS NOT NULL;
EOF

    } > "$output_file"

    success "Storage report generated: $output_file"
}

# Generate cleanup effectiveness report
analytics_cleanup_report() {
    local days=${1:-30}
    local output_file="$MARMOT_ANALYTICS_DIR/cleanup_report_$(date +%Y%m%d).txt"

    {
        echo "Cleanup Effectiveness Report"
        echo "============================"
        echo "Period: Last $days days"
        echo "Generated: $(date)"
        echo ""

        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
.headers on
.mode table

SELECT
    operation_type,
    COUNT(*) as Operations,
    ROUND(SUM(space_freed) / 1024/1024/1024, 2) || ' GB' as Space_Freed,
    SUM(files_removed) as Files_Removed,
    ROUND(AVG(duration_ms) / 1000, 2) || ' s' as Avg_Duration
FROM cleanup_operations
WHERE timestamp > datetime('now', '-$days days')
GROUP BY operation_type
ORDER BY Space_Freed DESC;
EOF

        echo ""
        echo "Most Effective Cleaners:"
        echo "------------------------"

        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
.headers on
.mode table

SELECT
    details as Cleaner,
    ROUND(AVG(space_freed) / 1024/1024, 2) || ' MB' as Avg_Saved,
    COUNT(*) as Times_Run
FROM cleanup_operations
WHERE operation_type = 'app_cache'
  AND timestamp > datetime('now', '-$days days')
  AND details != ''
GROUP BY details
HAVING COUNT(*) > 1
ORDER BY Avg_Saved DESC
LIMIT 10;
EOF

    } > "$output_file"

    success "Cleanup report generated: $output_file"
}

# Predict storage issues
analytics_predict_issues() {
    local warning_threshold=${1:-90}  # Percentage
    local days_ahead=${2:-7}

    # Get latest snapshot
    local latest=$(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
        "SELECT total_space, used_space FROM storage_snapshots
         ORDER BY timestamp DESC LIMIT 1;")

    if [[ -z $latest ]]; then
        warn "No storage data available for prediction"
        return 1
    fi

    local total=$(echo $latest | cut -d'|' -f1)
    local used=$(echo $latest | cut -d'|' -f2)
    local usage_percent=$((used * 100 / total))

    echo "Storage Prediction Analysis"
    echo "==========================="
    echo "Current Usage: $usage_percent% ($(format_bytes $used) / $(format_bytes $total))"
    echo ""

    if [[ $usage_percent -gt $warning_threshold ]]; then
        echo "⚠️  WARNING: Storage usage is above ${warning_threshold}%!"
        echo ""
    fi

    # Calculate average daily growth
    local growth=$(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
SELECT AVG(daily_diff)
FROM (
    SELECT
        used_space - LAG(used_space, 1) OVER (ORDER BY timestamp) as daily_diff
    FROM storage_snapshots
    WHERE timestamp > datetime('now', '-30 days')
)
WHERE daily_diff > 0;
EOF
)

    if [[ -n $growth && $growth != "" ]]; then
        # Predict when storage will be full
        local remaining=$((total - used))
        local days_until_full=$((remaining / growth))

        echo "Average daily growth: $(format_bytes $growth)/day"
        echo "Predicted full in: $days_until_full days"

        if [[ $days_until_full -lt $days_ahead ]]; then
            echo ""
            echo "🚨 ALERT: Storage may be full within $days_ahead days!"
        fi
    fi
}

# Track large files
analytics_track_large_files() {
    local min_size=${1:-100M}  # Default 100MB
    local path=${2:-/}

    log "info" "Scanning for large files (>=$min_size) in $path..."

    # Find large files and store in database
    find "$path" -type f -size +"$min_size" -exec stat -c "%n %s %y" {} \; 2>/dev/null | \
    while read -r file size modified; do
        local file_type="${file##*.}"
        sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
INSERT OR REPLACE INTO large_files
(file_path, file_size, file_type, last_modified)
VALUES ('$file', $size, '$file_type', '$modified');
EOF
    done

    success "Large files tracking completed"
}

# Show top space consumers
analytics_show_top_consumers() {
    local limit=${1:-20}

    echo "Top Space Consumers"
    echo "==================="
    echo ""

    sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
.headers on
.mode table

SELECT
    file_path,
    ROUND(file_size / 1024/1024/1024, 2) || ' GB' as Size,
    file_type,
    DATE(last_modified) as Modified
FROM large_files
ORDER BY file_size DESC
LIMIT $limit;
EOF
}

# Generate visual storage map
analytics_storage_map() {
    local path=${1:-/}
    local output_file="$MARMOT_ANALYTICS_DIR/storage_map_$(date +%Y%m%d).html"

    # Create HTML storage map
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Marmot Storage Map</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { max-width: 800px; margin: 20px auto; }
        .stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .stat-card { background: #f0f0f0; padding: 20px; border-radius: 8px; text-align: center; }
        canvas { max-height: 400px; }
    </style>
</head>
<body>
    <h1>Marmot Storage Analytics</h1>

    <div class="stats">
        <div class="stat-card">
            <h3>Total Storage</h3>
            <p id="total-storage">Loading...</p>
        </div>
        <div class="stat-card">
            <h3>Used Space</h3>
            <p id="used-storage">Loading...</p>
        </div>
        <div class="stat-card">
            <h3>Free Space</h3>
            <p id="free-storage">Loading...</p>
        </div>
    </div>

    <div class="chart-container">
        <h2>Storage Usage Trend</h2>
        <canvas id="trendChart"></canvas>
    </div>

    <div class="chart-container">
        <h2>Cleanup Operations Impact</h2>
        <canvas id="cleanupChart"></canvas>
    </div>
EOF

    # Add JavaScript with real data
    sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" >> "$output_file" << EOF
<script>
// Storage data
const latestSnapshot = $(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
    "SELECT total_space, used_space, free_space FROM storage_snapshots
     ORDER BY timestamp DESC LIMIT 1;" | \
    tr '|' ',');

const trendData = $(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
    "SELECT DATE(timestamp), used_space FROM storage_snapshots
     WHERE timestamp > datetime('now', '-30 days')
     ORDER BY timestamp;" | \
    sed 's/|/,/g' | \
    awk '{print "{x: \""$1"\", y: "$2"},"}')

const cleanupData = $(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
    "SELECT DATE(timestamp), operation_type, space_freed FROM cleanup_operations
     WHERE timestamp > datetime('now', '-30 days');" | \
    sed 's/|/,/g')

// Update stats
document.getElementById('total-storage').textContent = formatBytes(latestSnapshot[0]);
document.getElementById('used-storage').textContent = formatBytes(latestSnapshot[1]);
document.getElementById('free-storage').textContent = formatBytes(latestSnapshot[2]);

// Create trend chart
new Chart(document.getElementById('trendChart'), {
    type: 'line',
    data: {
        datasets: [{
            label: 'Used Space',
            data: [${trendData}],
            borderColor: 'rgb(75, 192, 192)',
            tension: 0.1
        }]
    },
    options: {
        responsive: true,
        scales: {
            x: {
                type: 'time',
                time: {
                    unit: 'day'
                }
            },
            y: {
                ticks: {
                    callback: function(value) {
                        return formatBytes(value);
                    }
                }
            }
        }
    }
});

function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}
</script>
EOF

    cat >> "$output_file" << 'EOF'
</body>
</html>
EOF

    success "Storage map generated: $output_file"

    # Offer to open in browser
    if command -v xdg-open >/dev/null 2>&1; then
        if ask "Open storage map in browser?"; then
            xdg-open "$output_file"
        fi
    fi
}

# Export analytics data
analytics_export() {
    local format=${1:-json}
    local output_file="$MARMOT_ANALYTICS_DIR/export_$(date +%Y%m%d).$format"

    case $format in
        json)
            sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
                -header -json \
                "SELECT * FROM storage_snapshots WHERE timestamp > datetime('now', '-90 days')" \
                > "$output_file"
            ;;
        csv)
            sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
                -header -csv \
                "SELECT * FROM storage_snapshots WHERE timestamp > datetime('now', '-90 days')" \
                > "$output_file"
            ;;
        sql)
            sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
                ".dump storage_snapshots cleanup_operations" \
                > "$output_file"
            ;;
    esac

    success "Analytics exported to: $output_file"
}

# Cleanup old analytics data
analytics_cleanup() {
    local days_to_keep=${1:-365}

    sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" << EOF
DELETE FROM storage_snapshots
WHERE timestamp < datetime('now', '-$days_to_keep days');

DELETE FROM cleanup_operations
WHERE timestamp < datetime('now', '-$days_to_keep days');

DELETE FROM large_files
WHERE timestamp < datetime('now', '-$days_to_keep days');
EOF

    success "Cleaned analytics data older than $days_to_keep days"
}

# Run comprehensive analytics collection
analytics_collect() {
    log "info" "Starting comprehensive analytics collection..."

    # Take current snapshot
    analytics_snapshot

    # Track large files
    analytics_track_large_files

    # Update application usage (would need integration with package managers)
    # analytics_update_app_usage

    success "Analytics collection completed"
}
#!/bin/bash

# Schedule module for Marmot
# Handles automated maintenance scheduling

schedule_init() {
    # Ensure schedule directory exists
    mkdir -p "$MARMOT_SCHEDULE_DIR"

    # Initialize schedule config
    if [[ ! -f "$MARMOT_CONFIG_DIR/schedule.conf" ]]; then
        cat > "$MARMOT_CONFIG_DIR/schedule.conf" << EOF
# Marmot Schedule Configuration
# Format: "action|frequency|time|enabled"
# Actions: clean, optimize, analyze
# Frequency: daily, weekly, monthly
# Time: HH:MM (24-hour format)
# Enabled: true/false

# Example schedules
clean|daily|02:00|true
optimize|weekly|03:00|true
analyze|monthly|04:00|false
EOF
    fi
}

# Install cron job for scheduled maintenance
schedule_install() {
    log "info" "Installing scheduled maintenance..."

    # Create the cron script
    local cron_script="/usr/local/bin/marmot-schedule"
    sudo tee "$cron_script" > /dev/null << 'EOF'
#!/bin/bash
# Marmot Scheduled Maintenance Runner
# This script runs scheduled maintenance tasks

# Source marmot configuration
if [[ -f "/usr/local/etc/marmot/config" ]]; then
    source "/usr/local/etc/marmot/config"
elif [[ -f "$HOME/.config/marmot/config" ]]; then
    source "$HOME/.config/marmot/config"
else
    echo "Error: Marmot configuration not found"
    exit 1
fi

# Source core functions
source "$MARMOT_LIB_DIR/core/logging.sh"
source "$MARMOT_LIB_DIR/core/sudo.sh"
source "$MARMOT_LIB_DIR/schedule/schedule.sh"

# Initialize schedule
schedule_init

# Read configuration and execute scheduled tasks
while IFS='|' read -r action frequency time enabled; do
    # Skip comments and empty lines
    [[ $action =~ ^#.*$ ]] && continue
    [[ -z $action ]] && continue

    # Check if task is enabled
    [[ $enabled != "true" ]] && continue

    # Get current time in minutes since midnight
    current_hour=$(date +%H)
    current_minute=$(date +%M)
    current_total=$((current_hour * 60 + current_minute))

    # Parse scheduled time
    scheduled_hour=$(echo $time | cut -d: -f1)
    scheduled_minute=$(echo $time | cut -d: -f2)
    scheduled_total=$((scheduled_hour * 60 + scheduled_minute))

    # Check if it's time to run (within a 5-minute window)
    time_diff=$((current_total - scheduled_total))
    if [[ $time_diff -ge 0 && $time_diff -le 5 ]]; then
        # Check frequency
        case $frequency in
            daily)
                log "info" "Running scheduled $action (daily)"
                execute_scheduled_task "$action"
                ;;
            weekly)
                if [[ $(date +%u) -eq 1 ]]; then  # Monday
                    log "info" "Running scheduled $action (weekly)"
                    execute_scheduled_task "$action"
                fi
                ;;
            monthly)
                if [[ $(date +%d) -eq 1 ]]; then  # 1st of month
                    log "info" "Running scheduled $action (monthly)"
                    execute_scheduled_task "$action"
                fi
                ;;
        esac
    fi
done < "$MARMOT_CONFIG_DIR/schedule.conf"
EOF

    sudo chmod +x "$cron_script"

    # Install cron job (runs every 5 minutes)
    local cron_entry="*/5 * * * * $cron_script"
    (crontab -l 2>/dev/null | grep -v "marmot-schedule"; echo "$cron_entry") | crontab -

    # Create log rotation for schedule logs
    sudo tee /etc/logrotate.d/marmot-schedule > /dev/null << EOF
$MARMOT_LOG_DIR/schedule.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF

    success "Scheduled maintenance installed"
    log "info" "Cron job will run every 5 minutes to check for scheduled tasks"
}

# Execute scheduled task
execute_scheduled_task() {
    local action=$1
    local log_file="$MARMOT_LOG_DIR/schedule.log"

    echo "===== $(date) - Running $action =====" >> "$log_file"

    case $action in
        clean)
            "$MARMOT_BIN_DIR/marmot" clean --auto >> "$log_file" 2>&1
            ;;
        optimize)
            "$MARMOT_BIN_DIR/marmot" optimize --auto >> "$log_file" 2>&1
            ;;
        analyze)
            "$MARMOT_BIN_DIR/marmot" analyze --auto >> "$log_file" 2>&1
            ;;
    esac

    echo "===== Completed $action at $(date) =====" >> "$log_file"
    echo "" >> "$log_file"
}

# Remove scheduled maintenance
schedule_remove() {
    log "info" "Removing scheduled maintenance..."

    # Remove cron entry
    crontab -l 2>/dev/null | grep -v "marmot-schedule" | crontab -

    # Remove cron script
    sudo rm -f "/usr/local/bin/marmot-schedule"

    # Remove log rotation
    sudo rm -f "/etc/logrotate.d/marmot-schedule"

    success "Scheduled maintenance removed"
}

# Show current schedule
schedule_status() {
    echo "Current Schedule Configuration:"
    echo "=============================="

    if [[ -f "$MARMOT_CONFIG_DIR/schedule.conf" ]]; then
        echo -e "Action\t\tFrequency\tTime\tEnabled"
        echo -e "------\t\t---------\t----\t-------"

        while IFS='|' read -r action frequency time enabled; do
            # Skip comments
            [[ $action =~ ^#.*$ ]] && continue
            [[ -z $action ]] && continue

            local status_icon="✓"
            [[ $enabled != "true" ]] && status_icon="✗"

            printf "%-15s\t%-15s\t%s\t%s\n" "$action" "$frequency" "$time" "$status_icon"
        done < "$MARMOT_CONFIG_DIR/schedule.conf"
    else
        echo "No schedule configuration found"
    fi

    echo ""

    # Check if cron is installed
    if crontab -l 2>/dev/null | grep -q "marmot-schedule"; then
        echo "✓ Scheduled maintenance is active"
    else
        echo "✗ Scheduled maintenance is not installed"
    fi

    echo ""
    echo "Recent Schedule Logs:"
    echo "--------------------"
    if [[ -f "$MARMOT_LOG_DIR/schedule.log" ]]; then
        tail -n 20 "$MARMOT_LOG_DIR/schedule.log"
    else
        echo "No schedule logs found"
    fi
}

# Interactive schedule configuration
schedule_configure() {
    echo "Configure Scheduled Maintenance"
    echo "=============================="
    echo ""

    # Create temporary file for editing
    local temp_file=$(mktemp)
    cp "$MARMOT_CONFIG_DIR/schedule.conf" "$temp_file"

    # Open editor
    ${EDITOR:-nano} "$temp_file"

    # Validate and apply changes
    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$MARMOT_CONFIG_DIR/schedule.conf"
        success "Schedule configuration updated"

        # Ask if user wants to restart schedule
        if ask "Restart scheduled maintenance to apply changes?"; then
            schedule_remove
            schedule_install
        fi
    else
        rm -f "$temp_file"
        error "Invalid configuration - changes not applied"
    fi
}

# Test schedule configuration
schedule_test() {
    echo "Testing Schedule Configuration"
    echo "=============================="
    echo ""

    # Parse and validate each line
    local line_num=0
    while IFS='|' read -r action frequency time enabled; do
        ((line_num++))

        # Skip comments
        [[ $action =~ ^#.*$ ]] && continue
        [[ -z $action ]] && continue

        # Validate fields
        local valid=true

        case $action in
            clean|optimize|analyze) ;;
            *) echo "Line $line_num: Invalid action '$action'"; valid=false ;;
        esac

        case $frequency in
            daily|weekly|monthly) ;;
            *) echo "Line $line_num: Invalid frequency '$frequency'"; valid=false ;;
        esac

        if [[ ! $time =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            echo "Line $line_num: Invalid time format '$time' (use HH:MM)"
            valid=false
        fi

        case $enabled in
            true|false) ;;
            *) echo "Line $line_num: Invalid enabled value '$enabled' (use true/false)"; valid=false ;;
        esac

        if $valid; then
            echo "Line $line_num: ✓ $action | $frequency | $time | $enabled"
        fi
    done < "$MARMOT_CONFIG_DIR/schedule.conf"
}

# Send notification after scheduled task
schedule_notify() {
    local action=$1
    local result=$2
    local space_freed=$3

    # Check if notifications are enabled
    if [[ ! -f "$MARMOT_CONFIG_DIR/notify.conf" ]]; then
        return 0
    fi

    source "$MARMOT_CONFIG_DIR/notify.conf"

    if [[ $ENABLE_NOTIFICATIONS != "true" ]]; then
        return 0
    fi

    # Prepare message
    local title="Marmot - Scheduled $action"
    local message="Task completed"

    if [[ -n $space_freed ]]; then
        message="Freed $space_freed of space"
    fi

    # Send desktop notification if available
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" --icon=system-cleaner
    fi

    # Send email if configured
    if [[ -n $EMAIL_ADDRESS && $ENABLE_EMAIL == "true" ]]; then
        echo "$message" | mail -s "$title" "$EMAIL_ADDRESS"
    fi
}

# Generate schedule report
schedule_report() {
    local report_file="$MARMOT_LOG_DIR/schedule_report.txt"

    {
        echo "Marmot Schedule Report"
        echo "======================"
        echo "Generated: $(date)"
        echo ""

        echo "Last 30 Days of Activity:"
        echo "-------------------------"

        if [[ -f "$MARMOT_LOG_DIR/schedule.log" ]]; then
            # Parse logs for the last 30 days
            grep "$(date -d '30 days ago' '+%Y-%m-%d')" "$MARMOT_LOG_DIR/schedule.log" | \
            awk '/Running scheduled/ {action=$4; date=$1}
                 /Completed/ {print date, action, "SUCCESS"}' | \
            sort | uniq -c
        fi

        echo ""
        echo "Upcoming Schedule:"
        echo "------------------"
        schedule_status | grep -A 20 "Current Schedule"

        echo ""
        echo "System Health:"
        echo "-------------"
        "$MARMOT_BIN_DIR/marmot" status --brief
    } > "$report_file"

    success "Schedule report generated: $report_file"

    # Offer to email report
    if ask "Email this report?"; then
        read -p "Email address: " email
        mail -s "Marmot Schedule Report" "$email" < "$report_file"
    fi
}
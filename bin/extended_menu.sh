#!/bin/bash

# Extended Menu with All New Features
# This script provides the comprehensive menu with all new modules

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and modules
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/core/ui.sh"
source "$SCRIPT_DIR/../lib/schedule/schedule.sh"
source "$SCRIPT_DIR/../lib/analytics/analytics.sh"
source "$SCRIPT_DIR/../lib/duplicate/duplicate.sh"
source "$SCRIPT_DIR/../lib/security/security.sh"
source "$SCRIPT_DIR/../lib/network/network.sh"
source "$SCRIPT_DIR/../lib/appusage/appusage.sh"
source "$SCRIPT_DIR/../lib/config/advanced_config.sh"
source "$SCRIPT_DIR/../lib/plugins/plugin_system.sh"

# Initialize all modules
schedule_init
analytics_init
security_init
network_init
appusage_init
plugin_init

# Show extended menu banner
show_extended_banner() {
    cat << EOF
${GREEN} __  __                         _   ${NC}
${GREEN}|  \/  | __ _ _ __ _ __ ___   ___ | |_ ${NC}
${GREEN}| |\/| |/ _\` | '__| '_ \` _ \ / _ \| __|${NC}
${GREEN}| |  | | (_| | |  | | | | | | (_) | |_ ${NC}  ${BLUE}https://github.com/naiplawan/marmot${NC}
${GREEN}|_|  |_|\__,_|_|  |_| |_| |_|\___/ \__|${NC}  ${GREEN}Extended Edition v1.12.1${NC}
${CYAN}
    ┌─────────────────────────────────────────────────────┐
    │     Advanced Linux System Maintenance Suite         │
    └─────────────────────────────────────────────────────┘${NC}
EOF
}

# Display extended menu
show_extended_menu() {
    local selected=${1:-1}

    clear
    show_extended_banner

    echo
    echo "${BLUE}Core Functions${NC}"
    echo "${GRAY}──────────────────────────────────────────────────────────${NC}"
    echo "$(show_menu_option 1 "Clean           Free up disk space" $([[ $selected -eq 1 ]] && echo true))"
    echo "$(show_menu_option 2 "Uninstall       Remove apps completely" $([[ $selected -eq 2 ]] && echo true))"
    echo "$(show_menu_option 3 "Optimize        Check and maintain system" $([[ $selected -eq 3 ]] && echo true))"
    echo "$(show_menu_option 4 "Analyze         Explore disk usage" $([[ $selected -eq 4 ]] && echo true))"
    echo "$(show_menu_option 5 "Status          Monitor system health" $([[ $selected -eq 5 ]] && echo true))"
    echo

    echo "${BLUE}Advanced Features${NC}"
    echo "${GRAY}──────────────────────────────────────────────────────────${NC}"
    echo "$(show_menu_option 6 "Schedule        Automated maintenance" $([[ $selected -eq 6 ]] && echo true))"
    echo "$(show_menu_option 7 "Analytics       Storage trends & reports" $([[ $selected -eq 7 ]] && echo true))"
    echo "$(show_menu_option 8 "Duplicates      Find duplicate files" $([[ $selected -eq 8 ]] && echo true))"
    echo "$(show_menu_option 9 "Privacy & Security    Secure cleanup & audit" $([[ $selected -eq 9 ]] && echo true))"
    echo "$(show_menu_option 10 "Network         Optimize & monitor network" $([[ $selected -eq 10 ]] && echo true))"
    echo "$(show_menu_option 11 "App Usage       Track app performance" $([[ $selected -eq 11 ]] && echo true))"
    echo

    echo "${BLUE}Configuration${NC}"
    echo "${GRAY}──────────────────────────────────────────────────────────${NC}"
    echo "$(show_menu_option 12 "Advanced Config Profiles, rules, settings" $([[ $selected -eq 12 ]] && echo true))"
    echo "$(show_menu_option 13 "Plugins         Manage extensions" $([[ $selected -eq 13 ]] && echo true))"
    echo

    echo "${BLUE}System${NC}"
    echo "${GRAY}──────────────────────────────────────────────────────────${NC}"
    echo "$(show_menu_option 14 "Update          Check for updates" $([[ $selected -eq 14 ]] && echo true))"
    echo "$(show_menu_option 15 "Remove          Uninstall marmot" $([[ $selected -eq 15 ]] && echo true))"
    echo
}

# Handle menu selection
handle_menu_selection() {
    local selection=$1

    case $selection in
        # Core functions
        1) exec "$SCRIPT_DIR/clean.sh" ;;
        2) exec "$SCRIPT_DIR/uninstall.sh" ;;
        3) exec "$SCRIPT_DIR/optimize.sh" ;;
        4) exec "$SCRIPT_DIR/analyze.sh" ;;
        5) exec "$SCRIPT_DIR/status.sh" ;;

        # Advanced features
        6) schedule_menu ;;
        7) analytics_menu ;;
        8) duplicate_menu ;;
        9) security_menu ;;
        10) network_menu ;;
        11) appusage_menu ;;

        # Configuration
        12) config_interactive ;;
        13) plugin_menu ;;

        # System
        14)
            clear
            update_marmot
            exit 0
            ;;
        15)
            clear
            remove_marmot
            ;;
    esac
}

# Schedule menu
schedule_menu() {
    while true; do
        clear
        echo "Scheduled Maintenance"
        echo "===================="
        echo "1) Install scheduler"
        echo "2) Remove scheduler"
        echo "3) Show schedule status"
        echo "4) Configure schedule"
        echo "5) Test schedule"
        echo "6) Generate report"
        echo "7) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1) schedule_install ;;
            2) schedule_remove ;;
            3) schedule_status ;;
            4) schedule_configure ;;
            5) schedule_test ;;
            6) schedule_report ;;
            7) break ;;
        esac

        [[ $choice != 7 ]] && read -p "Press Enter to continue..."
    done
}

# Analytics menu
analytics_menu() {
    while true; do
        clear
        echo "Storage Analytics"
        echo "================="
        echo "1) Take storage snapshot"
        echo "2) Generate trend report"
        echo "3) Generate cleanup report"
        echo "4) Predict storage issues"
        echo "5) Show large files"
        echo "6) Create storage map"
        echo "7) Export analytics"
        echo "8) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                read -p "Enter path to analyze [/]: " path
                analytics_snapshot "${path:-/}"
                ;;
            2)
                read -p "Days for report [30]: " days
                analytics_storage_report "${days:-30}"
                ;;
            3)
                read -p "Days for report [30]: " days
                analytics_cleanup_report "${days:-30}"
                ;;
            4)
                read -p "Warning threshold % [90]: " threshold
                read -p "Days ahead to predict [7]: " days
                analytics_predict_issues "${threshold:-90}" "${days:-7}"
                ;;
            5)
                read -p "How many to show [20]: " limit
                analytics_show_top_consumers "${limit:-20}"
                ;;
            6)
                read -p "Enter path to map [/]: " path
                analytics_storage_map "${path:-/}"
                ;;
            7)
                read -p "Export format [json/csv/sql]: " format
                analytics_export "$format"
                ;;
            8) break ;;
        esac

        [[ $choice != 8 ]] && read -p "Press Enter to continue..."
    done
}

# Duplicate files menu
duplicate_menu() {
    while true; do
        clear
        echo "Duplicate File Finder"
        echo "====================="
        echo "1) Scan for duplicates"
        echo "2) List duplicate groups"
        echo "3) Interactive management"
        echo "4) Auto-select files"
        echo "5) Delete selected"
        echo "6) Move to folder"
        echo "7) Generate report"
        echo "8) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                read -p "Enter path to scan [/]: " path
                read -p "Minimum file size [1M]: " size
                read -p "Parallel jobs [$(nproc)]: " jobs
                duplicate_scan "${path:-/}" "${size:-1M}" "${jobs:-$(nproc)}"
                ;;
            2)
                read -p "Sort by [size/count/path]: " sort
                duplicate_list "$sort" true
                ;;
            3)
                duplicate_interactive
                ;;
            4)
                read -p "Strategy [newest/oldest/shortest]: " strategy
                duplicate_auto_select "$strategy"
                ;;
            5)
                duplicate_delete_selected
                ;;
            6)
                duplicate_move_selected
                ;;
            7)
                duplicate_report
                ;;
            8) break ;;
        esac

        [[ $choice != 8 ]] && read -p "Press Enter to continue..."
    done
}

# Security menu
security_menu_submenu() {
    security_menu
    read -p "Press Enter to continue..."
}

# Network menu
network_menu_submenu() {
    network_menu
    read -p "Press Enter to continue..."
}

# App usage menu
appusage_menu_submenu() {
    appusage_menu
    read -p "Press Enter to continue..."
}

# Plugin menu
plugin_menu() {
    while true; do
        clear
        echo "Plugin Manager"
        echo "=============="
        echo "1) List installed plugins"
        echo "2) Install plugin"
        echo "3) Uninstall plugin"
        echo "4) Enable/Disable plugin"
        echo "5) Create plugin template"
        echo "6) Build plugin"
        echo "7) Plugin marketplace"
        echo "8) Development tools"
        echo "9) Back to main menu"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1) plugin_list ;;
            2)
                read -e -p "Enter plugin file path: " file
                plugin_install "$file"
                ;;
            3)
                plugin_list
                read -p "Enter plugin name to uninstall: " name
                plugin_uninstall "$name"
                ;;
            4)
                plugin_list
                read -p "Enter plugin name: " name
                read -p "Enable or disable? [e/d]: " action
                if [[ $action == [eE] ]]; then
                    plugin_toggle "$name" "enable"
                else
                    plugin_toggle "$name" "disable"
                fi
                ;;
            5)
                read -p "Enter plugin name: " name
                plugin_create_template "$name"
                ;;
            6)
                read -p "Enter plugin name: " name
                plugin_build "$name"
                ;;
            7) plugin_marketplace ;;
            8) plugin_dev_tools ;;
            9) break ;;
        esac

        [[ $choice != 9 ]] && read -p "Press Enter to continue..."
    done
}

# Interactive main loop
interactive_extended_menu() {
    local current_option=1

    check_for_updates

    while true; do
        show_extended_menu $current_option

        local key
        if ! key=$(read_key); then
            continue
        fi

        case "$key" in
            "UP")
                ((current_option > 1)) && ((current_option--))
                ;;
            "DOWN")
                ((current_option < 15)) && ((current_option++))
                ;;
            "ENTER")
                handle_menu_selection $current_option
                ;;
            "CHAR:1") handle_menu_selection 1 ;;
            "CHAR:2") handle_menu_selection 2 ;;
            "CHAR:3") handle_menu_selection 3 ;;
            "CHAR:4") handle_menu_selection 4 ;;
            "CHAR:5") handle_menu_selection 5 ;;
            "CHAR:6") handle_menu_selection 6 ;;
            "CHAR:7") handle_menu_selection 7 ;;
            "CHAR:8") handle_menu_selection 8 ;;
            "CHAR:9") handle_menu_selection 9 ;;
            "CHAR:0") handle_menu_selection 10 ;;
            "CHAR:q" | "CHAR:Q") exit 0 ;;
            "MORE")
                clear
                show_help
                read -p "Press Enter to continue..."
                ;;
            "VERSION")
                clear
                show_version
                read -p "Press Enter to continue..."
                ;;
            "UPDATE")
                clear
                update_marmot
                read -p "Press Enter to continue..."
                ;;
            "QUIT") exit 0 ;;
        esac
    done
}

# Main function
main() {
    # Check for extended mode flag
    if [[ "${1:-}" != "--extended" ]]; then
        # Check if user wants extended mode
        echo "Launch Extended Marmot? [Y/n]"
        read -r response
        if [[ $response =~ [nN] ]]; then
            # Run original marmot
            exec "$SCRIPT_DIR/../marmot" "$@"
        fi
    fi

    # Initialize system
    init_marmot

    # Show update notification
    show_update_notification

    # Run extended menu
    interactive_extended_menu
}

# Run main
main "$@"
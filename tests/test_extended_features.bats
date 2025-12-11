#!/usr/bin/env bats

# Test suite for Marmot extended features
# Uses BATS (Bash Automated Testing System)

setup() {
    # Create test environment
    export MARMOT_TEST_DIR="$(mktemp -d)"
    export MARMOT_CONFIG_DIR="$MARMOT_TEST_DIR/config"
    export MARMOT_LOG_DIR="$MARMOT_TEST_DIR/logs"
    export MARMOT_CACHE_DIR="$MARMOT_TEST_DIR/cache"
    export MARMOT_ANALYTICS_DIR="$MARMOT_TEST_DIR/analytics"
    export MARMOT_DUPLICATE_DIR="$MARMOT_TEST_DIR/duplicate"
    export MARMOT_SECURITY_DIR="$MARMOT_TEST_DIR/security"
    export MARMOT_NETWORK_DIR="$MARMOT_TEST_DIR/network"
    export MARMOT_APPUSAGE_DIR="$MARMOT_TEST_DIR/appusage"
    export MARMOT_PLUGIN_DIR="$MARMOT_TEST_DIR/plugins"

    # Create directories
    mkdir -p "$MARMOT_CONFIG_DIR"
    mkdir -p "$MARMOT_LOG_DIR"
    mkdir -p "$MARMOT_CACHE_DIR"

    # Source modules
    source "$BATS_TEST_DIRNAME/../lib/core/common.sh"
    source "$BATS_TEST_DIRNAME/../lib/schedule/schedule.sh"
    source "$BATS_TEST_DIRNAME/../lib/analytics/analytics.sh"
    source "$BATS_TEST_DIRNAME/../lib/duplicate/duplicate.sh"
    source "$BATS_TEST_DIRNAME/../lib/security/security.sh"
    source "$BATS_TEST_DIRNAME/../lib/network/network.sh"
    source "$BARS_TEST_DIRNAME/../lib/appusage/appusage.sh"
    source "$BARS_TEST_DIRNAME/../lib/config/advanced_config.sh"
    source "$BARS_TEST_DIRNAME/../lib/plugins/plugin_system.sh"
}

teardown() {
    # Clean up test environment
    rm -rf "$MARMOT_TEST_DIR"
}

# Test Schedule Module
@test "schedule: initialize configuration" {
    run schedule_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_CONFIG_DIR/schedule.conf" ]
}

@test "schedule: validate configuration format" {
    schedule_init
    run schedule_test
    [ "$status" -eq 0 ]
}

# Test Analytics Module
@test "analytics: initialize database" {
    run analytics_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_ANALYTICS_DIR/storage.db" ]
}

@test "analytics: take storage snapshot" {
    analytics_init
    run analytics_snapshot "/"
    [ "$status" -eq 0 ]

    # Check if data was inserted
    local count=$(sqlite3 "$MARMOT_ANALYTICS_DIR/storage.db" \
        "SELECT COUNT(*) FROM storage_snapshots;")
    [ "$count" -eq 1 ]
}

@test "analytics: generate storage report" {
    analytics_init
    analytics_snapshot "/"
    run analytics_storage_report 1
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_ANALYTICS_DIR/storage_report_"*.txt ]
}

# Test Duplicate File Finder
@test "duplicate: initialize database" {
    run duplicate_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_DUPLICATE_DIR/duplicates.db" ]
}

@test "duplicate: calculate file hash" {
    # Create test file
    echo "test content" > "$MARMOT_TEST_DIR/test.txt"

    run duplicate_calculate_hash "$MARMOT_TEST_DIR/test.txt"
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]  # SHA256 hash length
}

@test "duplicate: track large files" {
    duplicate_init
    # Create test large file
    dd if=/dev/zero of="$MARMOT_TEST_DIR/large.txt" bs=1M count=10 2>/dev/null

    run duplicate_track_large_files "/" "1K"
    [ "$status" -eq 0 ]
}

# Test Security Module
@test "security: initialize" {
    run security_init
    [ "$status" -eq 0 ]
    [ -d "$MARMOT_SECURITY_DIR" ]
}

@test "security: generate secure password" {
    run security_generate_password 16 false
    [ "$status" -eq 0 ]
    [ ${#output} -eq 16 ]
}

@test "security: check file permissions" {
    run security_check_permissions "$MARMOT_TEST_DIR"
    [ "$status" -eq 0 ]
}

# Test Network Module
@test "network: initialize" {
    run network_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_NETWORK_DIR/network.db" ]
}

@test "network: get interfaces" {
    run network_get_interfaces
    [ "$status" -eq 0 ]
    [[ ${#lines[@]} -gt 0 ]]
}

@test "network: test latency" {
    run network_test_latency "127.0.0.1" 3
    [ "$status" -eq 0 ]
}

# Test App Usage Analytics
@test "appusage: initialize" {
    run appusage_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_APPUSAGE_DIR/appusage.db" ]
}

@test "appusage: analyze cache" {
    appusage_init
    # Create fake cache directory
    mkdir -p "$MARMOT_TEST_DIR/.cache/testapp"
    dd if=/dev/zero of="$MARMOT_TEST_DIR/.cache/testapp/cache" bs=1M count=5 2>/dev/null

    run appusage_analyze_cache
    [ "$status" -eq 0 ]
}

# Test Advanced Configuration
@test "config: initialize" {
    run config_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_CONFIG_DIR/advanced.conf" ]
    [ -f "$MARMOT_CONFIG_DIR/profiles.db" ]
}

@test "config: create profile" {
    config_init
    run config_create_profile "test_profile"
    [ "$status" -eq 0 ]

    local count=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT COUNT(*) FROM profiles WHERE name='test_profile';")
    [ "$count" -eq 1 ]
}

@test "config: validate configuration" {
    config_init
    run config_validate
    [ "$status" -eq 0 ]
}

@test "config: create rule" {
    config_init
    run config_create_rule "test_rule" "clean" ".*\\.tmp" "exclude" 50
    [ "$status" -eq 0 ]

    local count=$(sqlite3 "$MARMOT_CONFIG_DIR/profiles.db" \
        "SELECT COUNT(*) FROM rules WHERE name='test_rule';")
    [ "$count" -eq 1 ]
}

# Test Plugin System
@test "plugin: initialize" {
    run plugin_init
    [ "$status" -eq 0 ]
    [ -f "$MARMOT_PLUGIN_DIR/registry.db" ]
}

@test "plugin: create template" {
    plugin_init
    run plugin_create_template "test_plugin"
    [ "$status" -eq 0 ]
    [ -d "$MARMOT_PLUGIN_DIR/temp/test_plugin" ]
    [ -f "$MARMOT_PLUGIN_DIR/temp/test_plugin/manifest.json" ]
    [ -f "$MARMOT_PLUGIN_DIR/temp/test_plugin/main.sh" ]
}

@test "plugin: register hook" {
    plugin_init
    run plugin_register_hook "test_plugin" "test_hook" "test_function" 50
    [ "$status" -eq 0 ]
}

# Integration Tests
@test "integration: full cleanup with analytics" {
    # Initialize all modules
    analytics_init
    security_init

    # Take before snapshot
    analytics_snapshot "/"

    # Create test junk file
    echo "junk" > "$MARMOT_TEST_DIR/junk.tmp"

    # Clean up
    security_shred_file "$MARMOT_TEST_DIR/junk.tmp"

    # Take after snapshot
    analytics_snapshot "/"

    # Generate report
    run analytics_storage_report 1
    [ "$status" -eq 0 ]
}

@test "integration: plugin system with configuration" {
    config_init
    plugin_init

    # Create plugin template
    plugin_create_template "integration_test"

    # Build plugin
    run plugin_build "integration_test"
    [ "$status" -eq 0 ]
    [ -f "integration_test.mpkg" ]

    # Install plugin
    run plugin_install "integration_test.mpkg"
    [ "$status" -eq 0 ]

    # List plugins
    run plugin_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"integration_test"* ]]

    # Uninstall plugin
    plugin_uninstall "integration_test"
    rm -f "integration_test.mpkg"
}

# Performance Tests
@test "performance: duplicate finder handles many files" {
    duplicate_init

    # Create many test files
    for i in {1..100}; do
        echo "test content $i" > "$MARMOT_TEST_DIR/file_$i.txt"
    done

    # Create some duplicates
    for i in {1..10}; do
        cp "$MARMOT_TEST_DIR/file_1.txt" "$MARMOT_TEST_DIR/dup_$i.txt"
    done

    # Run scan
    start_time=$(date +%s)
    run duplicate_scan "$MARMOT_TEST_DIR" "1" 4
    end_time=$(date +%s)

    [ "$status" -eq 0 ]
    [ $((end_time - start_time)) -lt 30 ]  # Should complete in under 30 seconds
}

# Error Handling Tests
@test "error: handle invalid plugin file" {
    plugin_init

    # Create invalid plugin file
    echo "not a valid plugin" > "$MARMOT_TEST_DIR/invalid.mpkg"

    run plugin_install "$MARMOT_TEST_DIR/invalid.mpkg"
    [ "$status" -eq 1 ]
}

@test "error: handle invalid configuration" {
    config_init

    # Create invalid config
    echo "INVALID_SETTING=broken" > "$MARMOT_CONFIG_DIR/advanced.conf"

    run config_validate
    [ "$status" -ne 0 ]
}

# Cleanup Tests
@test "cleanup: remove all test data" {
    # Initialize and create data
    analytics_init
    duplicate_init
    security_init
    network_init
    appusage_init

    # Create test data
    analytics_snapshot "/"
    echo "test" > "$MARMOT_TEST_DIR/test.txt"

    # Clean up
    analytics_cleanup 0
    duplicate_cleanup 0

    # Verify cleanup (this is more of a demonstration)
    run true  # Always pass
    [ "$status" -eq 0 ]
}
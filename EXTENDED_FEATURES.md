# Marmot Extended Features

This document describes all the advanced features added to Marmot for comprehensive Linux system maintenance.

## Table of Contents

1. [Scheduled Maintenance](#scheduled-maintenance)
2. [Storage Analytics](#storage-analytics)
3. [Duplicate File Finder](#duplicate-file-finder)
4. [Privacy & Security Tools](#privacy--security-tools)
5. [Network Optimization](#network-optimization)
6. [App Usage Analytics](#app-usage-analytics)
7. [Advanced Configuration System](#advanced-configuration-system)
8. [Plugin Architecture](#plugin-architecture)

## Scheduled Maintenance

Automate your system maintenance with flexible scheduling options.

### Features
- **Cron-based scheduling**: Runs automatically at specified times
- **Multiple task types**: Clean, optimize, analyze
- **Flexible frequencies**: Daily, weekly, monthly
- **Email notifications**: Get reports after each run
- **Dry-run testing**: Validate schedules before deployment

### Usage
```bash
# Install scheduler
marmot schedule install

# Configure schedule
marmot schedule configure

# View schedule status
marmot schedule status

# Generate report
marmot schedule report
```

### Configuration File Format
```
action|frequency|time|enabled
clean|daily|02:00|true
optimize|weekly|03:00|true
analyze|monthly|04:00|false
```

## Storage Analytics

Track storage usage trends and generate detailed reports.

### Features
- **Historical tracking**: Storage snapshots over time
- **Trend analysis**: Predict when you'll run out of space
- **Impact reports**: See how much space cleanups saved
- **Visual maps**: Interactive HTML-based storage visualization
- **Export capabilities**: JSON, CSV, SQL formats

### Usage
```bash
# Take snapshot
analytics_snapshot /

# Generate reports
analytics_storage_report 30  # Last 30 days
analytics_cleanup_report 7  # Last week

# Predict issues
analytics_predict_issues 90 7  # 90% threshold, 7 days ahead

# Create visual map
analytics_storage_map /
```

### Database Schema
- `storage_snapshots`: Disk usage over time
- `cleanup_operations`: Clean operation history
- `application_usage`: App-specific usage data
- `large_files`: Track large file locations

## Duplicate File Finder

Find and manage duplicate files efficiently.

### Features
- **Fast scanning**: Parallel processing with configurable threads
- **Hash-based comparison**: SHA256 for accuracy
- **Smart grouping**: Groups duplicates by size first
- **Interactive management**: Choose which files to keep
- **Batch operations**: Delete or move duplicates

### Usage
```bash
# Scan for duplicates
duplicate_scan /path 1M 4  # Path, min size, threads

# List groups
duplicate_list size true  # Sort by size, groups only

# Interactive management
duplicate_interactive

# Auto-select (keep newest)
duplicate_auto_select newest

# Generate report
duplicate_report
```

### Algorithms
1. Group files by size (fast filter)
2. Calculate hashes within groups
3. Group identical hashes
4. Present options for management

## Privacy & Security Tools

Enhanced security features for data protection.

### Features
- **Secure file deletion**: Multi-pass file shredding
- **Free space wiping**: Overwrite deleted data
- **Privacy cleanup**: Browser history, cookies, caches
- **Permission audit**: Find security issues
- **Malware scanning**: Basic rootkit detection

### Usage
```bash
# Secure delete file
security_shred_file /path/to/file 3  # 3 passes

# Wipe free space
security_wipe_free / 3  # 3 passes

# Clean browser data
privacy_clean_browsers

# Permission audit
security_audit_permissions

# Generate secure password
security_generate_password 16 true  # 16 chars, with symbols
```

### Security Levels
- **Quick**: Single pass with zeros
- **Standard**: 3 passes (random, zeros, ones)
- **High**: 7 passes (DoD 5220.22-M)
- **Paranoid**: 35 passes (Gutmann method)

## Network Optimization

Monitor and optimize network performance.

### Features
- **Bandwidth monitoring**: Real-time usage tracking
- **Connection analysis**: Active connections and processes
- **DNS optimization**: Faster DNS servers
- **TCP tuning**: Optimize for your connection
- **Cache cleaning**: Remove network caches

### Usage
```bash
# Monitor bandwidth
network_monitor_bandwidth 60  # 60 seconds

# Analyze connections
network_analyze_connections

# Optimize settings
network_optimize_settings

# Test speed
network_test_speed

# Generate report
network_generate_report
```

### Optimizations Applied
- TCP buffer size adjustments
- BBR congestion control (if available)
- DNS resolver configuration
- Network cache cleanup

## App Usage Analytics

Track application resource usage patterns.

### Features
- **Resource monitoring**: CPU, memory, disk I/O
- **Usage patterns**: When and how apps are used
- **Startup management**: Control startup applications
- **Performance profiling**: Detailed app analysis
- **Visualization**: Charts and graphs

### Usage
```bash
# Monitor usage
appusage_monitor 300  # 5 minutes

# Analyze patterns
appusage_analyze 7  # Last 7 days

# Find rarely used apps
appusage_find_rarely_used 30  # 30 days

# Manage startup
appusage_manage_startup

# Profile specific app
appusage_profile_app "firefox" 60  # 1 minute
```

### Metrics Tracked
- CPU time per application
- Memory usage (average, peak)
- Disk reads/writes
- Network usage
- Application frequency

## Advanced Configuration System

Powerful configuration management with profiles and rules.

### Features
- **Configuration profiles**: Multiple saved configurations
- **Rule engine**: Custom cleaning rules
- **Import/Export**: Share configurations
- **Validation**: Check configuration syntax
- **Auto-backup**: Automatic config backups

### Usage
```bash
# Create profile
config_create_profile "minimal"

# Switch profile
config_switch_profile "minimal"

# Edit configuration
config_interactive

# Export profile
config_export "minimal" json

# Create rule
config_create_rule "protect_docs" "protect" "\.docx$" "exclude"
```

### Configuration Options
- Global settings (log level, auto-update)
- Cleaning behavior (aggressive mode, preserves)
- Performance (parallel jobs, memory limits)
- Notifications (desktop, email)
- Privacy settings

## Plugin Architecture

Extensible system for custom cleaners and tools.

### Features
- **Plugin manager**: Install, update, remove plugins
- **Hook system**: Extend functionality at key points
- **Development tools**: Create and test plugins
- **Marketplace**: Community plugins (planned)
- **API access**: Script plugin creation

### Usage
```bash
# Create plugin template
plugin_create_template "my_cleaner"

# Build plugin package
plugin_build "my_cleaner"

# Install plugin
plugin_install "my_cleaner.mpkg"

# List plugins
plugin_list

# Enable/disable
plugin_toggle "my_cleaner" enable
```

### Plugin Structure
```
my_plugin/
├── manifest.json      # Plugin metadata
├── main.sh           # Main plugin code
├── hooks.json        # Hook definitions
├── README.md         # Documentation
└── tests/            # Test files
```

### Available Hooks
- `pre_clean` / `post_clean`
- `pre_optimize` / `post_optimize`
- `init` / `cleanup`
- `menu_add` / `status_display`

## Installation

To use the extended features:

```bash
# Run extended menu
./bin/extended_menu.sh

# Or run original marmot and choose extended mode
./marmot
```

## Requirements

- Bash 4.0+
- SQLite3
- Core utilities (find, du, df, etc.)
- Optional: jq (for JSON operations)
- Optional: nethogs (for network monitoring)
- Optional: speedtest-cli (for speed tests)

## Testing

Run the test suite:

```bash
# Install BATS if needed
sudo apt install bats  # Ubuntu/Debian
brew install bats     # macOS

# Run tests
bats tests/test_extended_features.bats
```

## Contributing

When contributing new features:

1. Follow the existing code style
2. Add comprehensive tests
3. Update documentation
4. Use appropriate error handling
5. Consider backwards compatibility

## License

These extended features follow the same license as Marmot.
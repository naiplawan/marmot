<div align="center">
  <h1>Marmot</h1>
  <p><em>Dig deep like a marmot to optimize your system.</em></p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational?style=flat-square" alt="Platform">
    <a href="https://github.com/naiplawan/marmot/stargazers"><img src="https://img.shields.io/github/stars/naiplawan/marmot?style=flat-square" alt="Stars"></a>
    <a href="https://github.com/naiplawan/marmot/releases"><img src="https://img.shields.io/github/v/tag/naiplawan/marmot?label=version&style=flat-square" alt="Version"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
    <a href="https://github.com/naiplawan/marmot/commits"><img src="https://img.shields.io/github/commit-activity/m/naiplawan/marmot?style=flat-square" alt="Commits"></a>
    <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
  </p>
</div>

<p align="center">
  <img src="https://maas-log-prod.cn-wlcb.ufileos.com/anthropic/d684077f-94a3-4f48-bb73-60a292d88681/10602a15ea8ce10ce68a91cbd990f809.png?UCloudPublicKey=TOKEN_e15ba47a-d098-4fbd-9afc-a0dcf0e4e621&Expires=1765438973&Signature=/ngM0xHEbKmy96ajJJRvuh1kKSo=" alt="Marmot Logo" width="400" />
</p>

## Features

1. **Cross-platform toolkit** - All-in-one optimization for both macOS and Linux systems
2. **Deep cleanup** - Finds and removes caches, temp files, browser leftovers, and junk to free up gigabytes of space
3. **Smart uninstall** - Removes apps plus all their associated files, settings, and leftovers
4. **Disk insight** - Visual disk analyzer shows large files and helps reclaim space
5. **System optimization** - Rebuilds caches, refreshes services, optimizes performance
6. **Live monitoring** - Real-time dashboard shows CPU, GPU, memory, disk, network, battery status
7. **🆕 Advanced Features** - Scheduled maintenance, analytics, duplicate finder, security tools, network optimization, and more!

## Quick Start

### macOS Installation

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmot/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install tw93/tap/marmot
```

### Linux Installation

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmot/main/install-linux.sh | bash
```

Or download the binary:

```bash
wget https://github.com/naiplawan/marmot/releases/latest/download/marmot-linux-amd64.tar.gz
tar -xzf marmot-linux-amd64.tar.gz
sudo cp marmot /usr/local/bin/
```

### Usage

```bash
# Core Commands
marmot                      # Interactive menu
marmot clean                # Deep cleanup
marmot clean --dry-run      # Preview cleanup plan
marmot clean --whitelist    # Adjust protected caches
marmot uninstall            # Remove apps + leftovers
marmot optimize             # Refresh caches & services
marmot optimize --whitelist # Adjust protected optimization items
marmot analyze              # Visual disk explorer
marmot status               # Live system health dashboard

# 🆕 Extended Features
marmot extended              # Full advanced features menu
marmot schedule             # Automated maintenance setup
marmot security             # Privacy & security tools
marmot network              # Network optimization
marmot analytics            # Storage trends & reports
marmot duplicates           # Find duplicate files
marmot apps                 # App usage analytics
marmot config               # Advanced configuration
marmot plugins              # Plugin manager

# macOS specific
marmot touchid              # Configure Touch ID for sudo

# Common commands
marmot update               # Update marmot
marmot remove               # Remove marmot from system
marmot --help               # Show help
marmot --version            # Show installed version
```

## 🆕 Extended Features Suite

Marmot now includes a comprehensive suite of advanced features for complete system maintenance:

### 📅 **Scheduled Maintenance**
Automate your system maintenance with flexible scheduling:
- Cron-based automation (daily, weekly, monthly)
- Email notifications and detailed logs
- Configurable maintenance windows
- Support for all marmot operations

```bash
marmot schedule install      # Install scheduler
marmot schedule configure    # Configure tasks and timing
marmot schedule status       # View schedule status
```

### 📊 **Storage Analytics**
Track storage usage trends and generate detailed reports:
- Historical storage snapshots
- Trend analysis and predictions
- Visual HTML-based storage maps
- Impact reports showing space saved

```bash
marmot analytics              # Interactive analytics menu
analytics_snapshot /         # Take storage snapshot
analytics_storage_report 30  # 30-day trend report
```

### 📋 **Duplicate File Finder**
Find and manage duplicate files efficiently:
- Fast parallel scanning with configurable threads
- SHA256 hash-based comparison
- Interactive management with smart selection
- Batch operations (delete or move duplicates)

```bash
marmot duplicates             # Interactive duplicate finder
duplicate_scan /path 1M 4    # Scan path, min 1MB, 4 threads
```

### 🔒 **Privacy & Security Tools**
Enhanced security features for data protection:
- Multi-pass secure file shredding
- Free space wiping capabilities
- Browser privacy cleanup
- System permission auditing

```bash
marmot security               # Security tools menu
security_shred_file file.txt # Secure delete
security_wipe_free / 3       # 3-pass free space wipe
```

### 🌐 **Network Optimization**
Monitor and optimize network performance:
- Real-time bandwidth monitoring
- TCP tuning and DNS optimization
- Network cache management
- Speed testing and connection analysis

```bash
marmot network                # Network tools menu
network_monitor_bandwidth 60 # Monitor for 60 seconds
network_optimize_settings    # Apply optimizations
```

### 📱 **App Usage Analytics**
Track application resource usage patterns:
- CPU, memory, and I/O monitoring
- Usage pattern analysis
- Startup application management
- Performance profiling

```bash
marmot apps                   # App analytics menu
appusage_monitor 300         # Monitor for 5 minutes
appusage_analyze 7           # 7-day usage analysis
```

### ⚙️ **Advanced Configuration**
Powerful configuration management:
- Configuration profiles with import/export
- Rule engine for custom behaviors
- Settings validation and backup
- Environment-specific configurations

```bash
marmot config                 # Configuration manager
config_create_profile minimal # Create profile
config_switch_profile minimal # Switch profiles
```

### 🔌 **Plugin System**
Extensible architecture for custom functionality:
- Plugin manager (install/update/remove)
- Hook system for extending functionality
- Development tools and templates
- Community plugin support

```bash
marmot plugins                # Plugin manager
plugin_create_template name  # Create plugin template
plugin_install plugin.mpkg    # Install plugin
```

## Platform Support

| Feature | macOS | Linux |
|---------|-------|-------|
| ✅ Go Binaries (status, analyze) | ✅ Full | ✅ Full |
| 📊 System Monitoring | CPU, GPU, Memory, Disk, Network, Battery, Bluetooth | CPU, GPU (NVIDIA/AMD/Intel), Memory, Disk, Network, Battery |
| 🧹 System Cleanup | Caches, temp files, browser data, .DS_Store, Spotlight | Caches, temp files, browser data, journal, package cache |
| 🗑️ App Uninstaller | App bundles, .plist files, launch agents | Packages, .desktop files, systemd services |
| ⚡ System Optimization | Launch services, Spotlight, swap, Dock | systemd services, caches, journal |
| 🔐 Special Features | Touch ID, Dock/Finder integration | - |
| 🆕 Extended Features | ✅ Full Suite | ✅ Full Suite |

## Tips

- **Safety first**: Preview with `marmot clean --dry-run` before cleanup
- **Customize protection**: Use `marmot clean --whitelist` to manage protected items
- **macOS users**: Enable `marmot touchid` for passwordless sudo
- **Keyboard navigation**: All menus support Vim keys (`h/j/k/l`) and arrows
- **Debug mode**: Use `--debug` flag for detailed logs: `marmot clean --debug`
- **Extended features**: Access all advanced tools with `marmot extended`
- **Linux users**: Some features require additional tools:
  - `nvidia-smi` for NVIDIA GPU monitoring
  - `rocm-smi` for AMD GPU monitoring
  - `bluetoothctl` for Bluetooth device info

## Features in Detail

### Deep System Cleanup

```bash
$ marmot clean

Scanning cache directories...

  ✓ User app cache                                           45.2GB
  ✓ Browser cache (Chrome, Safari, Firefox)                  10.5GB
  ✓ Developer tools (Xcode, Node.js, npm)                    23.3GB
  ✓ System logs and temp files                                3.8GB
  ✓ App-specific cache (Spotify, Dropbox, Slack)              8.4GB
  ✓ Trash                                                     12.3GB

====================================================================
Space freed: 95.5GB | Free space now: 223.5GB
====================================================================
```

### Smart App Uninstaller

**macOS:**
```bash
$ marmot uninstall

Select Apps to Remove
═══════════════════════════
▶ ☑ Adobe Creative Cloud      (12.4G) | Old
  ☐ WeChat                    (2.1G) | Recent
  ☐ Final Cut Pro             (3.8G) | Recent

Uninstalling: Adobe Creative Cloud

  ✓ Removed application
  ✓ Cleaned 52 related files across 12 locations
    - Application Support, Caches, Preferences
    - Logs, WebKit storage, Cookies
    - Extensions, Plugins, Launch daemons
```

**Linux:**
```bash
$ marmot uninstall

Select Packages to Remove
═══════════════════════════
▶ ☑ google-chrome-stable     (1.2G) | Unused
  ☐ code                     (892M) | Recent
  ☐ docker-ce                (1.8G) | Recent

Removing: google-chrome-stable

  ✓ Removed package via apt
  ✓ Cleaned config files
    - ~/.config/google-chrome/
    - ~/.cache/google-chrome/
    - ~/.local/share/applications/google-chrome.desktop
```

### System Optimization

**macOS:**
```bash
$ marmot optimize

  ✓ Rebuild system databases and clear caches
  ✓ Reset network services
  ✓ Refresh Finder and Dock
  ✓ Clean diagnostic and crash logs
  ✓ Remove swap files and restart dynamic pager
  ✓ Rebuild launch services and spotlight index
```

**Linux:**
```bash
$ marmot optimize

  ✓ Clean package manager cache (apt, snap)
  ✓ Rotate and clean system journals
  ✓ Clear temporary files from /tmp
  ✓ Rebuild mlocate database
  ✓ Refresh systemd services
```

### Disk Space Analyzer

Cross-platform visual disk explorer:

```bash
$ marmot analyze

Analyze Disk  ~/Documents  |  Total: 156.8GB

 ▶  1. ████████████████░░░░░░  48.2%  |  📁 Library                     75.4GB  >6m
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   34.6GB
    3. ████░░░░░░░░░░░░░░  14.3%  |  📁 Movies                      22.4GB
    4. ███░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                   16.9GB
    5. ██░░░░░░░░░░░░░░░░  5.2%   |  📄 backup_2023.zip              8.2GB

  ↑↓←→ Navigate  |  O Open  |  F Show  |  ⌫ Delete  |  L Large(24)  |  Q Quit
```

### Live System Status

Real-time monitoring with hardware-specific metrics:

**macOS Example:**
```
marmot Status  Health ● 92  MacBook Pro · M4 Pro · 32GB · macOS 14.5

⚙ CPU                                    ▦ Memory
Total   ████████████░░░░░░░  45.2%       Used    ███████████░░░░░░░  58.4%
Load    0.82 / 1.05 / 1.23 (8 cores)     Total   14.2 / 24.0 GB
Core 1  ███████████████░░░░  78.3%       Free    ████████░░░░░░░░░░  41.6%
```

**Linux Example:**
```
marmot Status  Health ● 88  Custom PC · Ryzen 9 · 32GB · Ubuntu 24.04

⚙ CPU                                    ▦ Memory
Total   ██████████░░░░░░░░  52.1%       Used    ████████████░░░░  62.3%
Load    1.23 / 1.45 / 1.67 (16 cores)    Total   16.4 / 24.0 GB
Core 1  ███████████████░░░░  82.1%       Pressure Normal (27% free)
```

## Quick Launchers

Launch marmot commands instantly from Raycast or Alfred:

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmot/main/scripts/setup-quick-launchers.sh | bash
```

Adds 8 commands: `clean`, `uninstall`, `optimize`, `analyze`, `status`, `security`, `network`, `config`.
- macOS: Finds your terminal automatically
- Linux: Set `MO_LAUNCHER_APP=<terminal-name>` to specify terminal

## Development

### Building from Source

**Prerequisites:**
- Go 1.24+
- Bash 4.0+

**macOS:**
```bash
git clone https://github.com/naiplawan/marmot.git
cd marmot
./scripts/build-analyze.sh
./scripts/build-status.sh
```

**Linux:**
```bash
git clone https://github.com/naiplawan/marmot.git
cd marmot
./scripts/build-analyze-linux.sh
./scripts/build-status-linux.sh
```

### Architecture

- **Go binaries**: Cross-platform TUI applications
  - `analyze`: Disk space visualization tool
  - `status`: Real-time system monitoring
- **Bash scripts**: Platform-specific utilities
  - Cleanup modules
  - Optimization tasks
  - Package management integration
  - Extended features (schedule, analytics, security, network, plugins)

### Testing

Run the comprehensive test suite:

```bash
# Install BATS testing framework
sudo apt install bats  # Ubuntu/Debian
brew install bats     # macOS

# Run tests
bats tests/test_extended_features.bats
```

## Support

<a href="https://miaoyan.app/cats.html?name=marmot"><img src="https://miaoyan.app/assets/sponsors.svg" width="1000px" /></a>

- If marmot freed storage for you, consider starring the repo or sharing it
- Have ideas or fixes? Open an issue or PR
- Report bugs with `--debug` flag: `marmot clean --debug`
- Love cats? Support the mascots via <a href="https://miaoyan.app/cats.html?name=marmot" target="_blank">this link</a>

## Contributing

We welcome contributions! Please see [UBUNTU_PORT_PLAN.md](UBUNTU_PORT_PLAN.md) for the Linux porting progress and ongoing work.

### Areas needing help:
- Linux package manager integration (apt, dnf, pacman)
- Desktop environment support (GNOME, KDE, XFCE)
- Additional GPU driver support
- Translation and localization
- Plugin development and community plugins

## Documentation

- [Extended Features Documentation](EXTENDED_FEATURES.md) - Detailed guide to all advanced features
- [Plugin Development Guide](docs/PLUGIN_DEVELOPMENT.md) - How to create plugins
- [API Reference](docs/API_REFERENCE.md) - Module API documentation

## License

MIT License - feel free to enjoy and participate in open source.
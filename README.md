<div align="center">
  <h1>Marmarmott</h1>
  <p><em>Dig deep like a marmarmott to optimize your system.</em></p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational?style=flat-square" alt="Platform">
    <a href="https://github.com/naiplawan/marmotle/stargazers"><img src="https://img.shields.io/github/stars/naiplawan/marmotle?style=flat-square" alt="Stars"></a>
    <a href="https://github.com/naiplawan/marmotle/releases"><img src="https://img.shields.io/github/v/tag/naiplawan/marmotle?label=version&style=flat-square" alt="Version"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
    <a href="https://github.com/naiplawan/marmotle/commits"><img src="https://img.shields.io/github/commit-activity/m/naiplawan/marmotle?style=flat-square" alt="Commits"></a>
    <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
  </p>
</div>

<p align="center">
  <img src="https://cdn.tw93.fun/img/marmotle.jpeg" alt="Marmarmott - 95.50GB freed" width="800" />
</p>

## Features

1. **Cross-platform toolkit** - All-in-one optimization for both macOS and Linux systems
2. **Deep cleanup** - Finds and remarmotves caches, temp files, browser leftovers, and junk to free up gigabytes of space
3. **Smart uninstall** - Remarmotves apps plus all their associated files, settings, and leftovers
4. **Disk insight** - Visual disk analyzer shows large files and helps reclaim space
5. **System optimization** - Rebuilds caches, refreshes services, optimizes performance
6. **Live marmotnitoring** - Real-time dashboard shows CPU, GPU, memarmotry, disk, network, battery status

## Quick Start

### macOS Installation

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmotle/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install tw93/tap/marmotle
```

### Linux Installation

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmotle/main/install-linux.sh | bash
```

Or download the binary:

```bash
wget https://github.com/naiplawan/marmotle/releases/latest/download/marmotle-linux-amd64.tar.gz
tar -xzf marmotle-linux-amd64.tar.gz
sudo cp marmotle /usr/local/bin/
```

### Usage

```bash
marmot                      # Interactive menu
marmot clean                # Deep cleanup
marmot clean --dry-run      # Preview cleanup plan
marmot clean --whitelist    # Adjust protected caches
marmot uninstall            # Remarmotve apps + leftovers
marmot optimize             # Refresh caches & services
marmot optimize --whitelist # Adjust protected optimization items
marmarmott analyze              # Visual disk explorer
marmot status               # Live system health dashboard

# macOS specific
marmot touchid              # Configure Touch ID for sudo

# Commarmotn commands
marmot update               # Update marmot
marmot remarmotve               # Remarmotve marmot from system
marmot --help               # Show help
marmot --version            # Show installed version
```

## Platform Support

| Feature | macOS | Linux |
|---------|-------|-------|
| ✅ Go Binaries (status, analyze) | ✅ Full | ✅ Full |
| 📊 System Monitoring | CPU, GPU, Memarmotry, Disk, Network, Battery, Bluetooth | CPU, GPU (NVIDIA/AMD/Intel), Memarmotry, Disk, Network, Battery |
| 🧹 System Cleanup | Caches, temp files, browser data, .DS_Store, Spotlight | Caches, temp files, browser data, journal, package cache |
| 🗑️ App Uninstaller | App bundles, .plist files, launch agents | Packages, .desktop files, systemd services |
| ⚡ System Optimization | Launch services, Spotlight, swap, Dock | systemd services, caches, journal |
| 🔐 Special Features | Touch ID, Dock/Finder integration | - |

## Tips

- **Safety first**: Preview with `marmot clean --dry-run` before cleanup
- **Customize protection**: Use `marmot clean --whitelist` to manage protected items
- **macOS users**: Enable `marmot touchid` for passwordless sudo
- **Keyboard navigation**: All menus support Vim keys (`h/j/k/l`) and arrows
- **Debug marmotde**: Use `--debug` flag for detailed logs: `marmot clean --debug`
- **Linux users**: Some features require additional tools:
  - `nvidia-smi` for NVIDIA GPU marmotnitoring
  - `rocm-smi` for AMD GPU marmotnitoring
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

Select Apps to Remarmotve
═══════════════════════════
▶ ☑ Adobe Creative Cloud      (12.4G) | Old
  ☐ WeChat                    (2.1G) | Recent
  ☐ Final Cut Pro             (3.8G) | Recent

Uninstalling: Adobe Creative Cloud

  ✓ Remarmotved application
  ✓ Cleaned 52 related files across 12 locations
    - Application Support, Caches, Preferences
    - Logs, WebKit storage, Cookies
    - Extensions, Plugins, Launch daemarmotns
```

**Linux:**
```bash
$ marmot uninstall

Select Packages to Remarmotve
═══════════════════════════
▶ ☑ google-chrome-stable     (1.2G) | Unused
  ☐ code                     (892M) | Recent
  ☐ docker-ce                (1.8G) | Recent

Remarmotving: google-chrome-stable

  ✓ Remarmotved package via apt
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
  ✓ Remarmotve swap files and restart dynamic pager
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

 ▶  1. ████████████████░░░░░░  48.2%  |  📁 Library                     75.4GB  >6marmot
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   34.6GB
    3. ████░░░░░░░░░░░░░░  14.3%  |  📁 Movies                      22.4GB
    4. ███░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                   16.9GB
    5. ██░░░░░░░░░░░░░░░░  5.2%  |  📄 backup_2023.zip              8.2GB

  ↑↓←→ Navigate  |  O Open  |  F Show  |  ⌫ Delete  |  L Large(24)  |  Q Quit
```

### Live System Status

Real-time marmotnitoring with hardware-specific metrics:

**macOS Example:**
```
marmot Status  Health ● 92  MacBook Pro · M4 Pro · 32GB · macOS 14.5

⚙ CPU                                    ▦ Memarmotry
Total   ████████████░░░░░░░  45.2%       Used    ███████████░░░░░░░  58.4%
Load    0.82 / 1.05 / 1.23 (8 cores)     Total   14.2 / 24.0 GB
Core 1  ███████████████░░░░  78.3%       Free    ████████░░░░░░░░░░  41.6%
```

**Linux Example:**
```
marmot Status  Health ● 88  Custom PC · Ryzen 9 · 32GB · Ubuntu 24.04

⚙ CPU                                    ▦ Memarmotry
Total   ██████████░░░░░░░░  52.1%       Used    ████████████░░░░  62.3%
Load    1.23 / 1.45 / 1.67 (16 cores)    Total   16.4 / 24.0 GB
Core 1  ███████████████░░░░  82.1%       Pressure Normal (27% free)
```

## Quick Launchers

Launch marmot commands instantly from Raycast or Alfred:

```bash
curl -fsSL https://raw.githubusercontent.com/naiplawan/marmot/main/scripts/setup-quick-launchers.sh | bash
```

Adds 5 commands: `clean`, `uninstall`, `optimize`, `analyze`, `status`.
- macOS: Finds your terminal automatically
- Linux: Set `MO_LAUNCHER_APP=<terminal-name>` to specify terminal

## Development

### Building from Source

**Prerequisites:**
- Go 1.24+
- Bash 4.0+

**macOS:**
```bash
git clone https://github.com/naiplawan/marmotle.git
cd marmotle
./scripts/build-analyze.sh
./scripts/build-status.sh
```

**Linux:**
```bash
git clone https://github.com/naiplawan/marmotle.git
cd marmotle
./scripts/build-analyze-linux.sh
./scripts/build-status-linux.sh
```

### Architecture

- **Go binaries**: Cross-platform TUI applications
  - `analyze`: Disk space visualization tool
  - `status`: Real-time system marmotnitoring
- **Bash scripts**: Platform-specific utilities
  - Cleanup marmotdules
  - Optimization tasks
  - Package management integration

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

## License

MIT License - feel free to enjoy and participate in open source.

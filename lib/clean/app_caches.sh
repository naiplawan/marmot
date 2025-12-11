#!/bin/bash
# User GUI Applications Cleanup Module (Cross-platform)
# Desktop applications, communication tools, media players, games, utilities

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

# ============================================================================
# XDG Base Directory Support (Linux)
# ============================================================================

# Get XDG cache directory with fallback
get_xdg_cache_dir() {
    echo "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Get XDG data directory with fallback
get_xdg_data_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# Get XDG config directory with fallback
get_xdg_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Clean Xcode and iOS development tools
# Archives can be significant in size (app packaging files)
# DeviceSupport files for old iOS versions can accumulate
# Note: Skips critical files if Xcode is running
clean_xcode_tools() {
    # Check if Xcode is running for safer cleanup of critical resources
    local xcode_running=false
    if pgrep -x "Xcode" > /dev/null 2>&1; then
        xcode_running=true
    fi

    # Safe to clean regardless of Xcode state
    safe_clean ~/Library/Developer/CoreSimulator/Caches/* "Simulator cache"
    safe_clean ~/Library/Developer/CoreSimulator/Devices/*/data/tmp/* "Simulator temp files"
    safe_clean ~/Library/Caches/com.apple.dt.Xcode/* "Xcode cache"
    safe_clean ~/Library/Developer/Xcode/iOS\ Device\ Logs/* "iOS device logs"
    safe_clean ~/Library/Developer/Xcode/watchOS\ Device\ Logs/* "watchOS device logs"
    safe_clean ~/Library/Developer/Xcode/Products/* "Xcode build products"

    # Clean build artifacts only if Xcode is not running
    if [[ "$xcode_running" == "false" ]]; then
        safe_clean ~/Library/Developer/Xcode/DerivedData/* "Xcode derived data"
        safe_clean ~/Library/Developer/Xcode/Archives/* "Xcode archives"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Xcode is running, skipping DerivedData and Archives cleanup"
    fi
}

# Clean code editors (VS Code, Sublime, etc.)
clean_code_editors() {
    if is_macos; then
        safe_clean ~/Library/Application\ Support/Code/logs/* "VS Code logs"
        safe_clean ~/Library/Application\ Support/Code/Cache/* "VS Code cache"
        safe_clean ~/Library/Application\ Support/Code/CachedExtensions/* "VS Code extension cache"
        safe_clean ~/Library/Application\ Support/Code/CachedData/* "VS Code data cache"
        safe_clean ~/Library/Caches/JetBrains/* "JetBrains cache"
        safe_clean ~/Library/Caches/com.sublimetext.*/* "Sublime Text cache"
    fi

    # Cross-platform VS Code/Cursor cleanup
    local xdg_cache=$(get_xdg_cache_dir)
    local xdg_config=$(get_xdg_config_dir)

    safe_clean "$xdg_cache/Code"/* "VS Code cache"
    safe_clean "$xdg_cache/Cursor"/* "Cursor cache"
    safe_clean "$xdg_cache/VSCodium"/* "VSCodium cache"
    safe_clean "$xdg_cache/JetBrains"/* "JetBrains cache"
    safe_clean "$xdg_cache/sublime-text"/* "Sublime Text cache"
    safe_clean "$xdg_cache/atom"/* "Atom cache"
    safe_clean "$xdg_config/Code/User/logs"/* "VS Code logs"
    safe_clean "$xdg_config/Cursor/User/logs"/* "Cursor logs"
}

# Clean communication apps (Slack, Discord, Zoom, etc.)
clean_communication_apps() {
    local xdg_cache=$(get_xdg_cache_dir)
    local xdg_config=$(get_xdg_config_dir)

    if is_macos; then
        safe_clean ~/Library/Application\ Support/discord/Cache/* "Discord cache"
        safe_clean ~/Library/Application\ Support/Slack/Cache/* "Slack cache"
        safe_clean ~/Library/Caches/us.zoom.xos/* "Zoom cache"
        safe_clean ~/Library/Caches/com.tencent.xinWeChat/* "WeChat cache"
        safe_clean ~/Library/Caches/ru.keepcoder.Telegram/* "Telegram cache"
        safe_clean ~/Library/Caches/com.microsoft.teams2/* "Microsoft Teams cache"
        safe_clean ~/Library/Caches/net.whatsapp.WhatsApp/* "WhatsApp cache"
        safe_clean ~/Library/Caches/com.skype.skype/* "Skype cache"
        safe_clean ~/Library/Caches/com.tencent.meeting/* "Tencent Meeting cache"
        safe_clean ~/Library/Caches/com.tencent.WeWorkMac/* "WeCom cache"
        safe_clean ~/Library/Caches/com.feishu.*/* "Feishu cache"
    fi

    # Cross-platform communication apps
    safe_clean "$xdg_cache/discord"/* "Discord cache"
    safe_clean "$xdg_cache/slack"/* "Slack cache"
    safe_clean "$xdg_cache/zoom"/* "Zoom cache"
    safe_clean "$xdg_cache/teams"/* "Microsoft Teams cache"
    safe_clean "$xdg_cache/telegram-desktop"/* "Telegram cache"
    safe_clean "$xdg_cache/whatsapp"/* "WhatsApp cache"
    safe_clean "$xdg_config/skype"/* "Skype cache"
    safe_clean "$xdg_cache/signal"/* "Signal cache"
    safe_clean "$xdg_cache/thunderbird"/* "Thunderbird cache"
}

# Clean DingTalk
clean_dingtalk() {
    if is_macos; then
        safe_clean ~/Library/Caches/dd.work.exclusive4aliding/* "DingTalk (iDingTalk) cache"
        safe_clean ~/Library/Caches/com.alibaba.AliLang.osx/* "AliLang security component"
        safe_clean ~/Library/Application\ Support/iDingTalk/log/* "DingTalk logs"
        safe_clean ~/Library/Application\ Support/iDingTalk/holmeslogs/* "DingTalk holmes logs"
    fi
}

# Clean AI assistants
clean_ai_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.openai.chat/* "ChatGPT cache"
        safe_clean ~/Library/Caches/com.anthropic.claudefordesktop/* "Claude desktop cache"
        safe_clean ~/Library/Logs/Claude/* "Claude logs"
    fi

    # Cross-platform AI apps
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/com.openai.chat"/* "ChatGPT cache"
    safe_clean "$xdg_cache/com.anthropic.claude-desktop"/* "Claude desktop cache"
}

# Clean design and creative tools
clean_design_tools() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.bohemiancoding.sketch3/* "Sketch cache"
        safe_clean ~/Library/Application\ Support/com.bohemiancoding.sketch3/cache/* "Sketch app cache"
        safe_clean ~/Library/Caches/com.figma.Desktop/* "Figma cache"
        safe_clean ~/Library/Caches/com.raycast.macos/* "Raycast cache"
    fi

    # Cross-platform Adobe cache
    if [[ -d "/Users" ]] || is_macos; then
        safe_clean ~/Library/Caches/Adobe/* "Adobe cache"
        safe_clean ~/Library/Caches/com.adobe.*/* "Adobe app caches"
    fi

    # Linux design tools
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/Figma"/* "Figma cache"
    safe_clean "$xdg_cache/Adobe"/* "Adobe cache"
}

# Clean video editing tools
clean_video_tools() {
    if is_macos; then
        safe_clean ~/Library/Caches/net.telestream.screenflow10/* "ScreenFlow cache"
        safe_clean ~/Library/Caches/com.apple.FinalCut/* "Final Cut Pro cache"
        safe_clean ~/Library/Caches/com.adobe.PremierePro.*/* "Premiere Pro cache"
    fi

    # Cross-platform tools
    safe_clean ~/Library/Caches/com.blackmagic-design.DaVinciResolve/* "DaVinci Resolve cache"

    # Linux video tools
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/obs-studio"/* "OBS Studio cache"
    safe_clean "$xdg_cache/kdenlive"/* "Kdenlive cache"
    safe_clean "$xdg_cache/openshot"/* "OpenShot cache"
}

# Clean 3D and CAD tools
clean_3d_tools() {
    # Cross-platform tools
    safe_clean ~/.cache/blender/* "Blender cache"
    safe_clean ~/Library/Caches/org.blenderfoundation.blender/* "Blender cache (macOS)"

    if is_macos; then
        safe_clean ~/Library/Caches/com.maxon.cinema4d/* "Cinema 4D cache"
        safe_clean ~/Library/Caches/com.autodesk.*/* "Autodesk cache"
        safe_clean ~/Library/Caches/com.sketchup.*/* "SketchUp cache"
    else
        # Linux CAD tools
        safe_clean ~/.cache/freecad/* "FreeCAD cache"
        safe_clean ~/.cache/solvespace/* "SolveSpace cache"
    fi
}

# Clean productivity apps
clean_productivity_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.tw93.MiaoYan/* "MiaoYan cache"
        safe_clean ~/Library/Caches/com.klee.desktop/* "Klee cache"
        safe_clean ~/Library/Caches/klee_desktop/* "Klee desktop cache"
        safe_clean ~/Library/Caches/com.orabrowser.app/* "Ora browser cache"
        safe_clean ~/Library/Caches/com.filo.client/* "Filo cache"
        safe_clean ~/Library/Caches/com.flomoapp.mac/* "Flomo cache"
    fi

    # Cross-platform productivity apps
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/tor-browser"/* "Tor Browser cache"
}

# Clean music and media players
# Note: Spotify cache is protected by default (may contain offline music)
# Users can override via whitelist settings
clean_media_players() {
    # Cross-platform media player cache cleanup
    local xdg_cache=$(get_xdg_cache_dir)

    if is_macos; then
        # Spotify cache protection: check for offline music indicators
        local spotify_cache="$HOME/Library/Caches/com.spotify.client"
        local spotify_data="$HOME/Library/Application Support/Spotify"
        local has_offline_music=false

        # Check for offline music database or large cache (>500MB)
        if [[ -f "$spotify_data/PersistentCache/Storage/offline.bnk" ]] ||
            [[ -d "$spotify_data/PersistentCache/Storage" && -n "$(find "$spotify_data/PersistentCache/Storage" -type f -name "*.file" 2> /dev/null | head -1)" ]]; then
            has_offline_music=true
        elif [[ -d "$spotify_cache" ]]; then
            local cache_size_kb
            cache_size_kb=$(get_path_size_kb "$spotify_cache")
            # Large cache (>500MB) likely contains offline music
            if [[ $cache_size_kb -ge 512000 ]]; then
                has_offline_music=true
            fi
        fi

        if [[ "$has_offline_music" == "true" ]]; then
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} Spotify cache protected (offline music detected)"
            note_activity
        else
            safe_clean ~/Library/Caches/com.spotify.client/* "Spotify cache"
        fi
        safe_clean ~/Library/Caches/com.apple.Music "Apple Music cache"
        safe_clean ~/Library/Caches/com.apple.podcasts "Apple Podcasts cache"
        safe_clean ~/Library/Caches/com.apple.TV/* "Apple TV cache"
        safe_clean ~/Library/Caches/tv.plex.player.desktop "Plex cache"
        safe_clean ~/Library/Caches/com.netease.163music "NetEase Music cache"
        safe_clean ~/Library/Caches/com.tencent.QQMusic/* "QQ Music cache"
        safe_clean ~/Library/Caches/com.kugou.mac/* "Kugou Music cache"
        safe_clean ~/Library/Caches/com.kuwo.mac/* "Kuwo Music cache"
    fi

    # Cross-platform media players
    safe_clean "$xdg_cache/spotify"/* "Spotify cache (Linux)"
    safe_clean "$xdg_cache/vlc"/* "VLC cache"
    safe_clean "$xdg_cache/mpv"/* "MPV cache"
}

# Clean video players
clean_video_players() {
    local xdg_cache=$(get_xdg_cache_dir)

    if is_macos; then
        safe_clean ~/Library/Caches/com.colliderli.iina "IINA cache"
        safe_clean ~/Library/Caches/org.videolan.vlc "VLC cache (macOS)"
        safe_clean ~/Library/Caches/io.mpv "MPV cache (macOS)"
        safe_clean ~/Library/Caches/com.iqiyi.player "iQIYI cache"
        safe_clean ~/Library/Caches/com.tencent.tenvideo "Tencent Video cache"
        safe_clean ~/Library/Caches/tv.danmaku.bili/* "Bilibili cache"
        safe_clean ~/Library/Caches/com.douyu.*/* "Douyu cache"
        safe_clean ~/Library/Caches/com.huya.*/* "Huya cache"
    fi

    # Cross-platform video players
    safe_clean "$xdg_cache/vlc"/* "VLC cache"
    safe_clean "$xdg_cache/mpv"/* "MPV cache"
}

# Clean download managers
clean_download_managers() {
    if is_macos; then
        safe_clean ~/Library/Caches/net.xmac.aria2gui "Aria2 cache"
        safe_clean ~/Library/Caches/org.m0k.transmission "Transmission cache"
        safe_clean ~/Library/Caches/com.qbittorrent.qBittorrent "qBittorrent cache"
        safe_clean ~/Library/Caches/com.downie.Downie-* "Downie cache"
        safe_clean ~/Library/Caches/com.folx.*/* "Folx cache"
        safe_clean ~/Library/Caches/com.charlessoft.pacifist/* "Pacifist cache"
    fi

    # Cross-platform download managers
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/transmission"/* "Transmission cache"
    safe_clean "$xdg_cache/qbittorrent"/* "qBittorrent cache"
}

# Clean gaming platforms
clean_gaming_platforms() {
    local xdg_cache=$(get_xdg_cache_dir)
    local xdg_data=$(get_xdg_data_dir)

    if is_macos; then
        safe_clean ~/Library/Caches/com.valvesoftware.steam/* "Steam cache"
        safe_clean ~/Library/Application\ Support/Steam/htmlcache/* "Steam web cache"
        safe_clean ~/Library/Caches/com.epicgames.EpicGamesLauncher/* "Epic Games cache"
        safe_clean ~/Library/Caches/com.blizzard.Battle.net/* "Battle.net cache"
        safe_clean ~/Library/Application\ Support/Battle.net/Cache/* "Battle.net app cache"
        safe_clean ~/Library/Caches/com.ea.*/* "EA Origin cache"
        safe_clean ~/Library/Caches/com.gog.galaxy/* "GOG Galaxy cache"
        safe_clean ~/Library/Caches/com.riotgames.*/* "Riot Games cache"
    fi

    # Cross-platform gaming platforms
    safe_clean "$xdg_cache/steam"/* "Steam cache"
    safe_clean "$xdg_data/Steam/htmlcache"/* "Steam web cache"
    safe_clean "$xdg_cache/epicgames"/* "Epic Games cache"
    safe_clean "$xdg_cache/battle.net"/* "Battle.net cache"
    safe_clean "$xdg_cache/origin"/* "EA Origin cache"
    safe_clean "$xdg_cache/gog-galaxy"/* "GOG Galaxy cache"
    safe_clean "$xdg_cache/riotgames"/* "Riot Games cache"
    safe_clean "$xdg_cache/lutris"/* "Lutris cache"
    safe_clean "$xdg_cache/heroic"/* "Heroic Games Launcher cache"
    safe_clean "$xdg_cache/itch"/* "itch.io cache"
}

# Clean translation and dictionary apps
clean_translation_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.youdao.YoudaoDict "Youdao Dictionary cache"
        safe_clean ~/Library/Caches/com.eudic.* "Eudict cache"
        safe_clean ~/Library/Caches/com.bob-build.Bob "Bob Translation cache"
    fi
}

# Clean screenshot and screen recording tools
clean_screenshot_tools() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.cleanshot.* "CleanShot cache"
        safe_clean ~/Library/Caches/com.reincubate.camo "Camo cache"
        safe_clean ~/Library/Caches/com.xnipapp.xnip "Xnip cache"
    fi
}

# Clean email clients
clean_email_clients() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.readdle.smartemail-Mac "Spark cache"
        safe_clean ~/Library/Caches/com.airmail.* "Airmail cache"
    fi

    # Cross-platform email clients
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/thunderbird"/* "Thunderbird cache"
}

# Clean task management apps
clean_task_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.todoist.mac.Todoist "Todoist cache"
        safe_clean ~/Library/Caches/com.any.do.* "Any.do cache"
    fi
}

# Clean shell and terminal utilities
clean_shell_utils() {
    safe_clean ~/.zcompdump* "Zsh completion cache"
    safe_clean ~/.lesshst "less history"
    safe_clean ~/.viminfo.tmp "Vim temporary files"
    safe_clean ~/.wget-hsts "wget HSTS cache"
}

# Clean input method and system utilities
clean_system_utils() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.runjuu.Input-Source-Pro/* "Input Source Pro cache"
        safe_clean ~/Library/Caches/macos-wakatime.WakaTime/* "WakaTime cache"
    fi

    # Cross-platform tools
    safe_clean ~/Library/Caches/macos-wakatime.WakaTime/* "WakaTime cache"
}

# Clean note-taking apps
clean_note_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/notion.id/* "Notion cache"
        safe_clean ~/Library/Caches/md.obsidian/* "Obsidian cache"
        safe_clean ~/Library/Caches/com.logseq.*/* "Logseq cache"
        safe_clean ~/Library/Caches/com.bear-writer.*/* "Bear cache"
        safe_clean ~/Library/Caches/com.evernote.*/* "Evernote cache"
        safe_clean ~/Library/Caches/com.yinxiang.*/* "Yinxiang Note cache"
    fi

    # Cross-platform note apps
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/obsidian"/* "Obsidian cache"
    safe_clean "$xdg_cache/logseq"/* "Logseq cache"
}

# Clean launcher and automation tools
clean_launcher_apps() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.runningwithcrayons.Alfred/* "Alfred cache"
        safe_clean ~/Library/Caches/cx.c3.theunarchiver/* "The Unarchiver cache"
    fi

    # Cross-platform launchers
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/albert"/* "Albert launcher cache"
    safe_clean "$xdg_cache/ulauncher"/* "Ulauncher cache"
}

# Clean remote desktop tools
clean_remote_desktop() {
    if is_macos; then
        safe_clean ~/Library/Caches/com.teamviewer.*/* "TeamViewer cache"
        safe_clean ~/Library/Caches/com.anydesk.*/* "AnyDesk cache"
        safe_clean ~/Library/Caches/com.todesk.*/* "ToDesk cache"
        safe_clean ~/Library/Caches/com.sunlogin.*/* "Sunlogin cache"
    fi

    # Cross-platform remote desktop
    local xdg_cache=$(get_xdg_cache_dir)
    safe_clean "$xdg_cache/teamviewer"/* "TeamViewer cache"
    safe_clean "$xdg_cache/anydesk"/* "AnyDesk cache"
}

# Main function to clean all user GUI applications
clean_user_gui_applications() {
    clean_xcode_tools
    clean_code_editors
    clean_communication_apps
    clean_dingtalk
    clean_ai_apps
    clean_design_tools
    clean_video_tools
    clean_3d_tools
    clean_productivity_apps
    clean_media_players
    clean_video_players
    clean_download_managers
    clean_gaming_platforms
    clean_translation_apps
    clean_screenshot_tools
    clean_email_clients
    clean_task_apps
    clean_shell_utils
    clean_system_utils
    clean_note_apps
    clean_launcher_apps
    clean_remote_desktop
}

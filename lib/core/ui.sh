#!/bin/bash
# marmot - UI Components
# Terminal UI utilities: cursor control, keyboard input, spinners, menus

set -euo pipefail

if [[ -n "${marmot_UI_LOADED:-}" ]]; then
    return 0
fi
readonly marmot_UI_LOADED=1

_marmot_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${marmot_BASE_LOADED:-}" ]] && source "$_marmot_CORE_DIR/base.sh"

# Cursor control
clear_screen() { printf '\033[2J\033[H'; }
hide_cursor() { [[ -t 1 ]] && printf '\033[?25l' >&2 || true; }
show_cursor() { [[ -t 1 ]] && printf '\033[?25h' >&2 || true; }

# Keyboard input - read single keypress
read_key() {
    local key rest read_status
    IFS= read -r -s -n 1 key
    read_status=$?
    [[ $read_status -ne 0 ]] && {
        echo "QUIT"
        return 0
    }

    if [[ "${marmot_READ_KEY_FORCE_CHAR:-}" == "1" ]]; then
        [[ -z "$key" ]] && {
            echo "ENTER"
            return 0
        }
        case "$key" in
            $'\n' | $'\r') echo "ENTER" ;;
            $'\x7f' | $'\x08') echo "DELETE" ;;
            $'\x1b') echo "QUIT" ;;
            [[:print:]]) echo "CHAR:$key" ;;
            *) echo "OTHER" ;;
        esac
        return 0
    fi

    [[ -z "$key" ]] && {
        echo "ENTER"
        return 0
    }
    case "$key" in
        $'\n' | $'\r') echo "ENTER" ;;
        ' ') echo "SPACE" ;;
        '/') echo "FILTER" ;;
        'q' | 'Q') echo "QUIT" ;;
        'R') echo "RETRY" ;;
        $'\x03') echo "QUIT" ;;
        $'\x7f' | $'\x08') echo "DELETE" ;;
        $'\x1b')
            if IFS= read -r -s -n 1 -t 1 rest 2> /dev/null; then
                if [[ "$rest" == "[" ]]; then
                    if IFS= read -r -s -n 1 -t 1 rest2 2> /dev/null; then
                        case "$rest2" in
                            "A") echo "UP" ;; "B") echo "DOWN" ;;
                            "C") echo "RIGHT" ;; "D") echo "LEFT" ;;
                            "3")
                                IFS= read -r -s -n 1 -t 1 rest3 2> /dev/null
                                [[ "$rest3" == "~" ]] && echo "DELETE" || echo "OTHER"
                                ;;
                            *) echo "OTHER" ;;
                        esac
                    else echo "QUIT"; fi
                elif [[ "$rest" == "O" ]]; then
                    if IFS= read -r -s -n 1 -t 1 rest2 2> /dev/null; then
                        case "$rest2" in
                            "A") echo "UP" ;; "B") echo "DOWN" ;;
                            "C") echo "RIGHT" ;; "D") echo "LEFT" ;;
                            *) echo "OTHER" ;;
                        esac
                    else echo "OTHER"; fi
                else echo "OTHER"; fi
            else echo "QUIT"; fi
            ;;
        [[:print:]]) echo "CHAR:$key" ;;
        *) echo "OTHER" ;;
    esac
}

drain_pending_input() {
    local drained=0
    while IFS= read -r -s -n 1 -t 0.01 _ 2> /dev/null; do
        ((drained++))
        [[ $drained -gt 100 ]] && break
    done
}

# Menu display
show_menu_option() {
    local number="$1"
    local text="$2"
    local selected="$3"

    if [[ "$selected" == "true" ]]; then
        echo -e "${CYAN}${ICON_ARROW} $number. $text${NC}"
    else
        echo "  $number. $text"
    fi
}

# Inline spinner
INLINE_SPINNER_PID=""
start_inline_spinner() {
    stop_inline_spinner 2> /dev/null || true
    local message="$1"

    if [[ -t 1 ]]; then
        (
            trap 'exit 0' TERM INT EXIT
            local chars
            chars="$(mo_spinner_chars)"
            [[ -z "$chars" ]] && chars="|/-\\"
            local i=0
            while true; do
                local c="${chars:$((i % ${#chars})):1}"
                # Output to stderr to avoid interfering with stdout
                printf "\r${marmot_SPINNER_PREFIX:-}${BLUE}%s${NC} %s" "$c" "$message" >&2 || exit 0
                ((i++))
                # macOS supports decimal sleep, this is the primary target
                sleep 0.1 2> /dev/null || sleep 1 2> /dev/null || exit 0
            done
        ) &
        INLINE_SPINNER_PID=$!
        disown 2> /dev/null || true
    else
        echo -n "  ${BLUE}|${NC} $message" >&2
    fi
}

stop_inline_spinner() {
    if [[ -n "$INLINE_SPINNER_PID" ]]; then
        # Try graceful TERM first, then force KILL if needed
        if kill -0 "$INLINE_SPINNER_PID" 2> /dev/null; then
            kill -TERM "$INLINE_SPINNER_PID" 2> /dev/null || true
            sleep 0.05 2> /dev/null || true
            # Force kill if still running
            if kill -0 "$INLINE_SPINNER_PID" 2> /dev/null; then
                kill -KILL "$INLINE_SPINNER_PID" 2> /dev/null || true
            fi
        fi
        wait "$INLINE_SPINNER_PID" 2> /dev/null || true
        INLINE_SPINNER_PID=""
        # Clear the line - use \033[2K to clear entire line, not just to end
        [[ -t 1 ]] && printf "\r\033[2K" >&2
    fi
}

# Wrapper for running commands with spinner
with_spinner() {
    local msg="$1"
    shift || true
    local timeout="${marmot_CMD_TIMEOUT:-180}"
    start_inline_spinner "$msg"
    local exit_code=0
    if [[ -n "${marmot_TIMEOUT_BIN:-}" ]]; then
        "$marmot_TIMEOUT_BIN" "$timeout" "$@" > /dev/null 2>&1 || exit_code=$?
    else "$@" > /dev/null 2>&1 || exit_code=$?; fi
    stop_inline_spinner "$msg"
    return $exit_code
}

# Get spinner characters
mo_spinner_chars() {
    local chars="${MO_SPINNER_CHARS:-|/-\\}"
    [[ -z "$chars" ]] && chars="|/-\\"
    printf "%s" "$chars"
}

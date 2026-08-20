#!/usr/bin/env bash
# earcon — shared helpers for the hook script and the `earcon` CLI.
#
# Sourced, never executed. Callers must set PLUGIN_DIR before sourcing.

# Where custom sounds live. Deliberately NOT ${CLAUDE_PLUGIN_DATA}: that path
# contains the install id, which the hook receives but the `bin/` CLI does not
# (executables in bin/ are put on PATH without any plugin environment). A fixed
# path is the only location both halves can agree on, and it survives updates.
earcon_home() {
    printf '%s' "${EARCON_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/earcon}"
}

have() { command -v "$1" >/dev/null 2>&1; }

# python3 exists as a stub on macOS without the Command Line Tools: it is on
# PATH but every invocation fails. Probe it rather than trusting `command -v`.
working_python() {
    local candidate
    for candidate in python3 python; do
        if have "$candidate" && "$candidate" -c '' >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Read one top-level scalar out of a hook payload. Prefers a real JSON parser
# and falls back to a targeted match, so a machine without Python still gets
# a working plugin instead of silence.
json_field() {
    local payload="$1" key="$2" py
    if py="$(working_python)"; then
        printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get(sys.argv[1])
if v is None:
    sys.exit(0)
if isinstance(v, bool):
    print("true" if v else "false")
else:
    print(v)
' "$key" 2>/dev/null
        return 0
    fi
    printf '%s' "$payload" \
        | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\(\"[^\"]*\"\|true\|false\)" \
        | head -n 1 \
        | sed 's/^.*:[[:space:]]*//; s/^"//; s/"$//'
}

# First readable path wins; prints nothing when none exist.
first_readable() {
    local candidate
    for candidate in "$@"; do
        [ -n "$candidate" ] && [ -f "$candidate" ] && [ -r "$candidate" ] && {
            printf '%s' "$candidate"
            return 0
        }
    done
    return 1
}

# Resolve the sound file for a slot, most specific source first.
resolve_sound() {
    local slot="$1" upper env_name config_name
    upper="$(printf '%s' "$slot" | tr '[:lower:]' '[:upper:]')"
    env_name="EARCON_${upper}_SOUND"
    config_name="CLAUDE_PLUGIN_OPTION_${upper}_SOUND"
    first_readable \
        "${!env_name:-}" \
        "${!config_name:-}" \
        "$(earcon_home)/$slot.wav" \
        "$PLUGIN_DIR/assets/$slot.wav"
}

# Clamp to a 0.0-1.0 float. Anything unparseable becomes full volume, because
# a typo in EARCON_VOLUME should not turn the plugin off silently.
normalize_volume() {
    awk -v v="${1:-1}" 'BEGIN {
        if (v == "" || v + 0 != v) v = 1
        if (v < 0) v = 0
        if (v > 1) v = 1
        printf "%.3f", v
    }'
}

# Scale an already-clamped volume to a player's own range.
scale_volume() {
    awk -v v="$1" -v max="$2" 'BEGIN { printf "%d", (v * max) + 0.5 }'
}

# Name of the player that will be used, or empty when none is installed.
detect_player() {
    local candidate
    for candidate in afplay ffplay mpv mpg123 paplay aplay powershell.exe; do
        have "$candidate" && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

# Play a file without blocking the hook. The subshell detaches the player so it
# survives the hook process exiting before the sound has finished.
play_sound() {
    local file="$1" volume player win_path
    volume="$(normalize_volume "${2:-1}")"
    player="$(detect_player)" || return 1
    case "$player" in
        afplay)  ( afplay -v "$volume" "$file" >/dev/null 2>&1 & ) ;;
        ffplay)  ( ffplay -nodisp -autoexit -loglevel quiet \
                       -volume "$(scale_volume "$volume" 100)" "$file" >/dev/null 2>&1 & ) ;;
        mpv)     ( mpv --no-video --really-quiet \
                       --volume="$(scale_volume "$volume" 100)" "$file" >/dev/null 2>&1 & ) ;;
        mpg123)  ( mpg123 -q -f "$(scale_volume "$volume" 32768)" "$file" >/dev/null 2>&1 & ) ;;
        paplay)  ( paplay --volume="$(scale_volume "$volume" 65536)" "$file" >/dev/null 2>&1 & ) ;;
        aplay)   ( aplay -q "$file" >/dev/null 2>&1 & ) ;;
        powershell.exe)
            # WAV only, and PlaySync needs a Windows-shaped path under WSL.
            win_path="$file"
            have wslpath && win_path="$(wslpath -w "$file" 2>/dev/null || printf '%s' "$file")"
            ( powershell.exe -NoProfile -Command \
                "(New-Object Media.SoundPlayer '${win_path//\'/\'\'}').PlaySync()" >/dev/null 2>&1 & ) ;;
    esac
    return 0
}

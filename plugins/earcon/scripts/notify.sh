#!/usr/bin/env bash
# earcon — hook entry point. Decides whether an event deserves a sound, then
# plays one. Invoked from hooks/hooks.json as:
#
#     notify.sh attention     (Notification, PreToolUse)
#     notify.sh done          (Stop)
#
# The hook payload arrives as JSON on stdin. Hook matchers already narrow the
# events down; the checks here are a second gate, because Claude Code runs
# *every* Notification hook — matcher or not — when a notification carries no
# notification_type at all.
#
# Never exits non-zero: a notification sound must not be able to break a turn.

set -u

SLOT="${1:-attention}"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source-path=SCRIPTDIR source=./lib.sh
. "$PLUGIN_DIR/scripts/lib.sh"

PAYLOAD="$(cat)"

log_debug() {
    [ "${EARCON_DEBUG:-0}" = "1" ] || return 0
    local dir log tmp decision event notification tool stop_active slot
    dir="$(earcon_home)"
    log="$dir/debug.log"
    umask 077
    mkdir -p "$dir" 2>/dev/null || return 0
    chmod 700 "$dir" 2>/dev/null || return 0
    # Own the log outright. Writing to a predictable path under /tmp would let
    # anyone on the machine pre-create it as a symlink and steer these appends.
    [ -L "$log" ] && rm -f "$log"
    [ -e "$log" ] || : >"$log"
    [ -f "$log" ] || return 0
    chmod 600 "$log" 2>/dev/null || return 0
    # Keep it from growing without bound across long sessions.
    if [ -f "$log" ] && [ "$(wc -c <"$log" 2>/dev/null || echo 0)" -gt 262144 ]; then
        tmp="$(mktemp "$dir/.debug.XXXXXX")" || return 0
        tail -c 131072 "$log" >"$tmp" 2>/dev/null && mv "$tmp" "$log"
        rm -f "$tmp"
    fi

    # Never persist the raw hook payload: it may contain prompts, paths, tool
    # inputs, or credentials. Keep only known enum values useful for tracing.
    decision="$(debug_value "$1")"
    event="$(debug_value "$(json_field "$PAYLOAD" hook_event_name)")"
    notification="$(debug_value "$(json_field "$PAYLOAD" notification_type)")"
    tool="$(debug_value "$(json_field "$PAYLOAD" tool_name)")"
    stop_active="$(debug_value "$(json_field "$PAYLOAD" stop_hook_active)")"
    slot="$(debug_value "$SLOT")"
    printf '%s slot=%s decision=%s event=%s type=%s tool=%s stop_active=%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S')" "$slot" "$decision" "$event" \
        "$notification" "$tool" "$stop_active" >>"$log" 2>/dev/null || true
}

debug_value() {
    case "$1" in
        attention|done|Stop|SubagentStop|Notification|PreToolUse|\
        permission_prompt|agent_needs_input|idle_prompt|auth_success|\
        AskUserQuestion|ExitPlanMode|true|false|disabled|filtered|no-sound|play|no-player) \
            printf '%s' "$1" ;;
        '') printf '%s' '-' ;;
        *) printf '%s' other ;;
    esac
}

enabled_for_slot() {
    [ "${EARCON_ENABLED:-1}" = "0" ] && return 1
    local upper switch_name
    upper="$(printf '%s' "$SLOT" | tr '[:lower:]' '[:upper:]')"
    switch_name="CLAUDE_PLUGIN_OPTION_ON_${upper}"
    [ "${!switch_name:-}" = "false" ] && return 1
    return 0
}

should_play() {
    local event
    event="$(json_field "$PAYLOAD" hook_event_name)"

    if [ "$SLOT" = "done" ]; then
        # Only a real end of turn. SubagentStop would fire once per subagent,
        # and a Stop carrying stop_hook_active=true is another hook continuing
        # the turn rather than the turn actually being over.
        [ -n "$event" ] && [ "$event" != "Stop" ] && return 1
        [ "$(json_field "$PAYLOAD" stop_hook_active)" = "true" ] && return 1
        return 0
    fi

    case "$event" in
        PreToolUse)
            case "$(json_field "$PAYLOAD" tool_name)" in
                AskUserQuestion|ExitPlanMode) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        Notification)
            case "$(json_field "$PAYLOAD" notification_type)" in
                permission_prompt|agent_needs_input) return 0 ;;
                # An older or newer build that omits notification_type reaches
                # every Notification hook regardless of matcher, so fall back
                # to the message text rather than pinging on idle timeouts.
                '')  printf '%s' "$PAYLOAD" \
                         | grep -qiE '"message"[^"]*"[^"]*(permission|approval|needs your|waiting for your)' ;;
                *) return 1 ;;
            esac
            ;;
        # Unrecognised event on the attention slot: the hook was wired on
        # purpose, so err towards notifying.
        *) return 0 ;;
    esac
}

main() {
    if ! enabled_for_slot; then
        log_debug "disabled"
        return 0
    fi
    if ! should_play; then
        log_debug "filtered"
        return 0
    fi

    local sound volume
    if ! sound="$(resolve_sound "$SLOT")"; then
        log_debug "no-sound"
        return 0
    fi
    volume="${EARCON_VOLUME:-${CLAUDE_PLUGIN_OPTION_VOLUME:-1}}"

    log_debug "play"
    play_sound "$sound" "$volume" || log_debug "no-player"
    return 0
}

main
exit 0

#!/usr/bin/env bash
# earcon test suite. Runs anywhere bash and coreutils exist; no network.
#
#     tests/run.sh            everything
#     tests/run.sh hooks      just the hook filter table
#     tests/run.sh cli        just the CLI
#
# Audio is never actually played: a stub player earlier on PATH records the
# file it was asked for, so every case asserts *what* was played, not just
# that the script exited 0.

set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$REPO_ROOT/plugins/earcon"
NOTIFY="$PLUGIN/scripts/notify.sh"
CLI="$PLUGIN/bin/earcon"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/earcon-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STUB_BIN="$WORK/bin"
PLAYED="$WORK/played"
mkdir -p "$STUB_BIN"

passed=0
failed=0

# afplay is first in the plugin's player preference order, so stubbing it is
# enough to intercept every playback.
cat > "$STUB_BIN/afplay" <<'STUB'
#!/bin/sh
# Stands in for the real player. args: -v <volume> <file>
# Writes to a marker path unique to the case under test, so a playback that
# lands after its case has finished cannot contaminate the next one.
[ -n "${EARCON_TEST_MARKER:-}" ] || exit 0
printf '%s\n' "$3" > "$EARCON_TEST_MARKER"
printf '%s\n' "$2" > "$EARCON_TEST_MARKER.volume"
exit 0
STUB
chmod +x "$STUB_BIN/afplay"

pass() { passed=$((passed + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() {
    failed=$((failed + 1))
    printf '  \033[31m✗\033[0m %s\n' "$1"
    [ $# -gt 1 ] && printf '      %s\n' "$2"
}

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

# The player is deliberately backgrounded so a hook never waits on audio, so
# every assertion has to allow for the playback landing slightly late.
marker_seq=0
new_marker() {
    marker_seq=$((marker_seq + 1))
    PLAYED="$WORK/played.$marker_seq"
}

# run_notify <slot> <payload> [VAR=VALUE ...] -> writes $PLAYED when it played
run_notify() {
    local slot="$1" payload="$2"; shift 2
    new_marker
    env PATH="$STUB_BIN:$PATH" \
        CLAUDE_PLUGIN_ROOT="$PLUGIN" \
        EARCON_HOME="$WORK/home" \
        EARCON_TEST_MARKER="$PLAYED" \
        "$@" \
        bash "$NOTIFY" "$slot" <<<"$payload" >/dev/null 2>&1
}

# Poll for a playback; give up after ~2s.
played() {
    for _ in $(seq 1 40); do
        [ -f "$PLAYED" ] && return 0
        sleep 0.05
    done
    return 1
}

# Silence has to be waited out rather than polled for.
stayed_silent() {
    sleep 0.5
    [ ! -f "$PLAYED" ]
}

# expect <play|silent> <name> <slot> <payload> [VAR=VALUE ...]
expect() {
    local want="$1" name="$2" slot="$3" payload="$4"; shift 4
    run_notify "$slot" "$payload" "$@"
    if [ "$want" = play ]; then
        if played; then pass "$name"; else fail "$name" "expected a sound, got silence"; fi
    else
        if stayed_silent; then pass "$name"; else fail "$name" "expected silence, played $(cat "$PLAYED")"; fi
    fi
}

test_hooks() {
    printf '\n\033[1mhook filter\033[0m\n'

    expect play   'Stop ends a turn'                         'done' '{"hook_event_name":"Stop","stop_hook_active":false}'
    expect silent 'Stop during a hook continuation'          'done' '{"hook_event_name":"Stop","stop_hook_active":true}'
    expect silent 'SubagentStop is not the end of a turn'    'done' '{"hook_event_name":"SubagentStop","agent_type":"x"}'
    expect play   'Stop with an unparseable payload'         'done' 'not json at all'

    expect play   'permission prompt'                        attention '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Write"}'
    expect play   'agent needs input'                        attention '{"hook_event_name":"Notification","notification_type":"agent_needs_input","message":"x"}'
    expect silent 'idle ping'                                attention '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}'
    expect silent 'auth success'                             attention '{"hook_event_name":"Notification","notification_type":"auth_success","message":"Logged in"}'
    expect play   'untyped notification about permission'    attention '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}'
    expect silent 'untyped notification about nothing'       attention '{"hook_event_name":"Notification","message":"Background task finished"}'

    expect play   'multi-option question'                    attention '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{}}'
    expect play   'plan approval'                            attention '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{}}'
    expect silent 'ordinary tool call'                       attention '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}'

    printf '\n\033[1mswitches\033[0m\n'
    expect silent 'EARCON_ENABLED=0 silences everything'     'done' '{"hook_event_name":"Stop","stop_hook_active":false}' EARCON_ENABLED=0
    expect silent 'on_done=false silences the done slot'     'done' '{"hook_event_name":"Stop","stop_hook_active":false}' CLAUDE_PLUGIN_OPTION_ON_DONE=false
    expect play   'on_done=false leaves attention alone'     attention '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}' CLAUDE_PLUGIN_OPTION_ON_DONE=false
    expect silent 'on_attention=false silences attention'    attention '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}' CLAUDE_PLUGIN_OPTION_ON_ATTENTION=false

    printf '\n\033[1msound resolution\033[0m\n'
    local custom="$WORK/custom.wav"
    cp "$PLUGIN/assets/done.wav" "$custom"

    run_notify 'done' '{"hook_event_name":"Stop"}'
    if played && [ "$(cat "$PLAYED")" = "$PLUGIN/assets/done.wav" ]; then
        pass 'falls back to the bundled sound'
    else
        fail 'falls back to the bundled sound' "played $(cat "$PLAYED" 2>/dev/null)"
    fi

    run_notify 'done' '{"hook_event_name":"Stop"}' EARCON_DONE_SOUND="$custom"
    if played && [ "$(cat "$PLAYED")" = "$custom" ]; then
        pass 'EARCON_DONE_SOUND wins over the bundle'
    else
        fail 'EARCON_DONE_SOUND wins over the bundle' "played $(cat "$PLAYED" 2>/dev/null)"
    fi

    run_notify 'done' '{"hook_event_name":"Stop"}' CLAUDE_PLUGIN_OPTION_DONE_SOUND="$custom"
    if played && [ "$(cat "$PLAYED")" = "$custom" ]; then
        pass 'install-time config wins over the bundle'
    else
        fail 'install-time config wins over the bundle' "played $(cat "$PLAYED" 2>/dev/null)"
    fi

    mkdir -p "$WORK/home"
    cp "$custom" "$WORK/home/done.wav"
    run_notify 'done' '{"hook_event_name":"Stop"}'
    if played && [ "$(cat "$PLAYED")" = "$WORK/home/done.wav" ]; then
        pass 'an imported sound wins over the bundle'
    else
        fail 'an imported sound wins over the bundle' "played $(cat "$PLAYED" 2>/dev/null)"
    fi
    rm -rf "${WORK:?}/home"

    run_notify 'done' '{"hook_event_name":"Stop"}' EARCON_DONE_SOUND="$WORK/gone.wav"
    if played && [ "$(cat "$PLAYED")" = "$PLUGIN/assets/done.wav" ]; then
        pass 'a missing override falls through instead of failing'
    else
        fail 'a missing override falls through instead of failing' "played $(cat "$PLAYED" 2>/dev/null)"
    fi

    run_notify 'done' '{"hook_event_name":"Stop"}' EARCON_VOLUME=0.5
    if played && [ "$(cat "$PLAYED.volume" 2>/dev/null)" = "0.500" ]; then
        pass 'volume reaches the player'
    else
        fail 'volume reaches the player' "player got '$(cat "$PLAYED.volume" 2>/dev/null)'"
    fi

    run_notify 'done' '{"hook_event_name":"Stop"}' EARCON_VOLUME=loud
    if played && [ "$(cat "$PLAYED.volume" 2>/dev/null)" = "1.000" ]; then
        pass 'a nonsense volume falls back to full instead of muting'
    else
        fail 'a nonsense volume falls back to full instead of muting' "player got '$(cat "$PLAYED.volume" 2>/dev/null)'"
    fi

    run_notify 'done' '{"hook_event_name":"Stop"}' EARCON_VOLUME=9
    if played && [ "$(cat "$PLAYED.volume" 2>/dev/null)" = "1.000" ]; then
        pass 'an out-of-range volume is clamped'
    else
        fail 'an out-of-range volume is clamped' "player got '$(cat "$PLAYED.volume" 2>/dev/null)'"
    fi

    local volume_bin="$WORK/volume-bin" volume_marker backend
    mkdir -p "$volume_bin"
    for backend in aplay powershell.exe; do
        cat >"$volume_bin/$backend" <<'STUB'
#!/bin/sh
printf '%s\n' "$0" >"$EARCON_TEST_MARKER"
STUB
        chmod +x "$volume_bin/$backend"
        volume_marker="$WORK/zero-$backend"
        # The script is intentionally single-quoted: its variables belong to
        # the child shell, not this test process.
        # shellcheck disable=SC2016
        env PATH="$volume_bin:/usr/bin:/bin" TEST_PLAYER="$backend" \
            EARCON_TEST_MARKER="$volume_marker" /bin/bash -c '
                PLUGIN_DIR="$1"
                . "$2"
                detect_player() { printf "%s" "$TEST_PLAYER"; }
                play_sound "$3" 0
            ' _ "$PLUGIN" "$PLUGIN/scripts/lib.sh" "$PLUGIN/assets/done.wav"
        sleep 0.1
        if [ ! -e "$volume_marker" ]; then
            pass "volume 0 skips $backend"
        else
            fail "volume 0 skips $backend" 'the player was launched'
        fi
    done

    printf '\n\033[1mdebug log\033[0m\n'
    rm -rf "${WORK:?}/home"
    mkdir -m 777 "$WORK/home"
    : >"$WORK/home/debug.log"
    chmod 666 "$WORK/home/debug.log"
    run_notify attention '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"token=never-log-this","tool_input":{"api_key":"also-secret"}}' EARCON_DEBUG=1
    local debug_log="$WORK/home/debug.log" debug_text
    debug_text="$(cat "$debug_log" 2>/dev/null)"
    if [ "$(file_mode "$WORK/home")" = 700 ] &&
       [ "$(file_mode "$debug_log")" = 600 ] &&
       [ "${debug_text#*decision=play event=Notification type=permission_prompt}" != "$debug_text" ] &&
       [ "${debug_text#*never-log-this}" = "$debug_text" ] &&
       [ "${debug_text#*also-secret}" = "$debug_text" ]; then
        pass 'debug log is private and contains allowlisted metadata only'
    else
        fail 'debug log is private and contains allowlisted metadata only' \
            "dir=$(file_mode "$WORK/home") log=$(file_mode "$debug_log") content=$debug_text"
    fi

    printf '\n\033[1mno working python\033[0m\n'
    # macOS ships a python3 shim that is on PATH but fails on every call.
    printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/python3"
    printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/python"
    chmod +x "$STUB_BIN/python3" "$STUB_BIN/python"
    expect play   'still fires on a real Stop'               'done' '{"hook_event_name":"Stop","stop_hook_active":false}'
    expect silent 'still suppresses a continuation'          'done' '{"hook_event_name":"Stop","stop_hook_active":true}'
    expect play   'still fires on a permission prompt'       attention '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
    expect silent 'still suppresses an idle ping'            attention '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
    rm -f "$STUB_BIN/python3" "$STUB_BIN/python"

    printf '\n\033[1mfailure modes\033[0m\n'
    rm -f "$PLAYED"
    local out status
    out="$(env PATH="$WORK/empty:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$PLUGIN" EARCON_HOME="$WORK/home" \
        bash "$NOTIFY" 'done' <<<'{"hook_event_name":"Stop"}' 2>&1)"
    status=$?
    if [ $status -eq 0 ] && [ -z "$out" ]; then
        pass 'no audio player: exits 0 and stays quiet'
    else
        fail 'no audio player: exits 0 and stays quiet' "status=$status output=$out"
    fi

    out="$(run_notify 'done' '' 2>&1)"; status=$?
    if [ $status -eq 0 ]; then
        pass 'empty payload never fails the turn'
    else
        fail 'empty payload never fails the turn' "status=$status"
    fi
}

# refute <name> <command...> — passes when the command exits non-zero.
refute() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$name" "expected a non-zero exit"; else pass "$name"; fi
}

test_cli() {
    printf '\n\033[1mcli\033[0m\n'
    local home="$WORK/clihome" out length
    run_cli() { env PATH="$STUB_BIN:$PATH" EARCON_HOME="$home" NO_COLOR=1 bash "$CLI" "$@"; }

    out="$(run_cli --version 2>&1)"
    case "$out" in "earcon "*) pass '--version' ;; *) fail '--version' "$out" ;; esac

    out="$(run_cli --help 2>&1)"
    case "$out" in
        *"earcon set <slot> <source>"*) pass '--help shows usage' ;;
        *) fail '--help shows usage' ;;
    esac

    out="$(run_cli status 2>&1)"
    case "$out" in
        *attention*done*) pass 'status lists both slots' ;;
        *) fail 'status lists both slots' "$out" ;;
    esac

    refute 'rejects an unknown slot'      run_cli set sideways /dev/null -y
    refute 'rejects a missing file'       run_cli set 'done' "$WORK/nope.wav" -y
    refute 'rejects a malformed --start'  run_cli set 'done' "$PLUGIN/assets/done.wav" --start -oops -y
    refute 'rejects an over-long --dur'   run_cli set 'done' "$PLUGIN/assets/done.wav" --dur 99 -y
    refute 'rejects an absurd --gain'     run_cli set 'done' "$PLUGIN/assets/done.wav" --gain 500 -y

    mkdir -p "$home"
    printf '%s' 'original sound' >"$home/done.wav"
    local cli_tmp="$WORK/cli-tmp"
    mkdir -p "$cli_tmp"
    cat >"$STUB_BIN/ffmpeg" <<'STUB'
#!/bin/sh
for output do :; done
printf '%s' 'partial output' >"$output"
exit 1
STUB
    chmod +x "$STUB_BIN/ffmpeg"
    if TMPDIR="$cli_tmp" run_cli set 'done' "$PLUGIN/assets/attention.wav" -y -q >/dev/null 2>&1; then
        fail 'failed ffmpeg import preserves the current sound' 'expected a non-zero exit'
    elif [ "$(cat "$home/done.wav")" = 'original sound' ] &&
         [ -z "$(find "$home" -maxdepth 1 -name '.done.wav.*' -print -quit)" ] &&
         [ -z "$(find "$cli_tmp" -mindepth 1 -print -quit)" ]; then
        pass 'failed ffmpeg import preserves the current sound'
    else
        fail 'failed ffmpeg import preserves the current sound' 'target changed or staging files leaked'
    fi
    rm -f "$STUB_BIN/ffmpeg"

    local copy_bin="$WORK/copy-bin" copy_home="$WORK/copy-home" copy_tmp="$WORK/copy-tmp" tool
    mkdir -p "$copy_bin" "$copy_home" "$copy_tmp"
    for tool in dirname basename mkdir mktemp rm mv awk; do
        ln -s "$(command -v "$tool")" "$copy_bin/$tool"
    done
    cat >"$copy_bin/cp" <<'STUB'
#!/bin/sh
for target do :; done
printf '%s' 'partial copy' >"$target"
exit 1
STUB
    chmod +x "$copy_bin/cp"
    printf '%s' 'original sound' >"$copy_home/done.wav"
    if env PATH="$copy_bin" EARCON_HOME="$copy_home" TMPDIR="$copy_tmp" NO_COLOR=1 \
        /bin/bash "$CLI" set 'done' "$PLUGIN/assets/attention.wav" -y -q >/dev/null 2>&1; then
        fail 'failed fallback copy preserves the current sound' 'expected a non-zero exit'
    elif [ "$(cat "$copy_home/done.wav")" = 'original sound' ] &&
         [ -z "$(find "$copy_home" -maxdepth 1 -name '.done.wav.*' -print -quit)" ] &&
         [ -z "$(find "$copy_tmp" -mindepth 1 -print -quit)" ]; then
        pass 'failed fallback copy preserves the current sound'
    else
        fail 'failed fallback copy preserves the current sound' 'target changed or staging files leaked'
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        printf '  \033[2m- ffmpeg not installed, skipping import tests\033[0m\n'
        return 0
    fi

    if run_cli set 'done' "$PLUGIN/assets/attention.wav" --dur 0.3 -y -q >/dev/null 2>&1 &&
       [ -s "$home/done.wav" ]; then
        pass 'imports a local file'
    else
        fail 'imports a local file'
    fi

    if command -v ffprobe >/dev/null 2>&1; then
        length="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$home/done.wav")"
        if awk -v l="$length" 'BEGIN { exit !(l > 0.25 && l < 0.4) }'; then
            pass 'honours --dur'
        else
            fail 'honours --dur' "got ${length}s"
        fi
    fi

    out="$(run_cli status 2>&1)"
    case "$out" in *custom*) pass 'status reports the import' ;; *) fail 'status reports the import' "$out" ;; esac

    run_cli reset 'done' >/dev/null 2>&1
    if [ ! -f "$home/done.wav" ]; then pass 'reset removes it'; else fail 'reset removes it'; fi

    if run_cli reset all >/dev/null 2>&1; then
        pass 'reset all is idempotent'
    else
        fail 'reset all is idempotent'
    fi
}

case "${1:-all}" in
    hooks) test_hooks ;;
    cli)   test_cli ;;
    all)   test_hooks; test_cli ;;
    *)     printf 'usage: tests/run.sh [all|hooks|cli]\n' >&2; exit 2 ;;
esac

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

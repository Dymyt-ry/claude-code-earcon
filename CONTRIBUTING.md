# Contributing

Small, focused pull requests are the easiest to say yes to.

## Getting set up

Nothing to install for the tests themselves — they stub the audio player and
never touch the network:

```bash
tests/run.sh                     # everything
tests/run.sh hooks               # just the payload filter table
tests/run.sh cli                 # just the CLI
python3 tests/check_manifests.py # manifest cross-checks
```

For the import tests you also want `ffmpeg`; they skip themselves without it.
`shellcheck` runs in CI and is worth having locally:

```bash
brew install ffmpeg shellcheck      # macOS
sudo apt install ffmpeg shellcheck  # Debian/Ubuntu
shellcheck -x --severity=style plugins/earcon/scripts/*.sh plugins/earcon/bin/earcon tests/run.sh
```

## Trying a change for real

```bash
claude --plugin-dir ./plugins/earcon
```

That loads the working copy over any installed version for one session. Run
`/reload-plugins` after edits instead of restarting.

To see the allowlisted event metadata and playback decision:

```bash
EARCON_DEBUG=1 claude --plugin-dir ./plugins/earcon
tail -20 ~/.claude/earcon/debug.log
```

Or drive the script directly, which is usually faster:

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt"}' \
  | CLAUDE_PLUGIN_ROOT=./plugins/earcon bash plugins/earcon/scripts/notify.sh attention
```

## What a change should come with

- **A case in `tests/run.sh`** if you touch the filter. The table there is the
  specification of when this plugin makes noise; adding a trigger without
  adding a row is how a plugin becomes annoying.
- **A `CHANGELOG.md` entry** under `## [Unreleased]`.
- **A README update** if you change a trigger, an option, or a requirement.

Two rules the code holds to, worth keeping:

1. `notify.sh` exits `0` on every path. A notification sound must not be able
   to fail someone's turn.
2. Nothing blocks. The player is detached; the hook returns immediately.

## Reporting a bug

Include:

- OS and version, and whether you're on WSL
- `claude --version`
- The output of `earcon status`
- An excerpt from `~/.claude/earcon/debug.log` with `EARCON_DEBUG=1` set; the
  log stores only allowlisted event metadata, never the raw hook payload

"It doesn't play" and "it plays too often" are both bugs here, and the debug
log usually settles which one it is in a line or two.

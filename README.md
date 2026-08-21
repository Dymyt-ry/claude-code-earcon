<h1 align="center">🔔 earcon</h1>

<p align="center"><em>Hear when Claude Code needs you.</em></p>

<p align="center">
  <a href="https://github.com/Dymyt-ry/claude-code-earcon/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Dymyt-ry/claude-code-earcon/ci.yml?branch=main&style=flat-square&label=CI&labelColor=1c1c1c"></a>
  <a href="./LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-4c9a2a?style=flat-square&labelColor=1c1c1c"></a>
  <a href="https://claude.com/claude-code"><img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-d97757?style=flat-square&labelColor=1c1c1c"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/macOS%20·%20Linux%20·%20WSL-4a90d9?style=flat-square&labelColor=1c1c1c">
  <img alt="Dependencies" src="https://img.shields.io/badge/runtime%20deps-none-8b5cf6?style=flat-square&labelColor=1c1c1c">
</p>

---

You give Claude a long task, switch to Slack, and come back ten minutes later to
find it has been sitting on a permission prompt for nine of them. Or it finished
in ninety seconds and you didn't notice.

**earcon** plays a short sound at exactly those two moments, and at no others.
The hook path is under 250 lines of shell with no runtime dependencies — no daemon, no
Node, nothing to keep alive — and it plays any sound you want, including one
pulled straight off YouTube.

```bash
claude plugin marketplace add Dymyt-ry/claude-code-earcon
claude plugin install earcon@earcon
```

Restart the session. That's the whole setup.

> An *earcon* is the audio equivalent of an icon: a short, deliberately
> designed sound that tells you something without demanding you look.

## What it plays, and when

| Sound | Fires on | Hook |
|---|---|---|
| **attention** | Claude asks permission to use a tool | `Notification` · `permission_prompt` |
| **attention** | Claude asks you to pick between options | `PreToolUse` · `AskUserQuestion` |
| **attention** | Claude hands you a plan to approve | `PreToolUse` · `ExitPlanMode` |
| **attention** | A teammate agent needs input | `Notification` · `agent_needs_input` |
| **done** | The turn ends and control returns to you | `Stop` |

And, deliberately, on nothing else. Idle timeouts, login confirmations,
background task chatter, and every one of the twenty-odd other hook events
Claude Code emits stay silent. Subagent completions (`SubagentStop`) and turns
that another hook resumes (`stop_hook_active`) don't double-ping you either.

## Bring your own sound

The bundled tones are two synthesized chimes — a rising one for *attention*, a
falling one for *done*. They exist so the plugin works the second it installs,
not because you should keep them.

While the plugin is enabled, `earcon` is on Claude's PATH, so the easiest way to
change a sound is to ask:

> *"set my done sound to the first two seconds of this: https://youtu.be/…"*

Or run it yourself:

```bash
earcon set attention ~/sounds/ping.wav
earcon set done      https://example.com/bell.wav
earcon set done      'https://youtu.be/VIDEO_ID' --start 1:04 --dur 1.8
```

| | |
|---|---|
| `--start <t>` | Where to start in the source: `7`, `7.5`, `1:03`, `0:01:03` |
| `--dur <s>` | How much to keep. Default `2.5`, capped at `10` |
| `--gain <dB>` | Nudge the level, e.g. `-6` or `3` |
| `--no-normalize` | Keep the source's own level instead of matching the others |
| `--no-fade` | Skip the fade in and out |
| `-y` `-q` | Don't ask before replacing · don't play it back |

Every import is trimmed, faded at both ends so it can't click, converted to
44.1 kHz mono WAV, and **level-matched to about −3 dBFS** — the quiet bridge of
a song and a mastered drum hit end up equally audible. Anything yt-dlp handles
works as a source; a direct audio URL doesn't need yt-dlp at all.

```bash
earcon status            # resolved paths, chosen player, which tools are present
earcon test              # play both
earcon reset all         # back to the bundled tones
```

Imported sounds live in `~/.claude/earcon/` and survive plugin updates.

### Sound packs

The two this plugin was originally built around, and the exact commands that
install them — both verified against the current importer:

| Slot | Sound | Install |
|---|---|---|
| **attention** | [fahh](https://youtu.be/VP6eZu3SAak) | `earcon set attention 'https://youtu.be/VP6eZu3SAak' --dur 2` |
| **done** | [blue lobster](https://youtu.be/ywthKNqI7uI) | `earcon set done 'https://youtu.be/ywthKNqI7uI' --dur 2.5` |

They're linked rather than bundled, because this repo ships only audio it owns.

> You are responsible for having the right to use whatever you import. The
> bundled tones are original and MIT-licensed along with the rest of the repo.

## Configuration

Claude Code asks for these when the plugin is installed, and `/plugin` can
change them later:

| Option | Default | What it does |
|---|---|---|
| Sound when Claude needs you | on | Permission prompts, questions, plan approvals |
| Sound when Claude finishes | on | The `Stop` sound |
| Attention sound / Done sound | bundled | Point either at a file you already have |
| Volume | `1.0` | `0.0` is silent; intermediate levels work where the player supports them |

Environment variables override all of it, which is handy for one project or one
shell:

| Variable | Effect |
|---|---|
| `EARCON_ENABLED=0` | Silence everything, without uninstalling |
| `EARCON_ATTENTION_SOUND` `EARCON_DONE_SOUND` | Use these files instead |
| `EARCON_VOLUME` | `0.0`–`1.0`; `aplay` and PowerShell use mute/full volume only |
| `EARCON_HOME` | Where imported sounds live |
| `EARCON_DEBUG=1` | Log allowlisted event metadata and decisions to `$EARCON_HOME/debug.log` |

A sound is resolved in that order — environment variable, then install-time
setting, then anything `earcon set` imported, then the bundled tone. The first
file that actually exists wins, so a stale path in your shell profile degrades
to the next option instead of silence.

## Requirements

| | Playback | Notes |
|---|---|---|
| **macOS** | `afplay`, built in | Nothing to install; adjustable volume |
| **Linux** | `ffplay`, `mpv`, `mpg123`, `paplay` or `aplay` | Any one; `aplay` supports mute/full volume only |
| **WSL / Git Bash** | `powershell.exe`, built in | WAV only; mute/full volume only |

Importing with `earcon set` additionally wants `ffmpeg` for trimming and
level-matching, and `yt-dlp` for anything that isn't a direct file URL. Neither
is needed to *play* sounds, and the plugin degrades cleanly when they're
missing — a local file still imports, it just arrives untrimmed.

`python3` is used to parse hook payloads when it's available. When it isn't —
including the macOS stub that's on `PATH` but fails on every call — the script
falls back to matching the payload directly and keeps working.

## How it works

Three hooks, one script, one decision:

```
Notification (permission_prompt|agent_needs_input) ─┐
PreToolUse   (AskUserQuestion|ExitPlanMode) ────────┼─→ notify.sh attention
Stop ───────────────────────────────────────────────┴─→ notify.sh done
```

Claude Code's matchers do the first pass, but the script re-checks the payload
rather than trusting them, because **a `Notification` that carries no
`notification_type` reaches every `Notification` hook regardless of its
matcher**. Without the second gate, an untyped notification would ping you on
events you never asked about; with it, the plugin falls back to reading the
message text and stays quiet unless it looks like a request for you.

Everything else follows from three constraints:

- **A notification must never break a turn.** `notify.sh` exits `0` on every
  path — bad JSON, missing sound file, no audio player, no Python.
- **A notification must never make you wait.** The player is detached, so the
  hook returns in milliseconds regardless of how long the sound is.
- **The two halves have to agree on one path.** Hooks receive
  `${CLAUDE_PLUGIN_DATA}`; executables in `bin/` receive no plugin environment
  at all. Neither can derive the other's view, so both compute
  `~/.claude/earcon` independently — which also means your sounds outlive
  updates and reinstalls.

## Development

```bash
git clone https://github.com/Dymyt-ry/claude-code-earcon
cd claude-code-earcon

tests/run.sh                  # 49 cases, no network, no audio
tests/run.sh hooks            # just the filter table
python3 tests/check_manifests.py

claude plugin validate .
claude plugin validate ./plugins/earcon --strict
claude --plugin-dir ./plugins/earcon    # load it without installing
```

The suite stubs the audio player earlier on `PATH` and asserts *which file*
each payload played, so a change that silently stops playing — or starts
playing on the wrong event — fails instead of passing on a zero exit code. CI
runs it on Linux and macOS, plus once more with `ffmpeg`, `yt-dlp` and
`python3` removed from `PATH`.

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE) © Timofej Golobokov ([@Dymyt-ry](https://github.com/Dymyt-ry))

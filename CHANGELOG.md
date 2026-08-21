# Changelog

Notable changes to `earcon`, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-08-20

First stable release. The plugin was previously published as two separate
plugins, `fahh` and `done`, in a marketplace of the same name; both are merged
into one configurable plugin here. `renames` in the marketplace manifest
migrates existing installs automatically.

### Added
- `earcon` CLI on the Bash tool's `PATH`: `set`, `test`, `reset`, `status`.
  Imports a sound from a local file, a direct audio URL, or anything `yt-dlp`
  can extract from, then trims, fades and level-matches it.
- Imports are normalized to roughly −3 dBFS by default, so a quiet passage and
  a mastered sample end up equally audible. `--no-normalize` opts out, and a
  clip that is still inaudible afterwards says so.
- `/earcon:sound` skill, so changing a sound can be asked for in plain language.
- Install-time configuration (`userConfig`): per-slot on/off switches, custom
  sound paths, and volume, exposed to the hook as `CLAUDE_PLUGIN_OPTION_*`.
- `EARCON_ENABLED=0` silences the plugin without uninstalling it.
- Adjustable volume where the player supports it, with reliable mute across
  every supported player.
- WSL and Git Bash playback through `powershell.exe` (WAV only).
- `agent_needs_input` notifications now count as needing your attention.
- Test suite: 49 cases asserting which file each payload plays, plus manifest
  cross-checks. CI runs it on Linux and macOS, and again with `ffmpeg`,
  `yt-dlp` and `python3` removed from `PATH`.

### Changed
- Bundled sounds are now original synthesized tones (0.48 s and 0.66 s WAV)
  rather than 5.3 s MP3 clips of unclear provenance. WAV also plays through
  `aplay`, which cannot decode MP3.
- The `Notification` matcher is back. It was removed in 0.2.1 because Claude
  Code was not firing matched `Notification` hooks; verified working again
  against 2.1.237, where the matcher is applied to `notification_type`. The
  script-side filter is kept as a second gate, because a notification that
  carries no `notification_type` reaches every `Notification` hook regardless.
- Both halves of the plugin now resolve sounds through `~/.claude/earcon`.
  Executables in `bin/` receive no plugin environment, so they cannot see the
  `${CLAUDE_PLUGIN_DATA}` path the hook is given; a fixed location is the only
  one both can compute, and it survives updates.
- One `notify.sh` and one shared `lib.sh` replace the two near-identical copies.

### Fixed
- A machine without a working `python3` no longer disables the plugin outright.
  It previously exited silently; the payload filter now falls back to matching
  the raw JSON. This also covers the macOS `python3` stub, which is on `PATH`
  but fails on every invocation.
- Debug logs are written under `$EARCON_HOME` instead of a predictable path in
  `/tmp`, where any other user could have pre-created the file as a symlink and
  redirected the appends. The log is also size-capped.
- A sound path that no longer exists falls through to the next candidate
  instead of producing silence.
- README no longer documents `claude plugin path`, which is not a command.

## [0.2.1] — 2026-05-24

### Fixed
- `fahh`: removed the `permission_prompt` matcher on the `Notification` hook,
  which was preventing it from firing.

## [0.2.0] — 2026-05-23

### Added
- `done` plugin: a sound when Claude finishes responding (`Stop` hook).

## [0.1.0] — 2026-05-21

### Added
- Initial release: `fahh`, a sound on permission prompts and multi-option
  questions.

---
description: Change, preview, or reset the sound Claude Code plays through the earcon plugin. Use when the user wants a different notification sound, wants to install one from a file, a URL or a YouTube link, wants to hear the current sounds, or reports that the sound is not playing.
---

# Change the notification sound

The `earcon` command is on your PATH whenever this plugin is enabled. Run it
with the Bash tool; never edit files under the sounds directory by hand.

## Which slot

- `attention` — Claude needs the user: permission prompt, question, plan approval.
- `done` — Claude finished the turn.

If the user says "the sound" without saying which, and the context does not make
it obvious, ask which one they mean.

## Setting a sound

```bash
earcon set <attention|done> <file-or-url> [--start T] [--dur S] [--gain dB] -y
```

Pass `-y` so the command does not block waiting for a confirmation it cannot
receive. Add `-q` if the user does not want it played back.

- A YouTube or similar link needs `yt-dlp`; a direct audio URL does not.
- Long sources need `--start` and `--dur` to pick the good part. The default is
  the first 2.5 seconds, which is rarely the interesting part of a song.
- If it comes back too loud or too quiet, re-run with `--gain -6` or `--gain 4`.

## Other commands

```bash
earcon status            # resolved paths, chosen player, which tools are installed
earcon test [slot]       # play the current sounds
earcon reset <slot|all>  # back to the bundled tones
```

## When no sound plays

Run `earcon status` first and read it before guessing:

- `player: none found` — no audio player on the machine. On Linux suggest
  `ffmpeg` (for `ffplay`), `mpv`, or `mpg123`.
- The slot shows `bundled` when the user expected their own file — the import
  did not land; run `earcon set` again and read the error.
- Everything looks right but nothing is audible — the hooks may not be loaded.
  Ask the user to check `/hooks` for `Notification`, `PreToolUse` and `Stop`
  entries, and to restart the session if they are missing.

For a payload-level trace, set `EARCON_DEBUG=1` in the environment and read
`debug.log` in the sounds directory shown by `earcon status`.

## Rights

The user is responsible for having the right to use whatever they import. Do
not talk them out of a sound, but do not go looking for copyrighted audio on
their behalf either.

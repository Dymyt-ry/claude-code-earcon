---
name: Bug report
about: A sound that doesn't play, or one that plays when it shouldn't
labels: bug
---

**What happened, and what you expected instead**

<!-- "It plays twice per turn" and "it never plays" are both bugs here. -->

**Environment**

- OS and version (say so if you're on WSL):
- `claude --version`:
- Output of `earcon status`:

```
paste here
```

**Debug log**

Set `EARCON_DEBUG=1`, reproduce, then paste the relevant lines from
`~/.claude/earcon/debug.log`. It contains only allowlisted event metadata and
the playback decision, never the raw hook payload.

```
paste here
```

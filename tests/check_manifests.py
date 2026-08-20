#!/usr/bin/env python3
"""Structural checks on the plugin and marketplace manifests.

`claude plugin validate` is the authority on the schema, but it needs the
Claude Code binary. These are the invariants that break silently when a file
is edited by hand: version drift between the two manifests, hooks pointing at
scripts that do not exist, and assets a hook expects to find.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN_DIR = os.path.join(ROOT, "plugins", "earcon")
FAILURES = []


def check(condition, message):
    if condition:
        print(f"  \033[32m✓\033[0m {message}")
    else:
        print(f"  \033[31m✗\033[0m {message}")
        FAILURES.append(message)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


marketplace = load(os.path.join(ROOT, ".claude-plugin", "marketplace.json"))
plugin = load(os.path.join(PLUGIN_DIR, ".claude-plugin", "plugin.json"))
hooks = load(os.path.join(PLUGIN_DIR, "hooks", "hooks.json"))

print("\n\033[1mmanifests\033[0m")
check(marketplace["name"] == "earcon", "marketplace is named earcon")
check(len(marketplace["plugins"]) == 1, "marketplace lists exactly one plugin")

entry = marketplace["plugins"][0]
check(entry["name"] == plugin["name"], "plugin name matches in both manifests")
check(
    entry["version"] == plugin["version"],
    f"version matches in both manifests ({plugin['version']})",
)
check(
    os.path.isdir(os.path.join(ROOT, entry["source"])),
    f"source path exists: {entry['source']}",
)
check(
    marketplace["renames"].get("fahh") == "earcon"
    and marketplace["renames"].get("done") == "earcon",
    "renames migrate both former plugin names",
)

print("\n\033[1mhooks\033[0m")
events = set(hooks["hooks"])
check(
    events == {"Notification", "PreToolUse", "Stop"},
    f"hooks on exactly Notification, PreToolUse, Stop (got {sorted(events)})",
)

slots = set()
for event, matchers in hooks["hooks"].items():
    for matcher in matchers:
        for hook in matcher["hooks"]:
            command = hook["command"]
            check(
                "${CLAUDE_PLUGIN_ROOT}" in command,
                f"{event} hook resolves through CLAUDE_PLUGIN_ROOT",
            )
            check(
                isinstance(hook.get("timeout"), int) and hook["timeout"] <= 10,
                f"{event} hook has a short timeout",
            )
            slots.add(command.rsplit(" ", 1)[-1].strip('"'))

check(slots == {"attention", "done"}, f"hooks cover both slots (got {sorted(slots)})")

print("\n\033[1mfiles\033[0m")
for relative in [
    "scripts/notify.sh",
    "scripts/lib.sh",
    "bin/earcon",
    "skills/sound/SKILL.md",
]:
    check(os.path.isfile(os.path.join(PLUGIN_DIR, relative)), f"{relative} exists")

for relative in ["scripts/notify.sh", "bin/earcon"]:
    check(
        os.access(os.path.join(PLUGIN_DIR, relative), os.X_OK),
        f"{relative} is executable",
    )

for slot in sorted(slots):
    asset = os.path.join(PLUGIN_DIR, "assets", f"{slot}.wav")
    check(os.path.isfile(asset), f"assets/{slot}.wav ships with the plugin")
    if os.path.isfile(asset):
        size = os.path.getsize(asset)
        check(0 < size < 500_000, f"assets/{slot}.wav is a sane size ({size} bytes)")

print()
if FAILURES:
    print(f"\033[31m{len(FAILURES)} check(s) failed\033[0m")
    sys.exit(1)
print("\033[32mall manifest checks passed\033[0m")

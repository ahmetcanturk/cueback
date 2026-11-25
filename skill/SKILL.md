---
name: cueback
description: Control cueback, the haptic trackpad cues for Claude Code. Turn them on or off, check the status, run the demo, switch the theme, play one cue, restart or remove it. Use when the user asks for any of that, in any language, with requests like "turn cueback off", "mute the trackpad cues", "run the cueback demo", "switch cueback to theme 2", "cueback status", "restart cueback" or "remove cueback".
---

# cueback

cueback taps and chimes on the Mac's trackpad for Claude Code events: a permission request, Claude finishing, an
error, Claude waiting for the user, subagents starting and stopping. Its program is `~/.local/bin/cueback`.

| The user asks to | Run |
|---|---|
| turn it off or mute it | `~/.local/bin/cueback off` |
| turn it back on | `~/.local/bin/cueback on` |
| see the demo | `~/.local/bin/cueback demo` |
| switch the theme ("theme 2", "use mochi", "the warcraft theme", "back to classic") | `~/.local/bin/cueback theme <name or number>`: 1 classic, 2 mochi, 3 warhorn (also "warcraft"), 4 blocky (also "minecraft"), 5 owlpost (also "potter", "hp", "hogwarts"), 6 r2d2 (also "starwars", "sw", "r2"); with no name it lists them |
| check it | `~/.local/bin/cueback status` |
| hear one cue ("play the done cue") | `~/.local/bin/cueback play <cue>`; `~/.local/bin/cueback cues` lists them |
| restart it, or bring it back after Quit | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.cueback.daemon.plist 2>/dev/null; launchctl kickstart -k gui/$(id -u)/app.cueback.daemon` |

The user's own themes are JSON files in `~/Library/Application Support/cueback/themes/` (the file's name is the
theme's name); `~/.local/bin/cueback check <file>` says what's in one and what looks wrong.

`off` only silences the cues that come from Claude Code: the background service keeps running, and `play` and
`demo` still work. The bell in the menu bar opens a panel with the same switch, the volume, quiet hours and a
button for each cue; its Quit stops cueback until the next login or a restart. Confirm what you did in one short
sentence, in the user's language.

Remove cueback only when the user asks for that: run `~/.local/bin/cueback uninstall-hooks`, then
`launchctl bootout gui/$(id -u)/app.cueback.daemon`, and delete `~/Library/LaunchAgents/app.cueback.daemon.plist`,
`~/.local/bin/cueback` and the `~/.claude/skills/cueback` folder.

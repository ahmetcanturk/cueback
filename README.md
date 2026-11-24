# cueback

Haptic cues for Claude Code, played on your MacBook's trackpad. *cue + feedback.*

When Claude asks for permission, finishes, fails or is waiting for you, the trackpad taps or chimes, even with
the sound off. There's no speaker in the trackpad: cueback drives its haptic motor, the way
[nospeaker](https://github.com/os6/nospeaker) makes it talk.

> Private alpha. Needs macOS 13 or later and a Force Touch trackpad.

## Cues

| cue | Claude Code event | default | feel |
|---|---|---|---|
| `permission` | PermissionRequest | on | three firm taps, rising |
| `waiting` | Notification · `idle_prompt` | on | two soft taps |
| `input` | Elicitation | on | two rising taps |
| `done` | Stop | on | two rising notes |
| `error` | StopFailure | on | a tap, then a low buzz |
| `subagent-start` · `subagent-stop` | SubagentStart · SubagentStop | on | one soft tick · two soft ticks |
| `task-done` | TaskCompleted | off | one short high note |
| `tool-failed` | PostToolUseFailure | off | a faint tick |
| `compact` | PreCompact | off | three soft rising notes |
| `session-start` · `session-end` | SessionStart (startup) · SessionEnd | off | two notes up · down |

Main work is firm and sub-work is soft: a cue that comes from inside a subagent (its permission request, say)
plays at 60% of its strength (`subagentLevel` in the theme), and the subagents' own ticks are light already.

Left out on purpose: `Stop` while background tasks still run or a hook continued the turn, `SubagentStop`
from Claude's internal agents, and `PreToolUse`/`PostToolUse`, which fire dozens of times a minute.

## How it works

`cueback daemon` opens the motor once and listens on a socket in `~/Library/Application Support/cueback/`,
readable only by you; a LaunchAgent starts it at login and brings it back if it stops. Claude Code's hooks run
`cueback hook` with `"async": true`: it reads the event, sends the cue's name and exits. It never prints, never
fails and never makes Claude wait.

The daemon also puts a bell in the menu bar (`--headless` leaves it out). Its panel turns the cues on and off,
sets the volume (one tap plays at the new level when you let go), sets quiet hours, when the cues from Claude
Code stay silent, plays any cue or the demo, and shows the last cue. Quit stops cueback until the next login. The
panel's settings are kept in `~/Library/Application Support/cueback/config.json`.

A theme is a JSON file of cues, each a list of steps: `{"tap": 0.6}`, `{"note": "A6", "ms": 120, "level": 0.8}`,
`{"hz": 165, "ms": 200}` or `{"wait": 100}`. The default theme is in [Theme.swift](Sources/cueback/Theme.swift).

## Install

```sh
scripts/install.sh                       # builds and installs: the program, the daemon, the hooks, the skill
scripts/package.sh                       # dist/cueback.zip, to give to someone: unzip, run install.sh
~/.local/bin/cueback demo                # a Claude Code session in fifteen seconds
~/.local/bin/cueback play permission     # any cue, even one that's off; --subagent plays it quieter
~/.local/bin/cueback off                 # silence the cues from Claude Code; `on` brings them back
```

The install puts the program in `~/.local/bin/cueback`, runs its daemon as a LaunchAgent that starts at login
(log: `~/Library/Logs/cueback.log`), adds the hooks to `~/.claude/settings.json` next to yours (the old file is
kept as a backup) and adds a Claude skill, so "cueback'i kapat" or "cueback demo çalıştır" works in any session.
The first install plays the `installed` cue.

To remove it: run `cueback uninstall-hooks` and `launchctl bootout gui/$(id -u)/app.cueback.daemon`, then delete
`~/Library/LaunchAgents/app.cueback.daemon.plist`, `~/.local/bin/cueback` and `~/.claude/skills/cueback`.

## Safety

One person reported their trackpad's click feel gone after running nospeaker
([nospeaker#15](https://github.com/os6/nospeaker/issues/15)), with the driver refusing thousands of commands
(0xE00002BC) just before. cueback keeps the motor's work light: a tap is one command and a tone one per ~40 ms,
commands never overlap, a cue is cut off at 1.2 s, 150 ms of quiet follows each one, at most 30 play in a
minute, and the motor is never driven past its normal maximum. The daemon logs any command the motor refuses.

## Roadmap

- A theme picker in the menu bar
- Permission nudges that grow stronger while a request waits
- Original themes, including an RTS-style one (no copied game sounds)
- Signed and notarized builds

## Credits

Motor access and the tap are adapted from nospeaker (MIT, Cody Collier); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). MultitouchSupport is a private macOS framework, so a macOS
update can break this.

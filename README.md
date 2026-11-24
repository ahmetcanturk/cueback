# cueback

Haptic cues for Claude Code, played on your MacBook's trackpad. *cue + feedback.*

When Claude asks for permission, finishes, fails or is waiting for you, the trackpad taps or chimes, even with
the sound off. There's no speaker in the trackpad: cueback drives its haptic motor, the way
[nospeaker](https://github.com/os6/nospeaker) makes it talk.

> Private alpha. Needs macOS 13 or later and a Force Touch trackpad.

## Cues

| cue | Claude Code event | default | feel |
|---|---|---|---|
| `permission` | PermissionRequest | on | light, medium, strong taps |
| `waiting` | Notification · `idle_prompt` | on | two soft taps |
| `input` | Elicitation | on | two rising taps |
| `done` | Stop | on | two rising notes |
| `error` | StopFailure | on | a tap, then a low buzz |
| `subagent-start` · `subagent-stop` | SubagentStart · SubagentStop | off | one tick · two ticks |
| `task-done` | TaskCompleted | off | one short high note |
| `tool-failed` | PostToolUseFailure | off | a faint tick |
| `compact` | PreCompact | off | three soft rising notes |
| `session-start` · `session-end` | SessionStart (startup) · SessionEnd | off | two notes up · down |

Left out on purpose: `Stop` while background tasks still run or a hook continued the turn, `SubagentStop`
from Claude's internal agents, and `PreToolUse`/`PostToolUse`, which fire dozens of times a minute.

## How it works

`cueback daemon` opens the motor once and listens on a socket in `~/Library/Application Support/cueback/`,
readable only by you. Claude Code's hooks run `cueback hook` with `"async": true`: it reads the event, sends
the cue's name and exits. It never prints, never fails and never makes Claude wait.

A theme is a JSON file of cues, each a list of steps: `{"tap": 0.6}`, `{"note": "A6", "ms": 120, "level": 0.8}`,
`{"hz": 165, "ms": 200}` or `{"wait": 100}`. The default theme is in [Theme.swift](Sources/cueback/Theme.swift).

## Try it

```sh
swift build -c release
.build/release/cueback cues                # the cues and their events (silent)
.build/release/cueback daemon              # keeps running; plays through the trackpad
.build/release/cueback play permission     # in another terminal
.build/release/cueback hooks-json          # the hooks block to add to ~/.claude/settings.json
```

`--volume 0-100` turns the daemon down, `--theme file.json` uses your own cues, and `--external` plays through
a Magic Trackpad.

## Safety

One person reported their trackpad's click feel gone after running nospeaker
([nospeaker#15](https://github.com/os6/nospeaker/issues/15)). cueback keeps the motor's work light: a cue is
cut off at 1.2 s, 150 ms of quiet follows each one, at most 30 play in a minute, and the motor is never driven
past its normal maximum.

## Roadmap

- Menu bar app: theme picker, a test button for each cue, volume, quiet hours, start at login
- Permission nudges that grow stronger while a request waits
- Original themes, including an RTS-style one (no copied game sounds)
- Signed and notarized builds

## Credits

Motor access and the tap are adapted from nospeaker (MIT, Cody Collier); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). MultitouchSupport is a private macOS framework, so a macOS
update can break this.

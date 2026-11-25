# cueback

**Your MacBook's trackpad tells you what Claude Code is doing.** *cue + feedback.*

When Claude asks for permission, finishes, fails or has been waiting for you, the trackpad taps, chimes or even
talks, with the Mac's sound off. There's no speaker in a trackpad: cueback drives its haptic motor, the trick
[nospeaker](https://github.com/os6/nospeaker) uses to make it speak.

<!-- The demo video goes here. -->

It needs a MacBook with a Force Touch trackpad (2015 or later), macOS 13 or later and a recent Claude Code. So
far it has run on one Mac: a MacBook Pro with an M1 Pro, on macOS 27. A Magic Trackpad 2 should work but hasn't
been tried.

> **Before you install.** cueback drives the trackpad's motor through MultitouchSupport, a private macOS
> framework that Apple doesn't document. One person reported losing their trackpad's click feel after running
> nospeaker, which uses the same framework. cueback asks far less of the motor (see [Safety](#safety)), but
> nobody outside Apple knows the motor's limits. Use it at your own risk; the [disclaimer](#disclaimer) says
> what that means.

## Install

```sh
git clone https://github.com/ahmetcanturk/cueback
cd cueback
scripts/install.sh
```

The script builds cueback, which takes about a minute and needs Apple's Command Line Tools
(`xcode-select --install`). Then it:

- puts the program in `~/.local/bin/cueback`
- starts its background service, which also starts at login (a LaunchAgent, `app.cueback.daemon`)
- adds its hooks to `~/.claude/settings.json`, next to yours, and keeps the old file as a backup
- adds a Claude skill, so you can ask Claude to turn cueback off, switch its theme or run the demo

You'll feel the `installed` cue, and a bell appears in the menu bar.

To remove it, run `~/.local/bin/cueback uninstall-hooks` and
`launchctl bootout gui/$(id -u)/app.cueback.daemon`, then delete
`~/Library/LaunchAgents/app.cueback.daemon.plist`, `~/.local/bin/cueback` and `~/.claude/skills/cueback`.

## Use

**The menu bar.** Click the bell: turn the cues on or off, pick a theme, set the volume and quiet hours, try
any cue, play the demo. Quit stops cueback until your next login.

**The terminal.**

```sh
~/.local/bin/cueback demo                # a Claude Code session in fifteen seconds, on the trackpad
~/.local/bin/cueback theme               # the themes; `cueback theme 2` switches
~/.local/bin/cueback play permission     # any cue, even one that's off; --subagent plays it quieter
~/.local/bin/cueback off                 # silence the cues from Claude Code; `on` brings them back
~/.local/bin/cueback status              # on or off, and whether the service is running
```

**Claude.** In any session, ask it to turn cueback off, switch to another theme or run the demo.

## Cues

| cue | Claude Code event | default | feel in Classic |
|---|---|---|---|
| `prompt` | UserPromptSubmit | off (on in Warhorn and R2-D2) | one light tap |
| `permission` | PermissionRequest | on | three firm taps, rising |
| `waiting` | Notification · `idle_prompt` | on | two soft taps |
| `input` | Elicitation | on | two rising taps |
| `done` | Stop | on | two rising notes |
| `error` | StopFailure | on | a tap, then a low buzz |
| `subagent-start` · `subagent-stop` | SubagentStart · SubagentStop | on | one soft tick · two soft ticks |
| `task-done` | TaskCompleted | off | one short high note |
| `tool-failed` | PostToolUseFailure | off (on in Blocky) | a faint tick |
| `compact` | PreCompact | off | three soft rising notes |
| `session-start` · `session-end` | SessionStart (startup) · SessionEnd | off | two notes up · down |

Main work is firm and sub-work is soft: a cue that comes from inside a subagent (its permission request, say)
plays at 60% of its strength (`subagentLevel` in the theme), and the subagents' own ticks are light already.

Left out on purpose: `Stop` while background tasks still run or a hook continued the turn, `SubagentStop`
from Claude's internal agents, and `PreToolUse`/`PostToolUse`, which fire dozens of times a minute.

## Themes

A theme decides what every cue feels and sounds like. Six come with cueback:

- **1 · Classic**: firm taps and clear notes (the table above). A new install starts here.
- **2 · Mochi**: calm and sweet. Slow, soft pulses you feel under your finger and quiet music-box notes that
  ring and fade, at gentler strengths.
- **3 · Warhorn**: heavy and slow, an homage to orc-and-human strategy games. War drums, a horn call, and a
  gruff worker who talks back through the trackpad when the work is finished: "Job's done!"
- **4 · Blocky**: an homage to block-building games. A nasal "hrmm?" when you're needed, a fuse that hisses and
  goes off when the turn fails, digging, pops and tinkling orbs.
- **5 · Owlpost**: an homage to stories about a school of wizards. An owl hoots when you're needed, celesta
  notes ring, a quill scratches, and a British voice says a spell when the work is finished.
- **6 · R2-D2**: an homage to the small droid of the space films. Bent chirps and trills, a curious coo
  when you send a prompt, a rising whistle when it asks you something, and a wavering wail when the turn fails.

Switch in the menu bar, or with `cueback theme 2` (`cueback theme` lists them). Warhorn, Blocky, Owlpost and
R2-D2 are sounds of their own: no game's or film's audio or music is in them.

[THEMES.md](THEMES.md) has what each theme plays for each cue, and how to write a theme of your own.

## Safety

The motor is driven through a private framework, so what follows is what cueback does to stay gentle, not a
promise that it's harmless.

- **Few commands.** A tap is one command to the motor and a tone one per ~40 ms. The person who lost their
  trackpad's click feel ([nospeaker#15](https://github.com/os6/nospeaker/issues/15)) had the driver refusing
  thousands of commands (0xE00002BC) just before.
- **No overlap.** A command is never sent while the last one still plays; that is what the driver refuses.
- **Short and rare.** A cue is cut off at 1.2 s, 150 ms of quiet follows each one, and at most 30 play in a
  minute.
- **Never past normal.** The motor is never driven past its normal maximum; the volume only turns it down.
- **It tells you.** The daemon writes any command the motor refuses to `~/Library/Logs/cueback.log`.

Spoken lines (Warhorn's and Owlpost's) and hums and hisses (Blocky's) are the exceptions to "few commands": up
to about seventy in under a second, one for each beat of the voice's pitch. They're kept short, and the motor
has refused none of them.

## How it works

`cueback daemon` opens the motor once and listens on a socket in `~/Library/Application Support/cueback/`,
readable only by you; a LaunchAgent starts it at login and brings it back if it stops. Claude Code's hooks run
`cueback hook` with `"async": true`: it reads the event, sends the cue's name and exits. It never prints, never
fails and never makes Claude wait.

The daemon also puts the bell in the menu bar (`--headless` leaves it out). The panel's settings are kept in
`~/Library/Application Support/cueback/config.json`, and the log is `~/Library/Logs/cueback.log`.

A theme is a JSON file of cues, each a list of steps: a tap, a note, a pause, a hum, a spoken line, a sound
file of yours. Your own themes go in `~/Library/Application Support/cueback/themes/`; see
[THEMES.md](THEMES.md).

To give a built copy to someone without developer tools, `scripts/package.sh` makes `dist/cueback.zip`: they
unzip it and run `sh install.sh`. The copy isn't signed by Apple.

## Roadmap

- Permission nudges that grow stronger while a request waits
- A theme editor in the menu bar
- Signed and notarized builds

## Disclaimer

cueback is an independent hobby project. It is provided as is, with no warranty of any kind.

It drives your trackpad's haptic motor through a private, undocumented macOS framework. That may wear out,
damage or disable the trackpad's haptics, and a macOS update may break cueback at any time. You use it entirely
at your own risk: the author is not responsible for any damage to your hardware, your software or your data.

cueback is not affiliated with, endorsed by or sponsored by Anthropic or Apple. Warhorn, Blocky, Owlpost and
R2-D2 are fan homages made of sounds of their own. They are not affiliated with or endorsed by the owners of the
games and films they nod to, and every name and trademark belongs to its owner.

## Credits

Motor access and the speech analysis are adapted from nospeaker (MIT, Cody Collier); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE).

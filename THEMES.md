# Themes

A theme decides what every cue feels and sounds like on the trackpad. cueback comes with four, and plays one of
your own from a JSON file.

## The four themes

| theme | what it's like |
|---|---|
| **1 · Classic** | Firm taps and clear notes. A new install starts here. |
| **2 · Mochi** | Calm and sweet: slow, soft pulses you feel and quiet music-box notes, at gentler strengths. |
| **3 · Warhorn** | Heavy and slow, an homage to orc-and-human strategy games: war drums, a horn call, and a gruff worker who talks back through the trackpad. |
| **4 · Blocky** | An homage to block-building games: a nasal "hrmm?", a hissing fuse, digging, pops and tinkling orbs. |

Warhorn and Blocky are made of sounds of their own. No game's audio or music is in them: Warhorn's lines are
said by macOS's own voice, lowered in pitch, and Blocky's sounds are synthesized.

### What each one plays

| when | Classic | Mochi | Warhorn | Blocky |
|---|---|---|---|---|
| you send a prompt | – | – | two quick grunts | – |
| Claude asks for permission | three firm taps, rising | two soft knocks, then a rising question | a drum, then a horn rising a fifth | "hm… hrmm?" |
| Claude has waited a minute for you | two soft taps | a slow purr | distant drums | a long, falling "hrmmm" |
| an MCP server asks for input | two rising taps | two rising bell notes | a short horn and a drum | a short, rising "huh?" |
| Claude is finished | two rising notes | "ding, dong" | says "Job's done!" | three orb chimes, then a rising chime |
| the turn fails | a tap, then a low buzz | a low "uh-oh" | a drum, then three falling tones | a fuse hisses, then a boom |
| a tool call fails | – | – | – | a hurt "uh!" |
| a subagent starts | one soft tick | a soft pulse, then a bell note | says "Zug zug." | three crunches of digging |
| a subagent finishes | two soft ticks | a bell note, then a soft pulse | says "Work complete." | a crunch and a pop |

A dash means that theme stays silent then. A cue that comes from inside a subagent (its permission request,
say) plays quieter: at 60% of its strength in Classic, 65% in Warhorn, 70% in Mochi and Blocky.

## Switching

- **Menu bar:** click the bell and pick under Theme.
- **Terminal:** `cueback theme` lists the themes and marks the one in use; `cueback theme 2` or
  `cueback theme mochi` switches. `warcraft` and `minecraft` also work, for Warhorn and Blocky.
- **Claude:** say "tema 2" or "mochi'ye geç" in any session.

The new theme takes over at once and plays its `installed` cue, so you hear what you picked. Your choice is kept
in `~/Library/Application Support/cueback/config.json`.

## Trying a theme

```sh
cueback cues                          # every cue, what triggers it, and whether the theme in use plays it
cueback play permission               # play one cue now, even one the theme leaves off
cueback play permission --subagent    # the way it plays from inside a subagent
cueback demo                          # a whole Claude Code session in fifteen seconds
```

The menu bar panel has a button for each cue too.

## Writing your own

A theme is one JSON file. This is [examples/pebble.json](examples/pebble.json):

```json
{
  "name": "Pebble",
  "about": "Two taps and a chime.",
  "volume": 50,
  "enabled": ["permission", "done", "error"],
  "cues": {
    "permission": [{"tap": 0.6}, {"wait": 120}, {"tap": 0.9}],
    "done":       [{"note": "E6", "ms": 90}, {"wait": 20}, {"note": "A6", "ms": 170, "shape": "bell"}],
    "error":      [{"tap": 0.8}, {"wait": 140}, {"hz": 165, "ms": 200}],
    "installed":  [{"tap": 0.5}, {"wait": 120}, {"note": "A6", "ms": 200, "shape": "bell"}],
    "level":      [{"tap": 0.9}]
  }
}
```

To use it:

1. **Check it.** `cueback check pebble.json` lists its cues with their lengths and says what looks wrong: a
   note that isn't one, a cue name cueback doesn't have, a cue that's too long.
2. **Put it in the themes folder**, `~/Library/Application Support/cueback/themes/` (make the folder if it
   isn't there).
3. **Switch to it** with `cueback theme pebble`, or open the menu bar panel and pick it. It's numbered after
   the built-in themes.

The file's name is the theme's id, so `pebble.json` is `cueback theme pebble`. A file can't take a built-in
theme's name. After you change a theme you're using, run `cueback theme pebble` again to load the change.

### The file

| field | what it sets |
|---|---|
| `name` | What the theme is called in the menu bar and in `cueback theme`. |
| `about` | One line about it, shown under the picker. Optional. |
| `volume` | 0 to 100: how loud the theme is, until you move the menu bar's slider. Default 100. |
| `subagentLevel` | 0 to 1: the share of its strength a cue plays at when it comes from inside a subagent. Default 0.6. |
| `soft` | `true` makes every tone gentle unless its step says otherwise: tones under 500 Hz swell, the ones above ring and fade. Default `false`. |
| `enabled` | The cues that play for Claude Code's events. The rest stay silent then, but still play from `cueback play` and the panel. |
| `cues` | The cues: each a name and its list of steps. |

### The cues

| cue | plays when |
|---|---|
| `prompt` | you send Claude a prompt |
| `permission` | Claude asks for permission |
| `waiting` | Claude has been waiting for you for about a minute |
| `input` | an MCP server asks you for input |
| `done` | Claude finishes (not while background tasks are still running) |
| `error` | the turn ends on an API error |
| `subagent-start`, `subagent-stop` | a subagent starts, finishes |
| `task-done` | a task is marked complete |
| `tool-failed` | a tool call fails (not when you interrupted it) |
| `compact` | the conversation is about to be compacted |
| `session-start`, `session-end` | a session starts, ends |
| `installed` | cueback is installed, and when you switch to the theme |
| `fanfare` | the demo ends |
| `level` | you set the volume in the menu bar |

A cue you leave out never plays.

### The steps

A cue is a list of steps, played one after another. Each step is one of these:

| step | example | what it is |
|---|---|---|
| a tap | `{"tap": 0.6}` | A tap you feel. The number is its strength, 0 to 1. |
| a tone | `{"note": "A6", "ms": 120}` or `{"hz": 165, "ms": 200}` | A note by name (`A6`, `C#5`; A4 is 440 Hz) or a frequency from 80 to 4000 Hz. Under about 200 Hz you feel it more than you hear it. |
| a pause | `{"wait": 100}` | Silence, in milliseconds. |
| a slide | `{"glide": [520, 1700], "ms": 60}` | A tone that slides from the first pitch to the second: a pop going up, a drop going down. |
| a hum | `{"hum": [112, 104, 150], "ms": 380}` | A voice-like "hmm" whose pitch moves through the numbers, in Hz. Rising at the end, it sounds like a question. |
| noise | `{"hiss": [2600, 4000], "ms": 520, "rise": true}` | Noise between two frequencies: a hiss up high, a crunch down low. With `"rise": true` it grows. |
| a spoken line | `{"say": "Job's done!", "voice": "Ralph", "pitch": 0.75}` | A short line said by a macOS voice, through the trackpad. |

What else a step can carry:

- **`ms`**: how long it lasts. Default 120 for a tone, 60 for a slide, 300 for a hum, 200 for noise.
- **`level`**: its strength, 0 to 1. Default 0.8 for a tone, 0.6 for a hum, 0.5 for a slide and for noise, 0.9
  for a spoken line.
- **`shape`** (tones): `"plain"` holds the tone, `"bell"` strikes and fades like a music box, `"swell"` rises
  and falls like a breath.
- **`ring`** (tones): adds a quieter second tone at that multiple of the pitch, which makes a note glassy. `2`
  is an octave up.
- **`mouth`** (hums): the two resonances that give the hum its vowel, in Hz. The default, `[320, 1100]`, is
  closed and nasal; `[520, 950]` is an open "uh".
- **`voice`, `rate`, `pitch`, `formants`** (spoken lines): a voice from `say -v '?'`, its speed in words a
  minute, and two scales for the voice. `pitch` under 1 makes it deeper and `formants` under 1 makes it
  bigger. If the voice isn't installed, the system's voice says the line.

### Limits

cueback keeps the trackpad's motor from working hard, and a theme can't change that:

- A cue is cut off at 1.2 seconds, and 150 ms of quiet follows it.
- At most 30 cues play in a minute, and while one plays only one more can wait.
- Nothing is stronger than the motor's normal maximum: `volume` and `level` only turn it down.

Taps, tones and slides cost the motor a handful of commands. Hums, noise and spoken lines cost about a hundred a
second, so keep them short and on cues that don't come often. The daemon writes any command the motor refuses to
`~/Library/Logs/cueback.log`. If you see one after trying a theme, make that cue shorter or simpler.

The built-in themes are in [Sources/cueback/Theme.swift](Sources/cueback/Theme.swift), in the same format.

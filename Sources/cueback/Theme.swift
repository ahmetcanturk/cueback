import Foundation

/// One step of a cue: a tap, a tone (by note name or Hz), a pause, a hum, noise, a slide, a spoken line or a
/// sound file.
struct Step: Codable {
    var tap: Double?      // a felt tap, strength 0…1
    var note: String?     // a tone by note name, like "A6"
    var hz: Double?       // …or by frequency, 80 to 4000 Hz (below ~200 Hz it's felt more than heard)
    var ms: Double?       // a tone's length (default 120)
    var level: Double?    // a tone's strength, 0…1 (default 0.8)
    var shape: String?    // a tone's shape: "plain", "bell" (strike and fade) or "swell"; default: the theme's
    var wait: Double?     // a pause, in ms
    var say: String?      // a short line the trackpad speaks, in macOS's `voice` at `rate` words a minute
    var voice: String?
    var rate: Double?
    var pitch: Double?    // scales the voice's pitch (under 1: deeper)
    var formants: Double? // scales its resonances (under 1: a bigger voice)
    var ring: Double?     // a tone's glassy second tone, as a multiple of its pitch (2 is an octave up)
    var hum: [Double]?    // a voice-like "hmm" whose pitch moves through these (Hz) over `ms`
    var mouth: [Double]?  // the hum's two resonances (Hz): closed and nasal by default; [520, 950] is an open "uh"
    var hiss: [Double]?   // noise between these two frequencies for `ms`: a hiss up high, a crunch down low
    var rise: Bool?       // a hiss that grows
    var glide: [Double]?  // a tone that slides from the first pitch to the second over `ms`: a pop
    var sound: String?    // an audio file, played through the trackpad: a full path, "~/…" or a name in the themes folder
}

/// A set of cues. Only the ones named in `enabled` play for Claude Code's events; any of them plays as a preview.
struct Theme: Codable {
    var name: String
    var about: String?
    var volume: Double?          // 0…100 (default 100)
    var subagentLevel: Double?   // cues from inside a subagent play at this share of their strength (default 0.6)
    var soft: Bool?              // true: low tones swell like a breath and notes ring and fade like bells
    var enabled: [String]
    var cues: [String: [Step]]

    /// A theme from a JSON file.
    static func load(path: String) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// The themes cueback comes with, numbered in this order.
    static let builtInIDs = ["classic", "mochi", "warhorn", "blocky", "owlpost", "r2d2"]

    /// The theme a new install starts with.
    static let defaultID = "classic"

    static func builtIn(_ id: String) -> Theme? {
        let json: String
        switch id {
        case "classic": json = classic
        case "mochi": json = mochi
        case "warhorn": json = warhorn
        case "blocky": json = blocky
        case "owlpost": json = owlpost
        case "r2d2": json = r2d2
        default: return nil
        }
        return try? JSONDecoder().decode(Theme.self, from: Data(json.utf8))
    }

    /// Your own themes: every .json file in ~/Library/Application Support/cueback/themes, named by its file.
    static var userDirectory: URL { Socket.directory.appendingPathComponent("themes", isDirectory: true) }

    static func userThemes() -> [(id: String, theme: Theme)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil)) ?? []
        var found: [(id: String, theme: Theme)] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension.lowercased() == "json" {
            let id = url.deletingPathExtension().lastPathComponent.lowercased()
            if builtInIDs.contains(id) || id == "custom" { continue }   // those names are taken
            if let theme = try? load(path: url.path) { found.append((id, theme)) }
        }
        return found
    }

    /// Every theme, in the order they're numbered: the built-in ones, then your own.
    static func all() -> [(id: String, theme: Theme)] {
        var everything: [(id: String, theme: Theme)] = []
        for id in builtInIDs {
            if let theme = builtIn(id) { everything.append((id, theme)) }
        }
        return everything + userThemes()
    }

    /// A theme's id from its id, its number ("2" is "mochi") or what people call it.
    static func id(matching text: String) -> String? {
        let key = text.lowercased()
        let everything = all()
        if let n = Int(key), everything.indices.contains(n - 1) { return everything[n - 1].id }
        let nicknames = ["klasik": "classic", "warcraft": "warhorn", "wc": "warhorn", "minecraft": "blocky", "mc": "blocky",
                         "harrypotter": "owlpost", "potter": "owlpost", "hp": "owlpost", "hogwarts": "owlpost",
                         "starwars": "r2d2", "sw": "r2d2", "r2-d2": "r2d2", "r2": "r2d2", "droid": "r2d2", "astromech": "r2d2"]
        let id = nicknames[key] ?? key
        return everything.contains(where: { $0.id == id }) ? id : nil
    }

    /// 1 · Classic: firm taps and clear notes. The cues that need you are on, and so are the subagents' soft ticks.
    static let classic = """
    {
      "name": "Classic",
      "about": "Firm taps and clear notes.",
      "volume": 50,
      "subagentLevel": 0.6,
      "enabled": ["permission", "waiting", "input", "done", "error", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"tap": 0.6}, {"wait": 120}, {"tap": 0.8}, {"wait": 120}, {"tap": 1.0}],
        "waiting":        [{"tap": 0.45}, {"wait": 220}, {"tap": 0.45}],
        "input":          [{"tap": 0.5}, {"wait": 200}, {"tap": 0.8}],
        "done":           [{"note": "E6", "ms": 90, "level": 0.75}, {"wait": 20}, {"note": "A6", "ms": 170, "level": 0.9}],
        "error":          [{"tap": 0.8}, {"wait": 140}, {"hz": 165, "ms": 200, "level": 0.85}],
        "subagent-start": [{"tap": 0.3}],
        "subagent-stop":  [{"tap": 0.3}, {"wait": 170}, {"tap": 0.3}],
        "task-done":      [{"note": "C7", "ms": 70, "level": 0.6}],
        "tool-failed":    [{"tap": 0.25}],
        "compact":        [{"note": "A5", "ms": 110, "level": 0.4}, {"note": "E6", "ms": 110, "level": 0.45}, {"note": "A6", "ms": 150, "level": 0.5}],
        "session-start":  [{"note": "A5", "ms": 80, "level": 0.6}, {"note": "E6", "ms": 140, "level": 0.7}],
        "session-end":    [{"note": "E6", "ms": 80, "level": 0.6}, {"note": "A5", "ms": 140, "level": 0.6}],
        "installed":      [{"tap": 0.5}, {"wait": 120}, {"tap": 0.7}, {"wait": 160}, {"note": "E6", "ms": 80, "level": 0.7}, {"note": "A6", "ms": 80, "level": 0.8}, {"note": "E7", "ms": 220, "level": 0.9}],
        "fanfare":        [{"note": "A5", "ms": 80, "level": 0.7}, {"note": "C#6", "ms": 80, "level": 0.75}, {"note": "E6", "ms": 80, "level": 0.8}, {"note": "A6", "ms": 260, "level": 0.95}],
        "level":          [{"tap": 0.9}],
        "prompt":         [{"tap": 0.35}]
      }
    }
    """

    /// 2 · Mochi: calm and sweet. Slow, soft pulses you feel under your finger (around 110 Hz, swelling like a
    /// breath) and quiet music-box notes from the middle of the motor's range that ring and fade. Gentler
    /// strengths than Classic, and nothing sharp.
    static let mochi = """
    {
      "name": "Mochi",
      "about": "Calm and sweet: soft pulses you feel, and quiet music-box notes.",
      "volume": 50,
      "subagentLevel": 0.7,
      "soft": true,
      "enabled": ["permission", "waiting", "input", "done", "error", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"hz": 110, "ms": 90, "level": 0.55}, {"wait": 170}, {"hz": 110, "ms": 90, "level": 0.6}, {"wait": 200}, {"note": "G5", "ms": 120, "level": 0.45}, {"wait": 30}, {"note": "C6", "ms": 180, "level": 0.5}],
        "waiting":        [{"hz": 100, "ms": 90, "level": 0.45}, {"wait": 50}, {"hz": 100, "ms": 90, "level": 0.6}, {"wait": 50}, {"hz": 100, "ms": 90, "level": 0.6}, {"wait": 50}, {"hz": 100, "ms": 90, "level": 0.45}, {"wait": 120}, {"note": "G5", "ms": 200, "level": 0.42}],
        "input":          [{"note": "A5", "ms": 120, "level": 0.42}, {"wait": 40}, {"note": "D6", "ms": 180, "level": 0.46}],
        "done":           [{"note": "E6", "ms": 150, "level": 0.46}, {"wait": 60}, {"note": "C6", "ms": 240, "level": 0.5}],
        "error":          [{"hz": 110, "ms": 90, "level": 0.6}, {"wait": 60}, {"note": "E5", "ms": 140, "level": 0.5, "shape": "bell"}, {"wait": 50}, {"note": "B4", "ms": 260, "level": 0.5, "shape": "bell"}],
        "subagent-start": [{"hz": 110, "ms": 90, "level": 0.45}, {"wait": 60}, {"note": "A5", "ms": 110, "level": 0.36}],
        "subagent-stop":  [{"note": "A5", "ms": 110, "level": 0.36}, {"wait": 60}, {"hz": 110, "ms": 90, "level": 0.42}],
        "task-done":      [{"note": "C6", "ms": 160, "level": 0.4}],
        "tool-failed":    [{"hz": 110, "ms": 90, "level": 0.32}],
        "compact":        [{"hz": 294, "ms": 130, "level": 0.28}, {"wait": 40}, {"hz": 247, "ms": 130, "level": 0.26}, {"wait": 40}, {"hz": 196, "ms": 200, "level": 0.24}],
        "session-start":  [{"note": "C6", "ms": 100, "level": 0.38}, {"wait": 40}, {"note": "D6", "ms": 100, "level": 0.4}, {"wait": 40}, {"note": "E6", "ms": 180, "level": 0.42}],
        "session-end":    [{"note": "E6", "ms": 100, "level": 0.4}, {"wait": 40}, {"note": "D6", "ms": 100, "level": 0.38}, {"wait": 40}, {"note": "C6", "ms": 200, "level": 0.38}],
        "installed":      [{"hz": 110, "ms": 90, "level": 0.5}, {"wait": 130}, {"hz": 110, "ms": 90, "level": 0.5}, {"wait": 180}, {"note": "G5", "ms": 100, "level": 0.42}, {"wait": 30}, {"note": "C6", "ms": 100, "level": 0.44}, {"wait": 30}, {"note": "E6", "ms": 100, "level": 0.46}, {"wait": 30}, {"note": "C6", "ms": 200, "level": 0.46}],
        "fanfare":        [{"note": "C6", "ms": 100, "level": 0.4}, {"wait": 30}, {"note": "E6", "ms": 100, "level": 0.42}, {"wait": 30}, {"note": "G6", "ms": 100, "level": 0.44}, {"wait": 30}, {"note": "E6", "ms": 100, "level": 0.42}, {"wait": 30}, {"note": "C6", "ms": 240, "level": 0.46}],
        "level":          [{"hz": 110, "ms": 90, "level": 0.8}],
        "prompt":         [{"hz": 110, "ms": 90, "level": 0.35}]
      }
    }
    """

    /// 3 · Warhorn: heavy and slow, an homage to orc-and-human strategy games, with patterns of its own (no game's
    /// sounds or music). Deep war drums (95 Hz, struck and fading), a horn that swells up a fifth when you're
    /// needed, and a gruff worker who talks back through the trackpad: short lines said by macOS's own voice,
    /// lowered in pitch, when you give an order, when the job is done and for the subagents. No recording from
    /// any game is used.
    static let warhorn = """
    {
      "name": "Warhorn",
      "about": "War drums, a horn call and a gruff worker who talks back.",
      "volume": 50,
      "subagentLevel": 0.65,
      "soft": true,
      "enabled": ["prompt", "permission", "waiting", "input", "done", "error", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"hz": 95, "ms": 110, "level": 0.85, "shape": "bell"}, {"wait": 130}, {"hz": 196, "ms": 220, "level": 0.6}, {"hz": 294, "ms": 360, "level": 0.72}],
        "waiting":        [{"hz": 95, "ms": 110, "level": 0.55, "shape": "bell"}, {"wait": 260}, {"hz": 95, "ms": 110, "level": 0.38, "shape": "bell"}, {"wait": 110}, {"hz": 95, "ms": 110, "level": 0.38, "shape": "bell"}],
        "input":          [{"hz": 294, "ms": 200, "level": 0.6}, {"wait": 90}, {"hz": 95, "ms": 110, "level": 0.55, "shape": "bell"}],
        "prompt":         [{"hz": 170, "ms": 50, "level": 0.7, "shape": "plain"}, {"hz": 150, "ms": 90, "level": 0.7, "shape": "bell"}, {"wait": 90}, {"hz": 160, "ms": 50, "level": 0.7, "shape": "plain"}, {"hz": 135, "ms": 110, "level": 0.7, "shape": "bell"}],
        "done":           [{"say": "Job's done!", "voice": "Ralph", "rate": 150, "pitch": 0.75, "formants": 0.9, "level": 0.95}],
        "error":          [{"hz": 95, "ms": 110, "level": 0.9, "shape": "bell"}, {"wait": 60}, {"hz": 220, "ms": 170, "level": 0.6}, {"hz": 185, "ms": 170, "level": 0.55}, {"hz": 147, "ms": 300, "level": 0.5}],
        "subagent-start": [{"say": "Zug zug.", "voice": "Ralph", "rate": 150, "pitch": 0.75, "formants": 0.9, "level": 0.75}],
        "subagent-stop":  [{"say": "Work complete.", "voice": "Ralph", "rate": 150, "pitch": 0.75, "formants": 0.9, "level": 0.75}],
        "task-done":      [{"tap": 0.7}, {"note": "E7", "ms": 60, "level": 0.45, "shape": "bell"}, {"wait": 110}, {"tap": 0.9}, {"note": "A7", "ms": 90, "level": 0.5, "shape": "bell"}],
        "tool-failed":    [{"hz": 95, "ms": 110, "level": 0.4, "shape": "bell"}],
        "compact":        [{"hz": 95, "ms": 110, "level": 0.6, "shape": "bell"}, {"wait": 120}, {"hz": 95, "ms": 110, "level": 0.45, "shape": "bell"}, {"wait": 120}, {"hz": 95, "ms": 110, "level": 0.32, "shape": "bell"}, {"wait": 120}, {"hz": 95, "ms": 110, "level": 0.22, "shape": "bell"}],
        "session-start":  [{"hz": 196, "ms": 180, "level": 0.55}, {"hz": 294, "ms": 260, "level": 0.65}, {"wait": 60}, {"hz": 95, "ms": 110, "level": 0.7, "shape": "bell"}],
        "session-end":    [{"hz": 294, "ms": 200, "level": 0.55}, {"hz": 196, "ms": 320, "level": 0.5}],
        "installed":      [{"hz": 95, "ms": 110, "level": 0.85, "shape": "bell"}, {"wait": 140}, {"hz": 95, "ms": 110, "level": 0.5, "shape": "bell"}, {"wait": 80}, {"hz": 95, "ms": 110, "level": 0.5, "shape": "bell"}, {"wait": 150}, {"hz": 196, "ms": 180, "level": 0.6}, {"hz": 294, "ms": 280, "level": 0.72}],
        "fanfare":        [{"hz": 196, "ms": 160, "level": 0.6}, {"hz": 294, "ms": 160, "level": 0.66}, {"hz": 392, "ms": 300, "level": 0.72}, {"wait": 60}, {"hz": 95, "ms": 130, "level": 0.9, "shape": "bell"}],
        "level":          [{"hz": 95, "ms": 110, "level": 0.9, "shape": "bell"}]
      }
    }
    """

    /// 4 · Blocky: an homage to block-building games, made of synthesized sounds of its own (no game's audio). A
    /// nasal, questioning "hrmm?" when you're needed, a fuse that hisses and goes off when something fails,
    /// tinkling orbs and a rising chime when the work is done, three crunches of digging when a subagent
    /// starts, a crunch and a pop when it's finished, and a short hurt "uh!" when a tool call fails.
    static let blocky = """
    {
      "name": "Blocky",
      "about": "A humming hrmm, a hissing fuse, digging, pops and tinkling orbs.",
      "volume": 50,
      "subagentLevel": 0.7,
      "soft": true,
      "enabled": ["permission", "waiting", "input", "done", "error", "tool-failed", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"hum": [125, 112], "ms": 180, "level": 0.6}, {"wait": 110}, {"hum": [112, 104, 150], "ms": 380, "level": 0.7}],
        "waiting":        [{"hum": [120, 104, 100], "ms": 520, "level": 0.5}],
        "input":          [{"hum": [110, 160], "ms": 260, "level": 0.65}],
        "done":           [{"note": "A6", "ms": 70, "level": 0.42, "ring": 2}, {"wait": 60}, {"note": "F#6", "ms": 70, "level": 0.42, "ring": 2}, {"wait": 50}, {"note": "B6", "ms": 70, "level": 0.44, "ring": 2}, {"wait": 120}, {"note": "C6", "ms": 60, "level": 0.4}, {"note": "E6", "ms": 60, "level": 0.42}, {"note": "G6", "ms": 60, "level": 0.44}, {"note": "C7", "ms": 200, "level": 0.5}],
        "error":          [{"hiss": [2600, 4000], "ms": 520, "level": 0.5, "rise": true}, {"wait": 40}, {"tap": 1.0}, {"hz": 90, "ms": 180, "level": 1.0, "shape": "bell"}],
        "subagent-start": [{"hiss": [250, 800], "ms": 40, "level": 0.65}, {"wait": 150}, {"hiss": [250, 800], "ms": 40, "level": 0.65}, {"wait": 150}, {"hiss": [250, 800], "ms": 40, "level": 0.65}],
        "subagent-stop":  [{"hiss": [250, 800], "ms": 50, "level": 0.7}, {"wait": 90}, {"glide": [520, 1700], "ms": 60, "level": 0.5}],
        "task-done":      [{"note": "A6", "ms": 80, "level": 0.42, "ring": 2}],
        "tool-failed":    [{"hum": [185, 115], "ms": 170, "level": 0.85, "mouth": [520, 950]}, {"hiss": [1800, 3500], "ms": 50, "level": 0.22}],
        "compact":        [{"note": "E6", "ms": 160, "level": 0.36}, {"wait": 80}, {"note": "C6", "ms": 160, "level": 0.34}, {"wait": 80}, {"note": "A5", "ms": 260, "level": 0.32}],
        "session-start":  [{"tap": 0.5}, {"hz": 150, "ms": 45, "level": 0.5, "shape": "bell"}, {"wait": 120}, {"glide": [520, 1700], "ms": 60, "level": 0.5}, {"wait": 120}, {"note": "G6", "ms": 200, "level": 0.42}],
        "session-end":    [{"note": "G6", "ms": 160, "level": 0.4}, {"wait": 80}, {"note": "E6", "ms": 260, "level": 0.38}],
        "installed":      [{"tap": 0.55}, {"hz": 150, "ms": 45, "level": 0.55, "shape": "bell"}, {"wait": 120}, {"tap": 0.55}, {"hz": 150, "ms": 45, "level": 0.55, "shape": "bell"}, {"wait": 140}, {"glide": [520, 1700], "ms": 60, "level": 0.5}, {"wait": 130}, {"note": "C6", "ms": 60, "level": 0.4}, {"note": "E6", "ms": 60, "level": 0.42}, {"note": "G6", "ms": 60, "level": 0.44}, {"note": "C7", "ms": 200, "level": 0.5}],
        "fanfare":        [{"note": "G5", "ms": 150, "level": 0.42}, {"wait": 40}, {"note": "B5", "ms": 150, "level": 0.42}, {"wait": 40}, {"note": "D6", "ms": 150, "level": 0.44}, {"wait": 40}, {"note": "A5", "ms": 300, "level": 0.44}],
        "level":          [{"tap": 0.8}, {"hz": 150, "ms": 45, "level": 0.8, "shape": "bell"}],
        "prompt":         [{"tap": 0.4}, {"hz": 150, "ms": 45, "level": 0.4, "shape": "bell"}]
      }
    }
    """

    /// 5 · Owlpost: an homage to stories about a school of wizards, made of sounds of its own (no film's music or
    /// audio). An owl hoots when you're needed (low, breathy tones around 400 Hz), glassy celesta notes ring an
    /// octave above themselves, a quill scratches when you're asked for input, a spell fizzles out when the turn
    /// fails, and a British voice says a short spell when the work is done and for the subagents. The lines are
    /// said by macOS's own voice; no recording is used.
    static let owlpost = """
    {
      "name": "Owlpost",
      "about": "An owl's hoot, glassy celesta notes, a scratching quill and spoken spells.",
      "volume": 50,
      "subagentLevel": 0.7,
      "soft": true,
      "enabled": ["permission", "waiting", "input", "done", "error", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"hz": 392, "ms": 170, "level": 0.75}, {"wait": 100}, {"hz": 392, "ms": 110, "level": 0.7}, {"wait": 50}, {"hz": 440, "ms": 240, "level": 0.8}, {"wait": 110}, {"note": "D6", "ms": 160, "level": 0.46, "ring": 2}],
        "waiting":        [{"hz": 392, "ms": 260, "level": 0.6}, {"wait": 220}, {"hz": 349, "ms": 340, "level": 0.55}, {"wait": 100}, {"note": "A5", "ms": 180, "level": 0.4, "ring": 2}],
        "input":          [{"hiss": [1500, 3200], "ms": 60, "level": 0.4}, {"wait": 50}, {"hiss": [1500, 3200], "ms": 90, "level": 0.4}, {"wait": 90}, {"note": "D6", "ms": 100, "level": 0.44, "ring": 2}, {"wait": 30}, {"note": "A6", "ms": 180, "level": 0.48, "ring": 2}],
        "done":           [{"say": "Mischief managed.", "voice": "Daniel", "rate": 170, "level": 0.95}],
        "error":          [{"glide": [1600, 400], "ms": 160, "level": 0.6}, {"wait": 40}, {"hiss": [900, 2400], "ms": 70, "level": 0.5}, {"wait": 50}, {"hiss": [700, 1800], "ms": 60, "level": 0.35}, {"wait": 70}, {"hz": 110, "ms": 140, "level": 0.8, "shape": "bell"}],
        "subagent-start": [{"say": "Lumos!", "voice": "Daniel", "rate": 170, "level": 0.75}],
        "subagent-stop":  [{"say": "Nox.", "voice": "Daniel", "rate": 170, "level": 0.75}],
        "task-done":      [{"note": "A6", "ms": 70, "level": 0.42, "ring": 2}, {"wait": 40}, {"note": "E7", "ms": 110, "level": 0.44, "ring": 2}],
        "tool-failed":    [{"hiss": [900, 2400], "ms": 60, "level": 0.35}],
        "compact":        [{"hiss": [400, 1500], "ms": 90, "level": 0.45}, {"wait": 110}, {"hiss": [400, 1500], "ms": 90, "level": 0.36}, {"wait": 110}, {"hiss": [400, 1500], "ms": 90, "level": 0.28}],
        "session-start":  [{"note": "A5", "ms": 110, "level": 0.4, "ring": 2}, {"wait": 40}, {"note": "C6", "ms": 110, "level": 0.42, "ring": 2}, {"wait": 40}, {"note": "E6", "ms": 110, "level": 0.44, "ring": 2}, {"wait": 40}, {"note": "A6", "ms": 220, "level": 0.46, "ring": 2}],
        "session-end":    [{"note": "A6", "ms": 110, "level": 0.44, "ring": 2}, {"wait": 40}, {"note": "E6", "ms": 110, "level": 0.42, "ring": 2}, {"wait": 40}, {"note": "C6", "ms": 110, "level": 0.4, "ring": 2}, {"wait": 40}, {"note": "A5", "ms": 240, "level": 0.4, "ring": 2}],
        "installed":      [{"hz": 392, "ms": 170, "level": 0.75}, {"wait": 100}, {"hz": 440, "ms": 220, "level": 0.8}, {"wait": 130}, {"note": "A5", "ms": 90, "level": 0.42, "ring": 2}, {"wait": 30}, {"note": "C6", "ms": 90, "level": 0.44, "ring": 2}, {"wait": 30}, {"note": "E6", "ms": 90, "level": 0.46, "ring": 2}, {"wait": 30}, {"note": "A6", "ms": 200, "level": 0.48, "ring": 2}],
        "fanfare":        [{"note": "D6", "ms": 110, "level": 0.42, "ring": 2}, {"wait": 30}, {"note": "F6", "ms": 110, "level": 0.44, "ring": 2}, {"wait": 30}, {"note": "A6", "ms": 110, "level": 0.46, "ring": 2}, {"wait": 60}, {"glide": [900, 2600], "ms": 80, "level": 0.45}, {"wait": 40}, {"note": "D7", "ms": 260, "level": 0.5, "ring": 2}],
        "level":          [{"tap": 0.8}, {"note": "A6", "ms": 90, "level": 0.6, "ring": 2}],
        "prompt":         [{"glide": [700, 1900], "ms": 70, "level": 0.45}]
      }
    }
    """

    /// 6 · R2-D2: an homage to the small droid of the space films, made of synthesized sounds of its own (no
    /// film's audio or music). Its chirps bend instead of holding a pitch, and it trills between two pitches
    /// when it chatters. A curious coo that slides up when you send a prompt, a long rising whistle when it asks
    /// you something, a two-step whistle up when the work is done, a wavering wail and a low blat when the turn
    /// fails, and a sigh and a long falling moan when it has waited for you. Nothing is spoken.
    static let r2d2 = """
    {
      "name": "R2-D2",
      "about": "A little droid's chatter: bent chirps and trills, rising whistles and a wavering wail.",
      "volume": 50,
      "subagentLevel": 0.7,
      "enabled": ["prompt", "permission", "waiting", "input", "done", "error", "subagent-start", "subagent-stop"],
      "cues": {
        "permission":     [{"glide": [1700, 2300], "ms": 50, "level": 0.55}, {"glide": [2300, 1500], "ms": 50, "level": 0.55}, {"wait": 30}, {"hz": 2000, "ms": 30, "level": 0.5}, {"hz": 2600, "ms": 30, "level": 0.5}, {"hz": 2000, "ms": 30, "level": 0.5}, {"hz": 2600, "ms": 30, "level": 0.5}, {"wait": 50}, {"glide": [1300, 3000], "ms": 220, "level": 0.6}],
        "waiting":        [{"glide": [1900, 1500], "ms": 140, "level": 0.5}, {"wait": 60}, {"glide": [1600, 700], "ms": 480, "level": 0.55}, {"wait": 120}, {"glide": [900, 650], "ms": 200, "level": 0.4}],
        "input":          [{"glide": [1500, 1900], "ms": 60, "level": 0.55}, {"wait": 40}, {"glide": [1700, 2900], "ms": 160, "level": 0.58}, {"wait": 40}, {"hz": 2400, "ms": 30, "level": 0.5}, {"hz": 2900, "ms": 30, "level": 0.5}, {"hz": 2400, "ms": 30, "level": 0.5}],
        "done":           [{"hz": 1800, "ms": 30, "level": 0.5}, {"hz": 2400, "ms": 30, "level": 0.5}, {"hz": 1800, "ms": 30, "level": 0.5}, {"hz": 2400, "ms": 30, "level": 0.5}, {"hz": 2900, "ms": 40, "level": 0.5}, {"wait": 50}, {"glide": [1600, 2600], "ms": 110, "level": 0.6}, {"wait": 40}, {"glide": [2200, 3600], "ms": 200, "level": 0.65}],
        "error":          [{"hz": 3000, "ms": 30, "level": 0.55}, {"hz": 3400, "ms": 30, "level": 0.55}, {"hz": 3000, "ms": 30, "level": 0.55}, {"hz": 3400, "ms": 30, "level": 0.55}, {"wait": 20}, {"glide": [3400, 2400], "ms": 140, "level": 0.7}, {"glide": [2700, 1700], "ms": 140, "level": 0.68}, {"glide": [2000, 1000], "ms": 160, "level": 0.65}, {"glide": [1200, 500], "ms": 160, "level": 0.6}, {"wait": 40}, {"hz": 170, "ms": 160, "level": 0.85}],
        "subagent-start": [{"glide": [1600, 2400], "ms": 50, "level": 0.48}, {"wait": 30}, {"hz": 2000, "ms": 45, "level": 0.45}],
        "subagent-stop":  [{"hz": 2000, "ms": 45, "level": 0.45}, {"wait": 30}, {"glide": [2400, 1600], "ms": 60, "level": 0.48}],
        "task-done":      [{"glide": [1800, 3000], "ms": 70, "level": 0.5}],
        "tool-failed":    [{"glide": [900, 500], "ms": 90, "level": 0.5}],
        "compact":        [{"hz": 2200, "ms": 60, "level": 0.45}, {"wait": 70}, {"hz": 1700, "ms": 60, "level": 0.42}, {"wait": 100}, {"hz": 1300, "ms": 60, "level": 0.38}, {"wait": 140}, {"glide": [1100, 600], "ms": 220, "level": 0.45}],
        "session-start":  [{"glide": [500, 2200], "ms": 260, "level": 0.55}, {"wait": 70}, {"hz": 2200, "ms": 45, "level": 0.5}, {"wait": 35}, {"hz": 2700, "ms": 45, "level": 0.5}, {"wait": 35}, {"hz": 2000, "ms": 70, "level": 0.5}],
        "session-end":    [{"hz": 2000, "ms": 50, "level": 0.48}, {"wait": 40}, {"hz": 1600, "ms": 50, "level": 0.46}, {"wait": 70}, {"glide": [1800, 400], "ms": 340, "level": 0.55}],
        "installed":      [{"glide": [500, 2200], "ms": 240, "level": 0.55}, {"wait": 60}, {"hz": 1800, "ms": 30, "level": 0.5}, {"hz": 2400, "ms": 30, "level": 0.5}, {"hz": 1800, "ms": 30, "level": 0.5}, {"hz": 2400, "ms": 30, "level": 0.5}, {"wait": 50}, {"glide": [1600, 2600], "ms": 110, "level": 0.6}, {"wait": 40}, {"glide": [2200, 3600], "ms": 200, "level": 0.65}],
        "fanfare":        [{"hz": 2000, "ms": 30, "level": 0.5}, {"hz": 2600, "ms": 30, "level": 0.5}, {"hz": 2000, "ms": 30, "level": 0.5}, {"hz": 2600, "ms": 30, "level": 0.5}, {"glide": [2600, 1800], "ms": 60, "level": 0.55}, {"wait": 40}, {"glide": [1500, 2700], "ms": 120, "level": 0.6}, {"wait": 40}, {"glide": [2200, 3600], "ms": 180, "level": 0.65}, {"wait": 30}, {"hz": 3200, "ms": 30, "level": 0.55}, {"hz": 3600, "ms": 30, "level": 0.55}, {"hz": 3200, "ms": 30, "level": 0.55}, {"hz": 3600, "ms": 30, "level": 0.55}],
        "level":          [{"hz": 2200, "ms": 60, "level": 0.8}],
        "prompt":         [{"glide": [1100, 1400], "ms": 90, "level": 0.48}, {"glide": [1400, 1250], "ms": 50, "level": 0.46}, {"glide": [1250, 2500], "ms": 210, "level": 0.58}, {"wait": 30}, {"glide": [2500, 2950], "ms": 55, "level": 0.52}]
      }
    }
    """
}

/// Every cue cueback knows, and what triggers it.
let cueEvents: [(cue: String, event: String)] = [
    ("prompt", "UserPromptSubmit: you sent Claude a prompt"),
    ("permission", "PermissionRequest: Claude asks for permission"),
    ("waiting", "Notification (idle_prompt): Claude has been waiting for you for about a minute"),
    ("input", "Elicitation: an MCP server asks you for input"),
    ("done", "Stop: Claude finished"),
    ("error", "StopFailure: the turn ended on an API error"),
    ("subagent-start", "SubagentStart: a subagent started"),
    ("subagent-stop", "SubagentStop: a subagent finished"),
    ("task-done", "TaskCompleted: a task was marked complete"),
    ("tool-failed", "PostToolUseFailure: a tool call failed"),
    ("compact", "PreCompact: the conversation is about to be compacted"),
    ("session-start", "SessionStart (startup): a new session"),
    ("session-end", "SessionEnd: the session ended"),
    ("installed", "when cueback is installed, and when you switch to the theme"),
    ("fanfare", "the end of `cueback demo`"),
    ("level", "one tap at the new volume, when you set it in the menu bar"),
]

/// `cueback cues`: every cue, whether the theme in use plays it for Claude Code, and what triggers it.
func printCues() {
    let wanted = Config.load().theme ?? Theme.defaultID
    let theme = Theme.all().first(where: { $0.id == wanted })?.theme ?? Theme.builtIn(Theme.defaultID)
    print("  the theme in use: \(theme?.name ?? "?")")
    print("  cue             plays  event")
    for (cue, event) in cueEvents {
        let plays = theme?.enabled.contains(cue) == true ? "yes" : "no "
        print("  " + cue.padding(toLength: 16, withPad: " ", startingAt: 0) + plays + "    " + event)
    }
}

/// `cueback theme`: lists the themes, or switches to one (by name or number) and plays its `installed` cue.
func runTheme(_ choice: String?) {
    let everything = Theme.all()
    guard let choice else {
        let current = Config.load().theme ?? Theme.defaultID
        let width = everything.map { $0.theme.name.count }.max() ?? 0   // the longest name, so none is cut short
        for (i, entry) in everything.enumerated() {
            let name = entry.theme.name.padding(toLength: width, withPad: " ", startingAt: 0)
            print("  \(entry.id == current ? "▸" : " ") \(i + 1) · \(name) \(entry.theme.about ?? "")")
        }
        return
    }
    guard let id = Theme.id(matching: choice), let index = everything.firstIndex(where: { $0.id == id }) else {
        fail("There's no theme called \"\(choice)\". See: cueback theme")
    }
    var config = Config.load()
    config.theme = id
    config.save()
    if Socket.send("reload") { Socket.send("play installed") }
    print("Theme: \(index + 1) · \(everything[index].theme.name)")
}

/// `cueback check <file>`: reads a theme file and says what's in it, and what looks wrong.
func runCheck(_ path: String?) {
    guard let path else { fail("Which theme file? Like: cueback check my-theme.json") }
    let theme: Theme
    do { theme = try Theme.load(path: path) } catch { fail("cueback can't read that as a theme: \(error)") }
    print("\(theme.name)" + (theme.about.map { " · " + $0 } ?? ""))
    let known = cueEvents.map { $0.cue }
    var problems: [String] = []
    for cue in known {
        guard let steps = theme.cues[cue] else { continue }
        var ms = 0.0, voiced = false, empty = 0
        for step in steps {
            if step.say != nil { voiced = true; ms += 700 }   // a short line is about this long
            else if let file = step.sound {
                voiced = true
                // In the themes folder, or still next to a theme file that hasn't been put there yet.
                let beside = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(file)
                if let seconds = Sound.seconds(of: Sound.url(for: file)) ?? Sound.seconds(of: beside) {
                    ms += min(seconds, Limits.maxCueSeconds) * 1000
                } else {
                    problems.append("\(cue): the sound file \"\(file)\" isn't there or isn't audio (looked in \(Theme.userDirectory.path))")
                }
            }
            else if step.hum != nil { voiced = true; ms += step.ms ?? 300 }
            else if step.hiss != nil { voiced = true; ms += step.ms ?? 200 }
            else if step.glide != nil { ms += step.ms ?? 60 }
            else if step.tap != nil { ms += Motor.tapSeconds * 1000 }
            else if step.hz != nil || step.note != nil { ms += step.ms ?? 120 }
            else if let wait = step.wait { ms += wait }
            else { empty += 1 }
        }
        let plays = theme.enabled.contains(cue) ? "plays" : "off  "
        print("  \(plays)  " + cue.padding(toLength: 16, withPad: " ", startingAt: 0) + "\(steps.count) step\(steps.count == 1 ? "" : "s"), about \(Int(ms)) ms")
        if ms > Limits.maxCueSeconds * 1000 { problems.append("\(cue) is longer than \(Int(Limits.maxCueSeconds * 1000)) ms, so its end is cut off") }
        if voiced && theme.enabled.contains(cue) { problems.append("\(cue) hums, hisses, speaks or plays a file: about a hundred motor commands a second, so keep it for a cue that's rare") }
        if empty > 0 { problems.append("\(cue) has \(empty) step\(empty == 1 ? "" : "s") with nothing in \(empty == 1 ? "it" : "them") that cueback knows") }
        for step in steps {
            if let note = step.note, frequency(ofNote: note) == nil { problems.append("\(cue): \"\(note)\" isn't a note (write it like A6 or C#5)") }
        }
    }
    for cue in theme.cues.keys.sorted() where !known.contains(cue) {
        problems.append("\(cue): cueback has no cue by this name, so nothing plays it")
    }
    for cue in theme.enabled where theme.cues[cue] == nil {
        problems.append("\(cue) is in \"enabled\" but has no steps")
    }
    print(problems.isEmpty ? "\nNothing looks wrong." : "\nWorth a look:")
    for problem in problems { print("  - " + problem) }
}

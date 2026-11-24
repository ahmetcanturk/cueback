import Foundation

/// One step of a cue: a tap, a tone (by note name or Hz) or a pause.
struct Step: Codable {
    var tap: Double?      // a felt tap, strength 0…1
    var note: String?     // a tone by note name, like "A6"
    var hz: Double?       // …or by frequency, 80 to 4000 Hz
    var ms: Double?       // a tone's length (default 120)
    var level: Double?    // a tone's strength, 0…1 (default 0.8)
    var wait: Double?     // a pause, in ms
}

/// A set of cues. Only the ones named in `enabled` play.
struct Theme: Codable {
    var name: String
    var volume: Double?   // 0…100 (default 100)
    var enabled: [String]
    var cues: [String: [Step]]

    static func load(path: String?) throws -> Theme {
        let data = try path.map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? Data(builtIn.utf8)
        return try JSONDecoder().decode(Theme.self, from: data)
    }

    /// The default theme: short, quiet, and only the five cues that need you are on.
    static let builtIn = """
    {
      "name": "Default",
      "volume": 70,
      "enabled": ["permission", "waiting", "input", "done", "error"],
      "cues": {
        "permission":     [{"tap": 0.35}, {"wait": 110}, {"tap": 0.65}, {"wait": 110}, {"tap": 1.0}],
        "waiting":        [{"tap": 0.45}, {"wait": 140}, {"tap": 0.45}],
        "input":          [{"tap": 0.5}, {"wait": 120}, {"tap": 0.8}],
        "done":           [{"note": "E6", "ms": 90, "level": 0.75}, {"wait": 20}, {"note": "A6", "ms": 170, "level": 0.9}],
        "error":          [{"tap": 0.8}, {"wait": 60}, {"hz": 165, "ms": 200, "level": 0.85}],
        "subagent-start": [{"tap": 0.3}],
        "subagent-stop":  [{"tap": 0.3}, {"wait": 90}, {"tap": 0.3}],
        "task-done":      [{"note": "C7", "ms": 70, "level": 0.6}],
        "tool-failed":    [{"tap": 0.25}],
        "compact":        [{"note": "A5", "ms": 110, "level": 0.4}, {"note": "E6", "ms": 110, "level": 0.45}, {"note": "A6", "ms": 150, "level": 0.5}],
        "session-start":  [{"note": "A5", "ms": 80, "level": 0.6}, {"note": "E6", "ms": 140, "level": 0.7}],
        "session-end":    [{"note": "E6", "ms": 80, "level": 0.6}, {"note": "A5", "ms": 140, "level": 0.6}]
      }
    }
    """
}

/// Every cue cueback knows, and the Claude Code event that triggers it.
let cueEvents: [(cue: String, event: String)] = [
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
]

func printCues() {
    let theme = try? Theme.load(path: nil)
    print("  cue             default  event")
    for (cue, event) in cueEvents {
        let on = theme?.enabled.contains(cue) == true ? "on " : "off"
        print("  " + cue.padding(toLength: 16, withPad: " ", startingAt: 0) + on + "      " + event)
    }
}

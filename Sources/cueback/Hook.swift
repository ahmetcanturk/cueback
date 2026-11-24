import Foundation

/// The cue for a Claude Code hook event (its JSON input), or nil when the event shouldn't make a sound.
func cueName(for input: [String: Any]) -> String? {
    switch input["hook_event_name"] as? String {
    case "PermissionRequest":
        return "permission"
    case "Notification":
        // permission_prompt comes ~6 s late; PermissionRequest already covers it, instantly.
        return (input["notification_type"] as? String) == "idle_prompt" ? "waiting" : nil
    case "Elicitation":
        return "input"
    case "Stop":
        // A hook continued the turn, or background tasks are still running: Claude isn't done yet.
        if (input["stop_hook_active"] as? Bool) == true || hasValue(input["background_tasks"]) { return nil }
        return "done"
    case "StopFailure":
        return "error"
    case "SubagentStart":
        return hasValue(input["agent_type"]) ? "subagent-start" : nil
    case "SubagentStop":
        // Claude's own internal agents (prompt suggestions and the like) stop with an empty agent_type.
        return hasValue(input["agent_type"]) ? "subagent-stop" : nil
    case "TaskCompleted":
        return "task-done"
    case "PostToolUseFailure":
        return (input["is_interrupt"] as? Bool) == true ? nil : "tool-failed"
    case "PreCompact":
        return "compact"
    case "SessionStart":
        return (input["source"] as? String) == "startup" ? "session-start" : nil
    case "SessionEnd":
        return "session-end"
    default:
        return nil
    }
}

private func hasValue(_ value: Any?) -> Bool {
    guard let value, !(value is NSNull) else { return false }
    if let s = value as? String { return !s.isEmpty }
    if let a = value as? [Any] { return !a.isEmpty }
    if let d = value as? [String: Any] { return !d.isEmpty }
    if let n = value as? NSNumber { return n.doubleValue != 0 }
    return true
}

/// For Claude Code hooks: reads the event from stdin, sends its cue to the daemon and exits. It never prints,
/// never fails and never waits, so it can't get in Claude's way. With `dryRun` it prints what it would send.
func runHook(dryRun: Bool) -> Never {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    // Cues from inside a subagent play quieter ("sub <cue>"); the subagents' own start and stop cues are soft already.
    let message = cueName(for: input).map { cue in
        hasValue(input["agent_id"]) && !cue.hasPrefix("subagent-") ? "sub " + cue : cue
    }
    if dryRun {
        print(message ?? "-")
    } else if let message {
        Socket.send(message)
    }
    exit(0)
}

/// The Claude Code events cueback listens to, with their matchers.
let hookEvents: [(event: String, matcher: String?)] = [
    ("PermissionRequest", nil), ("Notification", "idle_prompt"), ("Elicitation", nil), ("Stop", nil),
    ("StopFailure", nil), ("SubagentStart", nil), ("SubagentStop", nil), ("TaskCompleted", nil),
    ("PostToolUseFailure", nil), ("PreCompact", nil), ("SessionStart", "startup"), ("SessionEnd", nil),
]

/// Prints the "hooks" block to merge into ~/.claude/settings.json. Every hook is async, so Claude never waits.
func printHooksJSON() {
    let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    let command = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "' hook"
    var hooks: [String: Any] = [:]
    for (event, matcher) in hookEvents {
        let hook: [String: Any] = ["type": "command", "command": command, "async": true]
        var group: [String: Any] = ["hooks": [hook]]
        if let matcher { group["matcher"] = matcher }
        hooks[event] = [group]
    }
    let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: options) {
        print(String(decoding: data, as: UTF8.self))
    }
}

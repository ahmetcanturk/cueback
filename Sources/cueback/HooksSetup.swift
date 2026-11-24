import Foundation

private let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

/// The command Claude Code runs for every cueback hook.
private var hookCommand: String {
    let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    let plain = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
    return (plain ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'") + " hook"
}

private func isCuebackHook(_ hook: [String: Any]) -> Bool {
    guard let command = hook["command"] as? String else { return false }
    return command.hasSuffix("/cueback hook") || command.hasSuffix("/cueback' hook")
}

private func readSettings() -> [String: Any] {
    guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
    guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        fail("~/.claude/settings.json isn't valid JSON, so cueback left it alone.")
    }
    return settings
}

/// Keeps a copy of the settings file next to it, then writes the new one in a single step.
private func writeSettings(_ settings: [String: Any]) {
    let fm = FileManager.default
    if fm.fileExists(atPath: settingsURL.path) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        try? fm.copyItem(atPath: settingsURL.path, toPath: settingsURL.path + ".bak-cueback-" + stamp.string(from: Date()))
    } else {
        try? fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? JSONSerialization.data(withJSONObject: settings, options: options) else {
        fail("Couldn't write the new settings.")
    }
    do { try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic) } catch {
        fail("Couldn't write ~/.claude/settings.json: \(error)")
    }
}

/// Adds cueback's hooks to ~/.claude/settings.json, next to the hooks already there. Leaves the file alone when
/// they're in already.
func installHooks() {
    var settings = readSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var added: [String] = []
    for (event, matcher) in hookEvents {
        var groups = hooks[event] as? [[String: Any]] ?? []
        if groups.contains(where: { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isCuebackHook) }) { continue }
        let hook: [String: Any] = ["type": "command", "command": hookCommand, "async": true]
        var group: [String: Any] = ["hooks": [hook]]
        if let matcher { group["matcher"] = matcher }
        groups.append(group)
        hooks[event] = groups
        added.append(event)
    }
    guard !added.isEmpty else { print("Claude Code hooks: already in ~/.claude/settings.json"); return }
    settings["hooks"] = hooks
    writeSettings(settings)
    print("Claude Code hooks: added for \(added.count) events in ~/.claude/settings.json (the old file is kept as a backup)")
}

/// Takes cueback's hooks out of ~/.claude/settings.json and keeps everything else.
func uninstallHooks() {
    var settings = readSettings()
    guard var hooks = settings["hooks"] as? [String: Any] else { print("Claude Code hooks: none to remove"); return }
    var removed = 0
    for (event, value) in hooks {
        guard let groups = value as? [[String: Any]] else { continue }
        var kept: [[String: Any]] = []
        for var group in groups {
            let entries = group["hooks"] as? [[String: Any]] ?? []
            let others = entries.filter { !isCuebackHook($0) }
            removed += entries.count - others.count
            if others.isEmpty && !entries.isEmpty { continue }
            group["hooks"] = others
            kept.append(group)
        }
        if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
    }
    guard removed > 0 else { print("Claude Code hooks: none to remove"); return }
    settings["hooks"] = hooks
    writeSettings(settings)
    print("Claude Code hooks: removed \(removed) from ~/.claude/settings.json (the old file is kept as a backup)")
}

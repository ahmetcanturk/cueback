import Combine
import Foundation

struct LastCue: Equatable {
    let name: String
    let at: Date
}

/// Decides what a cue request does, for the socket (hooks, `cueback play`) and for the menu bar alike, and holds
/// what the menu bar shows. Requests come from any thread; the published state changes on the main thread.
final class Engine: ObservableObject {
    private let player: Player
    private let themes: [String: Theme]
    let themeIDs: [String]
    private let defaultThemeID: String
    private let cliVolume: Double?
    private let lock = NSLock()
    private var settings: Config        // the copy the socket thread reads, under `lock`
    private var showsUI = false

    @Published private(set) var isOn = !Switch.isOff
    @Published private(set) var config: Config
    @Published var volume: Double       // the slider; saved when it's let go
    @Published private(set) var lastCue: LastCue?
    @Published private(set) var demoPlaying = false

    /// `custom` is a theme from the daemon's --theme; it's used until another one is picked.
    init(player: Player, custom: Theme?, cliVolume: Double?) {
        var themes: [String: Theme] = [:]
        var ids: [String] = []
        for id in Theme.builtInIDs {
            if let theme = Theme.builtIn(id) { themes[id] = theme; ids.append(id) }
        }
        if let custom { themes["custom"] = custom; ids.append("custom") }
        let defaultID = custom != nil ? "custom" : "classic"
        let config = Config.load()
        let theme = themes[config.theme ?? defaultID] ?? themes[defaultID]
        self.player = player
        self.themes = themes
        self.themeIDs = ids
        self.defaultThemeID = defaultID
        self.cliVolume = cliVolume
        self.settings = config
        self.config = config
        self.volume = config.volume ?? cliVolume ?? theme?.volume ?? 100
        if let theme { player.prepare(theme) }
    }

    private func theme(for config: Config) -> Theme {
        themes[config.theme ?? defaultThemeID] ?? themes[defaultThemeID] ?? themes.values.first!
    }

    /// The theme in use, from any thread.
    func activeTheme() -> Theme {
        lock.lock()
        defer { lock.unlock() }
        return theme(for: settings)
    }

    /// Plays a request: "[play] [sub] <cue>". "play" is a preview, which plays even when cueback is off, in quiet
    /// hours or for a cue the theme leaves off; "sub" comes from inside a subagent and plays quieter. "reload"
    /// rereads the settings (after `cueback theme`). Returns why a cue was skipped, or nil.
    @discardableResult
    func handle(_ message: String) -> String? {
        if message == "reload" { reload(); return nil }
        var words = message.split(separator: " ").map(String.init)
        guard let cue = words.popLast() else { return "empty request" }
        let preview = words.contains("play"), fromSubagent = words.contains("sub")
        lock.lock()
        let settings = self.settings
        lock.unlock()
        var reason: String?
        if !preview && Switch.isOff {
            reason = "cueback is off"
        } else if !preview && settings.isQuiet() {
            reason = "quiet hours"
        } else {
            let theme = self.theme(for: settings)
            let volume = settings.volume ?? cliVolume ?? theme.volume ?? 100
            reason = player.request(cue, theme: theme, preview: preview, fromSubagent: fromSubagent, volume: volume)
        }
        let label = cue + (preview ? " (preview)" : "") + (fromSubagent ? " (subagent)" : "")
        logLine(reason.map { "\(label) · skipped: \($0)" } ?? label)
        if reason == nil, showsUI {
            DispatchQueue.main.async { self.lastCue = LastCue(name: cue, at: Date()) }
        }
        return reason
    }

    private func reload() {
        let fresh = Config.load()
        lock.lock()
        settings = fresh
        lock.unlock()
        logLine("settings reloaded · theme \(theme(for: fresh).name)")
        player.prepare(theme(for: fresh))
        guard showsUI else { return }
        DispatchQueue.main.async {
            self.config = fresh
            self.volume = fresh.volume ?? self.cliVolume ?? self.theme(for: fresh).volume ?? 100
        }
    }

    // MARK: The menu bar (main thread)

    func attachUI() {
        guard !showsUI else { return }
        showsUI = true
        // `cueback on`/`off` from a terminal, and quiet hours starting or ending.
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        isOn = !Switch.isOff
        objectWillChange.send()
    }

    func setOn(_ on: Bool) {
        try? Switch.set(on: on)
        isOn = !Switch.isOff
        if isOn { preview("subagent-start") }
    }

    func updateConfig(_ change: (inout Config) -> Void) {
        var next = config
        change(&next)
        config = next
        next.save()
        lock.lock()
        settings = next
        lock.unlock()
    }

    var themeID: String { themes[config.theme ?? ""] != nil ? config.theme! : defaultThemeID }

    func themeTitle(_ id: String) -> String {
        "\((themeIDs.firstIndex(of: id) ?? 0) + 1) · \(themes[id]?.name ?? id)"
    }

    func themeAbout(_ id: String) -> String { themes[id]?.about ?? "" }

    /// Switches the theme and plays its `installed` cue, so you feel what you picked.
    func setTheme(_ id: String) {
        guard themes[id] != nil, id != themeID else { return }
        updateConfig { $0.theme = id }
        volume = config.volume ?? cliVolume ?? theme(for: config).volume ?? 100
        logLine("theme \(theme(for: config).name)")
        player.prepare(theme(for: config))
        preview("installed")
    }

    /// Saves the slider's volume, then taps once at it so you feel the new level.
    func commitVolume() {
        let level = volume.rounded()
        updateConfig { $0.volume = level }
        preview("level")
    }

    func preview(_ cue: String) {
        handle("play " + cue)
    }

    func playDemo() {
        guard !demoPlaying else { return }
        demoPlaying = true
        DispatchQueue.global(qos: .userInitiated).async {
            for scene in demoScenes {
                self.handle(scene.message)
                Thread.sleep(forTimeInterval: scene.pause)
            }
            DispatchQueue.main.async { self.demoPlaying = false }
        }
    }
}

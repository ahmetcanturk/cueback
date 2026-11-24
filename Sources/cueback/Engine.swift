import Combine
import Foundation

struct LastCue: Equatable {
    let name: String
    let at: Date
}

/// Decides what a cue request does, for the socket (hooks, `cueback play`) and for the menu bar alike, and holds
/// what the menu bar shows. Requests come from any thread; the published state changes on the main thread.
final class Engine: ObservableObject {
    let theme: Theme
    private let player: Player
    private let cliVolume: Double?
    private let lock = NSLock()
    private var settings: Config        // the copy the socket thread reads, under `lock`
    private var showsUI = false

    @Published private(set) var isOn = !Switch.isOff
    @Published private(set) var config: Config
    @Published var volume: Double       // the slider; saved when it's let go
    @Published private(set) var lastCue: LastCue?
    @Published private(set) var demoPlaying = false

    init(player: Player, theme: Theme, cliVolume: Double?) {
        let config = Config.load()
        self.player = player
        self.theme = theme
        self.cliVolume = cliVolume
        self.settings = config
        self.config = config
        self.volume = config.volume ?? cliVolume ?? theme.volume ?? 100
    }

    /// Plays a request: "[play] [sub] <cue>". "play" is a preview, which plays even when cueback is off, in quiet
    /// hours or for a cue the theme leaves off; "sub" comes from inside a subagent and plays quieter. Returns why
    /// it was skipped, or nil when it plays.
    @discardableResult
    func handle(_ message: String) -> String? {
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
            let volume = settings.volume ?? cliVolume ?? theme.volume ?? 100
            reason = player.request(cue, preview: preview, fromSubagent: fromSubagent, volume: volume)
        }
        let label = cue + (preview ? " (preview)" : "") + (fromSubagent ? " (subagent)" : "")
        logLine(reason.map { "\(label) · skipped: \($0)" } ?? label)
        if reason == nil, showsUI {
            DispatchQueue.main.async { self.lastCue = LastCue(name: cue, at: Date()) }
        }
        return reason
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

import Darwin
import Foundation

/// Limits that keep the motor's duty low (see nospeaker issue #15) and keep cues from turning into noise.
enum Limits {
    static let maxCueSeconds = 1.2   // a cue longer than this is cut off
    static let gapSeconds = 0.15     // quiet after every cue
    static let cuesPerMinute = 30    // past this, cues are dropped until the minute rolls over
    static let queueDepth = 2        // the cue playing plus one waiting; more are dropped
}

/// Plays cues one at a time, on their own thread, within `Limits`.
final class Player {
    private let motor: Motor
    private let theme: Theme
    private let queue = DispatchQueue(label: "cueback.player", qos: .userInteractive)
    private let lock = NSLock()
    private var queued = 0
    private var recent: [Date] = []

    init(motor: Motor, theme: Theme) {
        self.motor = motor
        self.theme = theme
    }

    /// Queues a cue by name: nil when it will play, or why it won't.
    func request(_ cue: String) -> String? {
        guard theme.enabled.contains(cue) else { return "off in this theme" }
        guard let steps = theme.cues[cue], !steps.isEmpty else { return "not in this theme" }
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0) > 60 }
        if queued >= Limits.queueDepth { return "another cue is playing" }
        if recent.count >= Limits.cuesPerMinute { return "\(Limits.cuesPerMinute) cues this minute already" }
        recent.append(now)
        queued += 1
        queue.async {
            self.perform(steps)
            self.lock.lock()
            self.queued -= 1
            self.lock.unlock()
        }
        return nil
    }

    private func perform(_ steps: [Step]) {
        let start = Clock.now()
        var t = 0.0
        for step in steps where t < Limits.maxCueSeconds {
            let left = Limits.maxCueSeconds - t
            if let strength = step.tap {
                motor.tap(min(1, max(0, strength)))
                t += Motor.tapSeconds
            } else if let hz = step.hz ?? step.note.flatMap(frequency(ofNote:)) {
                let seconds = min(max(0, step.ms ?? 120) / 1000, left)
                motor.tone(hz, seconds: seconds, level: min(1, max(0, step.level ?? 0.8)))
                t += seconds
            } else if let ms = step.wait {
                t += min(max(0, ms) / 1000, left)
            }
            Clock.wait(until: Clock.after(t, from: start))
        }
        usleep(useconds_t(Limits.gapSeconds * 1e6))
    }
}

private var socketPathForCleanup: UnsafeMutablePointer<CChar>?

/// Keeps the motor open and plays the cues that `cueback hook` and `cueback play` send. Runs until stopped.
func runDaemon(themePath: String?, volume: Double?, external: Bool) -> Never {
    if Socket.isServing() { fail("cueback is already running.") }
    let theme: Theme
    do { theme = try Theme.load(path: themePath) } catch { fail("Couldn't read the theme: \(error)") }
    let motor: Motor
    do { motor = try Motor(external: external) } catch { fail("\(error)") }
    let level = min(100, max(0, volume ?? theme.volume ?? 100))
    motor.volume = Float(level / 100)
    let player = Player(motor: motor, theme: theme)

    let listener: Int32
    do { listener = try Socket.listen() } catch { fail("\(error)") }
    socketPathForCleanup = strdup(Socket.path)
    let cleanup: @convention(c) (Int32) -> Void = { _ in
        if let path = socketPathForCleanup { unlink(path) }
        _exit(0)
    }
    signal(SIGINT, cleanup)
    signal(SIGTERM, cleanup)
    signal(SIGHUP, cleanup)

    logLine("ready · theme \(theme.name) · volume \(Int(level)) · on: \(theme.enabled.joined(separator: ", "))")
    while true {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { continue }
        let message = Socket.readMessage(client)
        close(client)
        guard let cue = message, !cue.isEmpty, cue.count <= 64 else { continue }
        if let reason = player.request(cue) { logLine("\(cue) · skipped: \(reason)") } else { logLine(cue) }
    }
}

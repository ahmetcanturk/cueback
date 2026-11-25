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
    private let speech = SpeechCache()
    private let sounds = SoundCache()
    private let queue = DispatchQueue(label: "cueback.player", qos: .userInteractive)
    private let lock = NSLock()
    private var queued = 0
    private var recent: [Date] = []

    init(motor: Motor) {
        self.motor = motor
    }

    /// Gets a theme's spoken lines and sound files ready, so its first cue isn't late.
    func prepare(_ theme: Theme) {
        speech.prepare(theme)
        sounds.prepare(theme)
    }

    /// Queues one of `theme`'s cues at `volume` (0…100): nil when it will play, or why it won't. A preview plays
    /// even a cue the theme leaves off. A cue from inside a subagent plays at the theme's `subagentLevel`.
    func request(_ cue: String, theme: Theme, preview: Bool = false, fromSubagent: Bool = false, volume: Double = 100) -> String? {
        guard preview || theme.enabled.contains(cue) else { return "off in this theme" }
        guard let steps = theme.cues[cue], !steps.isEmpty else { return "not in this theme" }
        let scale = fromSubagent ? min(1, max(0, theme.subagentLevel ?? 0.6)) : 1
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0) > 60 }
        if queued >= Limits.queueDepth { return "another cue is playing" }
        if recent.count >= Limits.cuesPerMinute { return "\(Limits.cuesPerMinute) cues this minute already" }
        recent.append(now)
        queued += 1
        let soft = theme.soft ?? false
        queue.async {
            self.motor.volume = Float(min(100, max(0, volume)) / 100)
            self.perform(steps, scale: scale, soft: soft)
            self.lock.lock()
            self.queued -= 1
            self.lock.unlock()
        }
        return nil
    }

    /// A tone takes the shape its step names. Otherwise, in a soft theme, low tones (under 500 Hz) swell and the
    /// notes above them ring like bells.
    private func perform(_ steps: [Step], scale: Double, soft: Bool) {
        let start = Clock.now()
        var t = 0.0
        var spoke = false
        for step in steps where t < Limits.maxCueSeconds {
            let left = Limits.maxCueSeconds - t
            if step.say != nil {
                if let frames = speech.frames(for: step) {
                    t += motor.speak(frames, level: min(1, max(0, step.level ?? 0.9)) * scale, pitch: step.pitch ?? 1,
                                     formants: step.formants ?? 1, limit: left)
                    spoke = true
                }
            } else if let file = step.sound {
                if let frames = sounds.frames(for: file) {
                    t += motor.sound(frames, level: min(1, max(0, step.level ?? 0.8)) * scale, limit: left)
                    spoke = true
                }
            } else if let pitches = step.hum {
                let seconds = min(max(0, step.ms ?? 300) / 1000, left)
                motor.hum(pitches, seconds: seconds, level: min(1, max(0, step.level ?? 0.6)) * scale, mouth: step.mouth)
                t += seconds
                spoke = true
            } else if let band = step.hiss, band.count == 2 {
                let seconds = min(max(0, step.ms ?? 200) / 1000, left)
                motor.hiss(low: band[0], high: band[1], seconds: seconds, level: min(1, max(0, step.level ?? 0.5)) * scale,
                           rise: step.rise ?? false)
                t += seconds
                spoke = true
            } else if let pitches = step.glide, pitches.count == 2 {
                let seconds = min(max(0, step.ms ?? 60) / 1000, left)
                motor.glide(from: pitches[0], to: pitches[1], seconds: seconds, level: min(1, max(0, step.level ?? 0.5)) * scale)
                t += seconds
            } else if let strength = step.tap {
                motor.tap(min(1, max(0, strength)) * scale)
                t += Motor.tapSeconds
            } else if let hz = step.hz ?? step.note.flatMap(frequency(ofNote:)) {
                let seconds = min(max(0, step.ms ?? 120) / 1000, left)
                let shape = ToneShape(rawValue: step.shape ?? "") ?? (soft ? (hz < 500 ? .swell : .bell) : .plain)
                motor.tone(hz, seconds: seconds, level: min(1, max(0, step.level ?? 0.8)) * scale, shape: shape, ring: step.ring)
                t += seconds
            } else if let ms = step.wait {
                t += min(max(0, ms) / 1000, left)
            }
            Clock.wait(until: Clock.after(t, from: start))
        }
        let counts = motor.takeCounts()
        if counts.failures > 0 {
            logLine("  the motor refused \(counts.failures) of \(counts.actuations) actuations (code \(counts.lastCode))")
        } else if spoke {
            logLine("  voiced in \(counts.actuations) commands, none refused")
        }
        usleep(useconds_t(Limits.gapSeconds * 1e6))
    }
}

private var socketPathForCleanup: UnsafeMutablePointer<CChar>?

/// Opens the motor and the socket, then plays what `cueback hook`, `cueback play` and the menu bar ask for. Shows
/// the menu bar icon unless `headless`. Runs until stopped.
func runDaemon(themePath: String?, volume: Double?, external: Bool, headless: Bool) -> Never {
    if Socket.isServing() { fail("cueback is already running.") }
    var custom: Theme?
    if let themePath {
        do { custom = try Theme.load(path: themePath) } catch { fail("Couldn't read the theme: \(error)") }
    }
    let motor: Motor
    do { motor = try Motor(external: external) } catch { fail("\(error)") }
    let engine = Engine(player: Player(motor: motor), custom: custom, cliVolume: volume)
    let theme = engine.activeTheme()

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

    let state = Switch.isOff ? " · OFF until `cueback on`" : ""
    let enabled = theme.enabled.joined(separator: ", ")
    logLine("ready · theme \(theme.name) · volume \(Int(engine.volume)) · on: \(enabled)\(state)\(headless ? "" : " · menu bar")")
    if headless { serve(listener, engine) }
    Thread { serve(listener, engine) }.start()
    runMenuBar(engine)
}

/// Answers cue requests on the socket, one at a time.
private func serve(_ listener: Int32, _ engine: Engine) -> Never {
    while true {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { continue }
        let message = Socket.readMessage(client)
        close(client)
        guard let message, !message.isEmpty, message.count <= 64 else { continue }
        engine.handle(message)
    }
}

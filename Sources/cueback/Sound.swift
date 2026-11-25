// A sound file for the trackpad. The start of the file is cut into 12 ms frames, and each frame is reduced to
// its three strongest pitches and its loudness, which the motor can play. A voice, a melody or one clear sound
// comes through; a full mix turns into a buzz, because the motor plays a few pure tones at a time and no more.

import AVFoundation
import Foundation

struct SoundFrame {
    var tones: [(hz: Double, amp: Double)] = []
    var level = 0.0
}

enum Sound {
    static let hop = 0.012
    private static let window = 0.032
    private static let lowest = 80.0, highest = 4000.0   // the motor's range
    private static let stepsPerOctave = 24.0

    /// Where a `sound` step's file is: a full path, one from your home folder ("~/…"), or a name in the themes
    /// folder.
    static func url(for path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return Theme.userDirectory.appendingPathComponent(expanded)
    }

    /// How long an audio file is, in seconds. Nil when macOS can't read it as audio.
    static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Reads the start of an audio file (any format macOS opens) and analyses it: up to `limit` seconds of sound,
    /// after any silence the file starts with. Nil when it can't.
    static func load(_ url: URL, seconds limit: Double) -> [SoundFrame]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        let count = AVAudioFrameCount(min(Double(file.length), (limit + 2) * rate))   // room for silence at the start
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              (try? file.read(into: buffer, frameCount: count)) != nil,
              let channels = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength), channelCount = Int(format.channelCount)
        guard n > 0, channelCount > 0 else { return nil }
        var mono = [Double](repeating: 0, count: n)
        for c in 0..<channelCount {
            let samples = channels[c]
            for i in 0..<n { mono[i] += Double(samples[i]) / Double(channelCount) }
        }
        var frames = analyse(mono, rate: rate)
        while let first = frames.first, first.level == 0 { frames.removeFirst() }
        frames = Array(frames.prefix(Int((limit / hop).rounded(.up))))
        while let last = frames.last, last.level == 0 { frames.removeLast() }
        return frames.isEmpty ? nil : frames
    }

    /// Each frame's three strongest pitches between 80 Hz and 4 kHz, at least a quarter of an octave apart, and
    /// its loudness next to the loudest frame's.
    private static func analyse(_ x: [Double], rate: Double) -> [SoundFrame] {
        let win = Int(window * rate), hopN = max(1, Int(hop * rate))
        guard win > 16, x.count >= win else { return [] }
        let hann = (0..<win).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(win - 1)) }
        var pitches: [Double] = []
        var hz = lowest
        while hz <= min(highest, rate * 0.45) {
            pitches.append(hz)
            hz *= pow(2, 1 / stepsPerOctave)
        }
        let waves = pitches.map { hz -> (cos: [Double], sin: [Double]) in
            let w = 2 * Double.pi * hz / rate
            return ((0..<win).map { cos(w * Double($0)) * hann[$0] }, (0..<win).map { sin(w * Double($0)) * hann[$0] })
        }
        var frames: [SoundFrame] = [], loudness: [Double] = []
        var strength = [Double](repeating: 0, count: pitches.count)
        var i = 0
        while i + win <= x.count {
            var energy = 0.0
            for k in 0..<win { energy += x[i + k] * x[i + k] }
            loudness.append(sqrt(energy / Double(win)))
            for (p, wave) in waves.enumerated() {
                var re = 0.0, im = 0.0
                for k in 0..<win {
                    re += x[i + k] * wave.cos[k]
                    im += x[i + k] * wave.sin[k]
                }
                strength[p] = sqrt(re * re + im * im)
            }
            let peaks = strength.indices.filter { p in
                (p == 0 || strength[p] >= strength[p - 1]) && (p == strength.count - 1 || strength[p] > strength[p + 1])
            }.sorted { strength[$0] > strength[$1] }
            var tones: [(hz: Double, amp: Double)] = []
            for p in peaks where tones.count < 3 {
                if let strongest = tones.first, strength[p] < strongest.amp * 0.15 { break }
                if tones.contains(where: { abs(log2($0.hz / pitches[p])) < 0.25 }) { continue }
                tones.append((pitches[p], strength[p]))
            }
            frames.append(SoundFrame(tones: tones, level: 0))
            i += hopN
        }
        let loudest = loudness.max() ?? 0
        guard loudest > 1e-6 else { return [] }
        for k in frames.indices {
            let share = loudness[k] / loudest
            frames[k].level = share < 0.03 ? 0 : min(1, pow(share, 0.6))
        }
        return frames
    }
}

/// The sound files a theme plays, analysed once and kept until the file changes.
final class SoundCache {
    private var ready: [String: [SoundFrame]] = [:]
    private var failed: Set<String> = []
    private let lock = NSLock()

    /// The analysed file of a `sound` step, from the cache or made now. Nil when it isn't there or isn't audio.
    func frames(for path: String) -> [SoundFrame]? {
        let url = Sound.url(for: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let changed = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(changed)"
        lock.lock()
        if let frames = ready[key] { lock.unlock(); return frames }
        let known = failed.contains(key)
        lock.unlock()
        if known { return nil }
        let frames = Sound.load(url, seconds: Limits.maxCueSeconds)
        lock.lock()
        if let frames { ready[key] = frames } else { failed.insert(key) }
        lock.unlock()
        if frames == nil { logLine("  the sound file \(url.path) isn't there or isn't audio") }
        return frames
    }

    func prepare(_ theme: Theme) {
        let files = Set(theme.cues.values.flatMap { $0 }.compactMap { $0.sound })
        guard !files.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for file in files { _ = self.frames(for: file) }
        }
    }
}

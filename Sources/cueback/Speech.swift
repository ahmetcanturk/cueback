// Speech for the trackpad. macOS's own voice (`say`) speaks a line into a file; every 10 ms of it is reduced to
// the voice's strongest resonances (formants), its loudness and its pitch, which the motor can play.
//
// Adapted from nospeaker (https://github.com/os6/nospeaker), MIT License, Copyright (c) 2026 Cody Collier.
// See THIRD_PARTY_NOTICES.md.

import AVFoundation
import Foundation

struct SpeechFrame {
    var formants: [Double] = [500, 1500, 2500]
    var amps: [Double] = [1, 0.5, 0.25]
    var level = 0.0
    var voiced = false
    var f0 = 110.0
}

enum Speech {
    static let hop = 0.010
    private static let sampleRate = 16000.0

    /// Says `text` with macOS's `say` (in `voice`, at `rate` words a minute) and analyses it. Nil when it can't.
    static func render(_ text: String, voice: String?, rate: Double?) -> [SpeechFrame]? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cueback-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000"]
        if let voice { arguments += ["-v", voice] }
        if let rate { arguments += ["-r", String(Int(rate))] }
        say.arguments = arguments + [text]
        say.standardOutput = FileHandle.nullDevice
        say.standardError = FileHandle.nullDevice
        guard (try? say.run()) != nil else { return nil }
        say.waitUntilExit()
        guard say.terminationStatus == 0, let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else { return nil }
        var frames = analyse(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        while let first = frames.first, first.level == 0 { frames.removeFirst() }
        while let last = frames.last, last.level == 0 { frames.removeLast() }
        return frames.isEmpty ? nil : frames
    }

    /// Linear prediction (autocorrelation, Levinson–Durbin): the filter that best predicts the signal, and its error.
    private static func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
        var r = [Double](repeating: 0, count: p + 1)
        for k in 0...p {
            var s = 0.0
            for i in k..<x.count { s += x[i] * x[i - k] }
            r[k] = s
        }
        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1
        guard r[0] > 1e-12 else { return (a, 0) }
        r[0] *= 1.0001
        var e = r[0]
        for i in 1...p {
            var acc = r[i]
            for j in 1..<i { acc += a[j] * r[i - j] }
            let k = -acc / e
            var next = a
            for j in 1..<i { next[j] = a[j] + k * a[i - j] }
            next[i] = k
            a = next
            e *= 1 - k * k
        }
        return (a, e)
    }

    private struct Complex {
        var re: Double, im: Double
        static func + (l: Complex, r: Complex) -> Complex { Complex(re: l.re + r.re, im: l.im + r.im) }
        static func - (l: Complex, r: Complex) -> Complex { Complex(re: l.re - r.re, im: l.im - r.im) }
        static func * (l: Complex, r: Complex) -> Complex { Complex(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re) }
        static func / (l: Complex, r: Complex) -> Complex {
            let d = r.re * r.re + r.im * r.im
            return Complex(re: (l.re * r.re + l.im * r.im) / d, im: (l.im * r.re - l.re * r.im) / d)
        }
    }

    /// The roots of the prediction filter (Durand–Kerner); the ones near the unit circle are the resonances.
    private static func roots(_ a: [Double]) -> [Complex] {
        let p = a.count - 1
        var z = (0..<p).map { k -> Complex in
            let angle = 2 * Double.pi * Double(k) / Double(p) + 0.4
            return Complex(re: 0.9 * cos(angle), im: 0.9 * sin(angle))
        }
        func poly(_ x: Complex) -> Complex {
            var s = Complex(re: 1, im: 0)
            for k in 1...p { s = s * x + Complex(re: a[k], im: 0) }
            return s
        }
        for _ in 0..<300 {
            var moved = 0.0
            for i in 0..<p {
                var d = Complex(re: 1, im: 0)
                for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
                if d.re == 0 && d.im == 0 { d = Complex(re: 1e-12, im: 0) }
                let step = poly(z[i]) / d
                z[i] = z[i] - step
                moved = max(moved, abs(step.re) + abs(step.im))
            }
            if moved < 1e-10 { break }
        }
        return z
    }

    private static func analyse(_ x: [Float]) -> [SpeechFrame] {
        let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
        let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
        var frames: [SpeechFrame] = [], rmsList: [Double] = []
        var prev = SpeechFrame()
        var i = 0
        while i + win <= x.count {
            let seg = (0..<win).map { Double(x[i + $0]) }
            rmsList.append(sqrt(seg.reduce(0) { $0 + $1 * $1 } / Double(win)))
            var f = prev
            var crossings = 0
            for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) { crossings += 1 }
            var bestLag = 0, bestR = 0.0
            for lag in Int(sampleRate / 300)...Int(sampleRate / 70) where lag < win - 40 {
                var s = 0.0, ea = 0.0, eb = 0.0
                for k in 0..<(win - lag) {
                    s += seg[k] * seg[k + lag]
                    ea += seg[k] * seg[k]
                    eb += seg[k + lag] * seg[k + lag]
                }
                let r = s / max(sqrt(ea * eb), 1e-12)
                if r > bestR { bestR = r; bestLag = lag }
            }
            f.voiced = bestR > 0.35 && Double(crossings) / Double(win) < 0.22
            if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }
            var emphasized = [Double](repeating: 0, count: win)
            for k in 0..<win { emphasized[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
            let (a, err) = lpc(emphasized, order: order)
            var candidates: [Double] = []
            if err > 0 {
                for z in roots(a) where z.im > 0 {
                    let hz = atan2(z.im, z.re) * sampleRate / (2 * .pi)
                    let bandwidth = -log(max(1e-9, sqrt(z.re * z.re + z.im * z.im))) * sampleRate / .pi
                    if hz > 150, hz < 4200, bandwidth < 500 { candidates.append(hz) }
                }
            }
            func pick(_ lo: Double, _ hi: Double, near: Double) -> Double? {
                candidates.filter { $0 >= lo && $0 <= hi }.min { abs($0 - near) < abs($1 - near) }
            }
            if let f1 = pick(200, 1000, near: prev.formants[0]) { f.formants[0] = f1 }
            if let f2 = pick(max(f.formants[0] + 200, 650), 2700, near: prev.formants[1]) { f.formants[1] = f2 }
            if let f3 = pick(max(f.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { f.formants[2] = f3 }
            if err > 0 {
                f.amps = f.formants.map { hz in
                    let w = 2 * Double.pi * hz / sampleRate
                    var re = 0.0, im = 0.0
                    for k in 0...order {
                        re += a[k] * cos(w * Double(k))
                        im -= a[k] * sin(w * Double(k))
                    }
                    return 1 / max(sqrt(re * re + im * im), 1e-6)
                }
            }
            frames.append(f)
            prev = f
            i += hopN
        }
        let peak = rmsList.max() ?? 1
        for k in frames.indices {
            let rel = rmsList[k] / max(peak, 1e-9)
            frames[k].level = rel < 0.02 ? 0 : min(1, pow(rel, 0.45))
            if frames[k].level == 0 { frames[k].voiced = false }
        }
        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        let raw = frames
        for k in frames.indices {
            let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
            for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
            frames[k].f0 = min(250, max(70, median((lo...hi).map { raw[$0].f0 })))
        }
        return frames
    }
}

/// The lines a theme speaks, analysed once and kept. Analysing takes a moment, so a theme's lines are prepared
/// when it's picked.
final class SpeechCache {
    private var ready: [String: [SpeechFrame]] = [:]
    private var failed: Set<String> = []
    private let lock = NSLock()

    private func key(_ step: Step) -> String { "\(step.voice ?? "")|\(Int(step.rate ?? 0))|\(step.say ?? "")" }

    /// The analysed line of a `say` step, from the cache or made now. Nil when it can't be said. If the step's
    /// voice isn't installed, the system's voice says it.
    func frames(for step: Step) -> [SpeechFrame]? {
        guard let text = step.say else { return nil }
        let k = key(step)
        lock.lock()
        if let frames = ready[k] { lock.unlock(); return frames }
        let known = failed.contains(k)
        lock.unlock()
        if known { return nil }
        var frames = Speech.render(text, voice: step.voice, rate: step.rate)
        if frames == nil, step.voice != nil { frames = Speech.render(text, voice: nil, rate: step.rate) }
        lock.lock()
        if let frames { ready[k] = frames } else { failed.insert(k) }
        lock.unlock()
        return frames
    }

    func prepare(_ theme: Theme) {
        let lines = theme.cues.values.flatMap { $0 }.filter { $0.say != nil }
        guard !lines.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for step in lines { _ = self.frames(for: step) }
        }
    }
}

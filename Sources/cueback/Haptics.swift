// The trackpad's haptic motor, and the two sounds every cue is built from: a felt tap and a tone.
//
// Motor access is adapted from nospeaker (https://github.com/os6/nospeaker), MIT License, Copyright (c) 2026
// Cody Collier. See THIRD_PARTY_NOTICES.md.
//
// MultitouchSupport is a private macOS framework: undocumented, and a macOS update can change it.

import Darwin
import Foundation

enum Clock {
    static let ticksPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return 1e9 * Double(timebase.denom) / Double(timebase.numer)
    }()

    static func now() -> UInt64 { mach_absolute_time() }

    static func after(_ seconds: Double, from start: UInt64) -> UInt64 {
        start + UInt64(max(0, seconds) * ticksPerSecond)
    }

    /// Sleeps until `t`, spinning only for the last ~1.5 ms: tight timing without pinning a core.
    static func wait(until t: UInt64) {
        let margin = UInt64(0.0015 * ticksPerSecond)
        while true {
            let n = mach_absolute_time()
            if n >= t { return }
            if t - n > margin { usleep(useconds_t(Double(t - n - margin) / ticksPerSecond * 1e6)) }
        }
    }
}

enum MotorError: Error, CustomStringConvertible {
    case unsupported, noTrackpad, noMotor(external: Bool)

    var description: String {
        switch self {
        case .unsupported:
            return "This version of macOS doesn't have the trackpad functions cueback needs."
        case .noTrackpad:
            return "No trackpad was found."
        case .noMotor(let external):
            return external
                ? "No external Force Touch trackpad was found. Turn on your Magic Trackpad and try again."
                : "No trackpad with a haptic motor (Force Touch) was found."
        }
    }
}

final class Motor {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    /// The driver refuses a command that arrives while the last one still plays (0xE00002BC, the same error as in
    /// nospeaker#15). So commands never overlap, a little quiet follows each, and a cue sends a handful of them
    /// rather than dozens: a tap is one command, a tone one per ~40 ms.
    static let tapMilliseconds = 28.0
    static let guardSeconds = 0.002
    static var tapSeconds: Double { tapMilliseconds / 1000 + guardSeconds }

    /// 0…1, scales every command. It only ever turns the motor down, never past its normal maximum.
    var volume: Float = 1

    /// Commands since the last `takeCounts()`, and how many of them the motor refused.
    private var actuations = 0
    private var failures = 0
    private var lastFailureCode: Int32 = 0
    /// When the last command (and the quiet after it) ends.
    private var busyUntil: UInt64 = 0

    private let actuator: CFTypeRef
    private let pointer: UnsafeMutableRawPointer
    private let createActuation: ActuationCreate
    private let actuate: ActuationPlay
    private let closeActuator: ActuatorClose?

    /// Opens the built-in trackpad's motor (or an external one when there's none), or with `external` only an
    /// external Magic Trackpad's.
    init(external: Bool = false) throws {
        guard let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            throw MotorError.unsupported
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(mt, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let createList = sym("MTDeviceCreateList", CreateList.self),
              let getID = sym("MTDeviceGetDeviceID", GetID.self),
              let actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self),
              let actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self),
              let createActuation = sym("MTActuationCreateFromDictionary", ActuationCreate.self),
              let actuate = sym("MTActuationActuate", ActuationPlay.self)
        else { throw MotorError.unsupported }
        let isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
        self.createActuation = createActuation
        self.actuate = actuate
        self.closeActuator = sym("MTActuatorClose", ActuatorClose.self)

        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { throw MotorError.noTrackpad }
        var devices: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getID(device, &id) == 0 { devices.append((id, isBuiltIn?(device) ?? false)) }
        }
        let candidates = external ? devices.filter { !$0.builtIn } : devices.sorted { $0.builtIn && !$1.builtIn }
        for device in candidates {
            if let ref = actuatorCreate(device.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                actuator = ref
                pointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                return
            }
        }
        throw MotorError.noMotor(external: external)
    }

    deinit { _ = closeActuator?(actuator) }

    /// One command: tones (Hz, relative strength) played together for `ms`, at `level` (0…1). Strengths are scaled
    /// to add up to 1: past that is louder, but the driver starts stalling. Waits until the last command is done.
    func play(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Double) {
        guard !tones.isEmpty, ms > 0 else { return }
        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": tones.map { ["Type": "Sine", "Amplitude": $0.amp / sum, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": $0.hz / 1000] },
        ]
        Clock.wait(until: busyUntil)
        actuations += 1
        guard let actuation = createActuation(shape as CFDictionary, 0) else { failures += 1; return }
        let code = actuate(actuation, pointer, 0, Float(min(1, max(0, level))) * volume, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
        busyUntil = Clock.after(ms / 1000 + Motor.guardSeconds, from: Clock.now())
        if code != 0 { failures += 1; lastFailureCode = code }
    }

    /// The command counts since the last call, then starts counting again.
    func takeCounts() -> (actuations: Int, failures: Int, lastCode: Int32) {
        defer { actuations = 0; failures = 0; lastFailureCode = 0 }
        return (actuations, failures, lastFailureCode)
    }

    /// A felt tap in one command: a low thump with a little edge on top. `strength` 0…1.
    func tap(_ strength: Double) {
        play([(160, 0.8), (640, 0.2)], ms: Motor.tapMilliseconds, level: strength)
    }

    /// A tone in commands of 30–40 ms, 80 Hz to 4 kHz (the motor's range), with its strength shaped over them:
    /// `plain` holds it, with the first and last a little softer so it starts and ends without a click; `bell`
    /// strikes and fades like a music box; `swell` rises and falls like a breath.
    func tone(_ hz: Double, seconds: Double, level: Double, shape: ToneShape = .plain) {
        let f = min(4000, max(80, hz))
        let pieces = max(1, Int((seconds / (shape == .plain ? 0.04 : 0.03)).rounded()))
        let length = seconds / Double(pieces)
        for i in 0..<pieces {
            let weight: Double
            switch shape {
            case .plain: weight = pieces == 1 ? 1 : (i == 0 ? 0.8 : (i == pieces - 1 ? 0.75 : 1))
            case .bell: weight = pow(0.7, Double(i))
            case .swell: weight = pieces < 3 ? 0.8 : sin(.pi * (Double(i) + 0.5) / Double(pieces))
            }
            play([(f, 1)], ms: max(1, (length - Motor.guardSeconds) * 1000), level: level * weight)
        }
    }

    /// Speaks analysed speech (see Speech). Every voiced moment is the voice's two strongest resonances, started
    /// again on each beat of its pitch so they buzz like a voice; hiss sounds are short bursts of high tones.
    /// `pitch` and `formants` scale the voice (under 1: deeper and bigger). This is the one thing that sends
    /// many commands a second (about one per pitch beat), so lines are short and it stops at `limit` seconds.
    /// Returns how long it spoke.
    func speak(_ frames: [SpeechFrame], level: Double, pitch: Double, formants: Double, limit: Double) -> Double {
        let total = min(Double(frames.count) * Speech.hop, limit)
        let start = Clock.now()
        var t = 0.0
        while t < total {
            let frame = frames[min(frames.count - 1, Int(t / Speech.hop))]
            var step = 0.005
            if frame.level > 0 {
                if frame.voiced {
                    step = 1 / min(300, max(45, frame.f0 * pitch))
                    let tones: [(hz: Double, amp: Double)] = [
                        (frame.formants[0] * formants, frame.amps[0]), (frame.formants[1] * formants, frame.amps[1] * 1.8),
                    ]
                    play(tones, ms: (step - Motor.guardSeconds) * 1000, level: frame.level * level)
                } else {
                    step = 0.008
                    let hiss: [(hz: Double, amp: Double)] = (0..<3).map { _ in (Double.random(in: 2700...4300) * formants, 1.0) }
                    play(hiss, ms: (step - Motor.guardSeconds) * 1000, level: frame.level * 0.7 * level)
                }
            }
            t += step
            Clock.wait(until: Clock.after(t, from: start))
        }
        return total
    }
}

enum ToneShape: String {
    case plain, bell, swell
}

/// A note name like "A6" or "C#5" in Hz (A4 = 440), or nil if it isn't one.
func frequency(ofNote note: String) -> Double? {
    let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
    guard let last = note.last, let octave = Int(String(last)), let semitone = names[String(note.dropLast())] else { return nil }
    return 440 * pow(2, Double(semitone + (octave - 4) * 12) / 12)
}

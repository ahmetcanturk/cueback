// The trackpad's haptic motor, and the two sounds every cue is built from: a felt tap and a tone.
//
// Motor access and the tap are adapted from nospeaker (https://github.com/os6/nospeaker),
// MIT License, Copyright (c) 2026 Cody Collier. See THIRD_PARTY_NOTICES.md.
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

    /// How long `tap` lasts.
    static let tapSeconds = 0.11

    /// 0…1, scales every actuation. It only ever turns the motor down, never past its normal maximum.
    var volume: Float = 1

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

    /// One actuation: tones (Hz, relative strength) played together for `ms`, at `level` (0…1). Strengths are
    /// scaled to add up to 1: past that is louder, but the driver starts stalling.
    func play(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Double) {
        guard !tones.isEmpty, ms > 0 else { return }
        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": tones.map { ["Type": "Sine", "Amplitude": $0.amp / sum, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": $0.hz / 1000] },
        ]
        guard let actuation = createActuation(shape as CFDictionary, 0) else { return }
        _ = actuate(actuation, pointer, 0, Float(min(1, max(0, level))) * volume, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }

    /// A felt tap: a fast pitch dive you feel more than hear (nospeaker's heartbeat thump). `strength` 0…1.
    func tap(_ strength: Double) {
        let start = Clock.now()
        var t = 0.0
        while t < Motor.tapSeconds {
            let f = 120 + 780 * exp(-t / 0.02)
            let segment = 1 / f
            play([(f, 1)], ms: segment * 1000, level: strength * exp(-t / 0.05))
            t += segment
            Clock.wait(until: Clock.after(t, from: start))
        }
    }

    /// A tone that fades in and out, so it starts and stops without a click. 80 Hz to 4 kHz: the motor's range.
    func tone(_ hz: Double, seconds: Double, level: Double) {
        let f = min(4000, max(80, hz))
        let segment = max(1, (0.01 * f).rounded()) / f
        let start = Clock.now()
        var t = 0.0
        while t < seconds {
            let length = min(segment, seconds - t)
            let middle = t + length / 2
            let fadeIn = min(1, middle / 0.012)
            let fadeOut = min(1, max(0, (seconds - middle) / max(0.001, 0.35 * seconds)))
            play([(f, 1)], ms: length * 1000, level: level * fadeIn * fadeOut)
            t += length
            Clock.wait(until: Clock.after(t, from: start))
        }
    }
}

/// A note name like "A6" or "C#5" in Hz (A4 = 440), or nil if it isn't one.
func frequency(ofNote note: String) -> Double? {
    let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
    guard let last = note.last, let octave = Int(String(last)), let semitone = names[String(note.dropLast())] else { return nil }
    return 440 * pow(2, Double(semitone + (octave - 4) * 12) / 12)
}

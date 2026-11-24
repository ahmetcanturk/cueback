import Foundation

/// `cueback demo`: a Claude Code session in about fifteen seconds, played on the trackpad. It plays as previews,
/// so it works even while cueback is off.
func runDemo() -> Never {
    guard Socket.isServing() else { fail("The daemon isn't running. Start it with: cueback daemon") }
    let scenes: [(message: String, line: String, pause: Double)] = [
        ("play session-start", "a session starts", 1.4),
        ("play permission", "Claude asks for permission", 1.6),
        ("play subagent-start", "a subagent gets to work", 1.2),
        ("play sub permission", "the subagent asks too, softer", 1.6),
        ("play subagent-stop", "the subagent is done", 1.3),
        ("play error", "something fails", 1.6),
        ("play waiting", "Claude is waiting for you", 1.5),
        ("play done", "Claude is finished", 1.5),
        ("play fanfare", "that's cueback", 1.2),
    ]
    print("cueback demo · a Claude Code session on your trackpad\n")
    for (i, scene) in scenes.enumerated() {
        print("  \(i + 1)/\(scenes.count)  \(scene.line)")
        fflush(stdout)
        Socket.send(scene.message)
        Thread.sleep(forTimeInterval: scene.pause)
    }
    print("\n  Mute your Mac and run it again: every sound came from the trackpad.")
    exit(0)
}

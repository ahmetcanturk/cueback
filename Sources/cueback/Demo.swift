import Foundation

/// A Claude Code session in about fifteen seconds: what each scene sends, what it shows, and the pause after it.
/// Every scene is a preview, so the demo plays even while cueback is off.
let demoScenes: [(message: String, line: String, pause: Double)] = [
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

/// `cueback demo`: plays the scenes through the daemon and names each one.
func runDemo() -> Never {
    guard Socket.isServing() else { fail("The daemon isn't running. Start it with: cueback daemon") }
    print("cueback demo · a Claude Code session on your trackpad\n")
    for (i, scene) in demoScenes.enumerated() {
        print("  \(i + 1)/\(demoScenes.count)  \(scene.line)")
        fflush(stdout)
        Socket.send(scene.message)
        Thread.sleep(forTimeInterval: scene.pause)
    }
    print("\n  Mute your Mac and run it again: every sound came from the trackpad.")
    exit(0)
}

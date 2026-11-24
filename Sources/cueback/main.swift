// cueback: haptic cues for Claude Code, played on a Mac's trackpad (cue + feedback).

import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

var args = Array(CommandLine.arguments.dropFirst())

/// The value after `flag` (and removes both), or nil when the flag isn't there.
func option(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard i + 1 < args.count else { fail("\(flag) needs a value.") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let usage = """
cueback · haptic cues for Claude Code, played on your Mac's trackpad

  cueback daemon         keep the trackpad's motor open and play cues as they come in
      --volume 0-100     turn it down (the default theme plays at 70)
      --theme file.json  use your own cues
      --external         play through an external Magic Trackpad
  cueback hook           for Claude Code hooks: reads the event on stdin, sends its cue
      --dry-run          print the cue instead of sending it
  cueback play <cue>     play one cue now (needs the daemon)
  cueback cues           list the cues and the events that trigger them
  cueback hooks-json     print the hooks block for ~/.claude/settings.json
"""

let command = args.first
if !args.isEmpty { args.removeFirst() }

switch command {
case "daemon":
    let volumeText = option("--volume")
    let volume = volumeText.flatMap { Double($0) }
    if volumeText != nil, !(volume.map { (0...100).contains($0) } ?? false) {
        fail("--volume needs a number from 0 to 100, like: --volume 60")
    }
    let themePath = option("--theme")
    let external = flag("--external")
    if let unknown = args.first { fail("\"\(unknown)\" isn't an option for daemon.") }
    runDaemon(themePath: themePath, volume: volume, external: external)
case "hook":
    runHook(dryRun: flag("--dry-run"))
case "play":
    guard let cue = args.first else { fail("Which cue? See: cueback cues") }
    if !Socket.send(cue) { fail("The daemon isn't running. Start it with: cueback daemon") }
case "cues":
    printCues()
case "hooks-json":
    printHooksJSON()
case nil, "help", "-h", "--help":
    print(usage)
default:
    fail("\"\(command ?? "")\" isn't a command.\n\n\(usage)")
}

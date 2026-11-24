import Foundation

/// `cueback off` silences the cues that come from Claude Code until `cueback on`. Previews still play.
enum Switch {
    static var flagPath: String { Socket.directory.appendingPathComponent("off").path }
    static var isOff: Bool { FileManager.default.fileExists(atPath: flagPath) }

    static func set(on: Bool) throws {
        if on {
            if isOff { try FileManager.default.removeItem(atPath: flagPath) }
        } else {
            try FileManager.default.createDirectory(at: Socket.directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: flagPath, contents: nil)
        }
    }
}

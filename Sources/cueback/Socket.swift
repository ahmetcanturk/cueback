import Darwin
import Foundation

/// The daemon's Unix socket, in ~/Library/Application Support/cueback, readable and writable only by this user.
enum Socket {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/cueback", isDirectory: true)
    static var path: String { directory.appendingPathComponent("cueback.sock").path }

    struct Failure: Error, CustomStringConvertible { let description: String }

    private static func address() -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    private static func withAddress<R>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R? {
        guard var addr = address() else { return nil }
        return withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func setTimeout(_ fd: Int32, _ option: Int32, ms: Int) {
        var tv = timeval(tv_sec: 0, tv_usec: Int32(ms * 1000))
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Sends one cue name to the daemon. False when it isn't running.
    @discardableResult
    static func send(_ message: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(fd, SO_SNDTIMEO, ms: 200)
        guard withAddress({ connect(fd, $0, $1) }) == 0 else { return false }
        let bytes = Array((message + "\n").utf8)
        return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    /// True when a daemon is already listening.
    static func isServing() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return withAddress({ connect(fd, $0, $1) }) == 0
    }

    /// Opens the daemon's socket.
    static func listen() throws -> Int32 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "Couldn't open a socket.") }
        let previous = umask(0o077)
        let bound = withAddress({ bind(fd, $0, $1) })
        umask(previous)
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            close(fd)
            throw Failure(description: "Couldn't listen on \(path).")
        }
        return fd
    }

    /// Reads one short message (a cue name) from a client, giving up after 200 ms.
    static func readMessage(_ fd: Int32) -> String? {
        setTimeout(fd, SO_RCVTIMEO, ms: 200)
        var buffer = [UInt8](repeating: 0, count: 128)
        let n = read(fd, &buffer, 128)
        guard n > 0 else { return nil }
        return String(decoding: buffer[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

private let clockFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

/// A line in the daemon's log (stderr), with the time.
func logLine(_ line: String) {
    FileHandle.standardError.write(Data("\(clockFormat.string(from: Date()))  \(line)\n".utf8))
}

/// Stops with a plain message.
func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("cueback: \(message)\n".utf8))
    exit(code)
}

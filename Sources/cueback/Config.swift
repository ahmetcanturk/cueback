import Foundation

/// What the menu bar changes, kept in ~/Library/Application Support/cueback/config.json.
struct Config: Codable, Equatable {
    var volume: Double?            // 0…100; nil: the theme's
    var quietHours = false
    var quietStart = 22 * 60       // minutes after midnight
    var quietEnd = 8 * 60

    static var url: URL { Socket.directory.appendingPathComponent("config.json") }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume)
        quietHours = try c.decodeIfPresent(Bool.self, forKey: .quietHours) ?? false
        quietStart = try c.decodeIfPresent(Int.self, forKey: .quietStart) ?? 22 * 60
        quietEnd = try c.decodeIfPresent(Int.self, forKey: .quietEnd) ?? 8 * 60
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: Socket.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Config.url, options: .atomic)
    }

    /// True while quiet hours are on and the clock is inside them (they may run past midnight).
    func isQuiet(at date: Date = Date()) -> Bool {
        guard quietHours, quietStart != quietEnd else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return quietStart < quietEnd ? (now >= quietStart && now < quietEnd) : (now >= quietStart || now < quietEnd)
    }
}

import Foundation

struct SyncMemoryChannelConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var resolvedPath: String?
    var bookmarkData: Data?
    var lastDetectionSummary: String?
}

struct SyncMemoryConfig: Codable, Equatable {
    var obsidian = SyncMemoryChannelConfig()
    var openClaw = SyncMemoryChannelConfig()
    var autoSyncEnabled = false
    var dailySyncHour = 21
    var dailySyncMinute = 0

    static let `default` = SyncMemoryConfig()

    private static let storageKey = "syncMemoryConfig"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> SyncMemoryConfig {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(SyncMemoryConfig.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}

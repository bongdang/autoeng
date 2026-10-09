import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var englishSourceID: String?
    public var targetBundleIDs: Set<String>
    public var isPaused: Bool

    public init(englishSourceID: String? = nil,
                targetBundleIDs: Set<String> = ["com.googlecode.iterm2", "com.apple.Terminal"],
                isPaused: Bool = false) {
        self.englishSourceID = englishSourceID
        self.targetBundleIDs = targetBundleIDs
        self.isPaused = isPaused
    }
}

@MainActor
public final class SettingsStore {
    private let defaults: UserDefaults
    public static let storageKey = "autoeng.settings.v1"
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return normalized(settings)
    }
    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(normalized(settings))
        defaults.set(data, forKey: Self.storageKey)
    }
    private func normalized(_ settings: AppSettings) -> AppSettings {
        var result = settings
        if result.englishSourceID?.isEmpty == true { result.englishSourceID = nil }
        return result
    }
}

import Foundation

/// Centralized settings store using UserDefaults with Observable conformance.
/// Provides reactive access to user preferences for alert timing, sounds, filtering, and more.
@Observable
public final class SettingsStore: @unchecked Sendable {
    // MARK: - UserDefaults Keys

    private enum Keys {
        static let alertStage1Minutes = "alertStage1Minutes"
        static let alertStage2Minutes = "alertStage2Minutes"
        static let stage1Sound = "stage1Sound"
        static let stage2Sound = "stage2Sound"
        static let customSoundPath = "customSoundPath"
        static let enabledCalendars = "enabledCalendars"
        static let blockedKeywords = "blockedKeywords"
        static let forceAlertKeywords = "forceAlertKeywords"
        static let launchAtLogin = "launchAtLogin"
        static let suppressDuringScreenShare = "suppressDuringScreenShare"
    }

    // MARK: - Properties

    private let defaults: UserDefaults

    // MARK: - Alert Timing (0 = disabled)

    public var alertStage1Minutes: Int {
        get { self.defaults.object(forKey: Keys.alertStage1Minutes) as? Int ?? 10 }
        set { self.defaults.set(newValue, forKey: Keys.alertStage1Minutes) }
    }

    public var alertStage2Minutes: Int {
        get { self.defaults.object(forKey: Keys.alertStage2Minutes) as? Int ?? 2 }
        set { self.defaults.set(newValue, forKey: Keys.alertStage2Minutes) }
    }

    // MARK: - Sounds

    public var stage1Sound: String {
        get { self.defaults.string(forKey: Keys.stage1Sound) ?? "gentle-chime" }
        set { self.defaults.set(newValue, forKey: Keys.stage1Sound) }
    }

    public var stage2Sound: String {
        get { self.defaults.string(forKey: Keys.stage2Sound) ?? "urgent-tone" }
        set { self.defaults.set(newValue, forKey: Keys.stage2Sound) }
    }

    public var customSoundPath: String? {
        get { self.defaults.string(forKey: Keys.customSoundPath) }
        set { self.defaults.set(newValue, forKey: Keys.customSoundPath) }
    }

    // MARK: - Filtering (arrays as JSON strings)

    /// Calendars to monitor. Empty array means all calendars.
    public var enabledCalendars: [String] {
        get { self.loadStringArray(forKey: Keys.enabledCalendars) ?? [] }
        set { self.saveStringArray(newValue, forKey: Keys.enabledCalendars) }
    }

    /// Events containing these keywords won't trigger alerts.
    public var blockedKeywords: [String] {
        get { self.loadStringArray(forKey: Keys.blockedKeywords) ?? [] }
        set { self.saveStringArray(newValue, forKey: Keys.blockedKeywords) }
    }

    /// Events containing these keywords will alert even without video links.
    public var forceAlertKeywords: [String] {
        get { self.loadStringArray(forKey: Keys.forceAlertKeywords) ?? ["Interview", "IMPORTANT"] }
        set { self.saveStringArray(newValue, forKey: Keys.forceAlertKeywords) }
    }

    // MARK: - Startup

    public var launchAtLogin: Bool {
        get { self.defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true }
        set { self.defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    // MARK: - Presentation Mode

    public var suppressDuringScreenShare: Bool {
        get { self.defaults.object(forKey: Keys.suppressDuringScreenShare) as? Bool ?? true }
        set { self.defaults.set(newValue, forKey: Keys.suppressDuringScreenShare) }
    }

    // MARK: - Initialization

    /// Creates a SettingsStore using the standard UserDefaults.
    public init() {
        self.defaults = .standard
    }

    /// Creates a SettingsStore with a custom UserDefaults suite (for testing).
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Private Helpers

    private func loadStringArray(forKey key: String) -> [String]? {
        guard let jsonString = defaults.string(forKey: key),
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private func saveStringArray(_ array: [String], forKey key: String) {
        guard let data = try? JSONEncoder().encode(array),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return
        }
        self.defaults.set(jsonString, forKey: key)
    }
}

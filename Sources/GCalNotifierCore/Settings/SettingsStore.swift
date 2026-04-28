import Foundation
import Observation

/// Centralized settings store using UserDefaults with Observable conformance.
/// Provides reactive access to user preferences for alert timing, sounds, filtering, and more.
@Observable
public final class SettingsStore: @unchecked Sendable {
    public typealias AlertAffectingSettingsChangeHandler = (AlertAffectingSetting) -> Void

    public enum AlertAffectingSetting: Sendable, Equatable {
        case alertStage1Minutes
        case alertStage2Minutes
        case enabledCalendars
        case blockedKeywords
        case forceAlertKeywords
    }

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
        static let shortcutsEnabled = "shortcutsEnabled"
        static let cachedCalendarList = "cachedCalendarList"
    }

    // MARK: - Properties

    private let defaults: UserDefaults
    @ObservationIgnored private var alertAffectingSettingsChangeHandler: AlertAffectingSettingsChangeHandler?

    // MARK: - Alert Timing (0 = disabled)

    public var alertStage1Minutes: Int {
        get {
            access(keyPath: \.alertStage1Minutes)
            return self.defaults.object(forKey: Keys.alertStage1Minutes) as? Int ?? 10
        }
        set {
            let oldValue = self.defaults.object(forKey: Keys.alertStage1Minutes) as? Int ?? 10
            guard oldValue != newValue else { return }
            withMutation(keyPath: \.alertStage1Minutes) {
                self.defaults.set(newValue, forKey: Keys.alertStage1Minutes)
            }
            self.notifyAlertAffectingSettingsChanged(.alertStage1Minutes)
        }
    }

    public var alertStage2Minutes: Int {
        get {
            access(keyPath: \.alertStage2Minutes)
            return self.defaults.object(forKey: Keys.alertStage2Minutes) as? Int ?? 2
        }
        set {
            let oldValue = self.defaults.object(forKey: Keys.alertStage2Minutes) as? Int ?? 2
            guard oldValue != newValue else { return }
            withMutation(keyPath: \.alertStage2Minutes) {
                self.defaults.set(newValue, forKey: Keys.alertStage2Minutes)
            }
            self.notifyAlertAffectingSettingsChanged(.alertStage2Minutes)
        }
    }

    // MARK: - Sounds

    public var stage1Sound: String {
        get {
            access(keyPath: \.stage1Sound)
            return self.defaults.string(forKey: Keys.stage1Sound) ?? "glass"
        }
        set {
            withMutation(keyPath: \.stage1Sound) {
                self.defaults.set(newValue, forKey: Keys.stage1Sound)
            }
        }
    }

    public var stage2Sound: String {
        get {
            access(keyPath: \.stage2Sound)
            return self.defaults.string(forKey: Keys.stage2Sound) ?? "hero"
        }
        set {
            withMutation(keyPath: \.stage2Sound) {
                self.defaults.set(newValue, forKey: Keys.stage2Sound)
            }
        }
    }

    public var customSoundPath: String? {
        get {
            access(keyPath: \.customSoundPath)
            return self.defaults.string(forKey: Keys.customSoundPath)
        }
        set {
            withMutation(keyPath: \.customSoundPath) {
                self.defaults.set(newValue, forKey: Keys.customSoundPath)
            }
        }
    }

    // MARK: - Filtering (arrays as JSON strings)

    /// Calendars to monitor. Empty array means all calendars.
    public var enabledCalendars: [String] {
        get {
            access(keyPath: \.enabledCalendars)
            return self.loadStringArray(forKey: Keys.enabledCalendars) ?? []
        }
        set {
            let oldValue = self.loadStringArray(forKey: Keys.enabledCalendars) ?? []
            guard oldValue != newValue else { return }
            withMutation(keyPath: \.enabledCalendars) {
                self.saveStringArray(newValue, forKey: Keys.enabledCalendars)
            }
            self.notifyAlertAffectingSettingsChanged(.enabledCalendars)
        }
    }

    /// Events containing these keywords won't trigger alerts.
    public var blockedKeywords: [String] {
        get {
            access(keyPath: \.blockedKeywords)
            return self.loadStringArray(forKey: Keys.blockedKeywords) ?? []
        }
        set {
            let oldValue = self.loadStringArray(forKey: Keys.blockedKeywords) ?? []
            guard oldValue != newValue else { return }
            withMutation(keyPath: \.blockedKeywords) {
                self.saveStringArray(newValue, forKey: Keys.blockedKeywords)
            }
            self.notifyAlertAffectingSettingsChanged(.blockedKeywords)
        }
    }

    /// Events containing these keywords will alert even without video links.
    public var forceAlertKeywords: [String] {
        get {
            access(keyPath: \.forceAlertKeywords)
            return self.loadStringArray(forKey: Keys.forceAlertKeywords) ?? ["Interview", "IMPORTANT"]
        }
        set {
            let oldValue = self.loadStringArray(forKey: Keys.forceAlertKeywords) ?? ["Interview", "IMPORTANT"]
            guard oldValue != newValue else { return }
            withMutation(keyPath: \.forceAlertKeywords) {
                self.saveStringArray(newValue, forKey: Keys.forceAlertKeywords)
            }
            self.notifyAlertAffectingSettingsChanged(.forceAlertKeywords)
        }
    }

    // MARK: - Startup

    public var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return self.defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                self.defaults.set(newValue, forKey: Keys.launchAtLogin)
            }
        }
    }

    // MARK: - Presentation Mode

    public var suppressDuringScreenShare: Bool {
        get {
            access(keyPath: \.suppressDuringScreenShare)
            return self.defaults.object(forKey: Keys.suppressDuringScreenShare) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.suppressDuringScreenShare) {
                self.defaults.set(newValue, forKey: Keys.suppressDuringScreenShare)
            }
        }
    }

    // MARK: - Cached Calendar List

    /// Cached list of Google calendars for offline display in the Calendars tab.
    /// Populated when the user opens Preferences → Calendars; UI-only, not used by sync logic.
    public var cachedCalendarList: [CalendarInfo] {
        get {
            access(keyPath: \.cachedCalendarList)
            return self.loadCodableArray(forKey: Keys.cachedCalendarList)
        }
        set {
            withMutation(keyPath: \.cachedCalendarList) {
                self.saveCodableArray(newValue, forKey: Keys.cachedCalendarList)
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Whether global keyboard shortcuts are enabled.
    public var shortcutsEnabled: Bool {
        get {
            access(keyPath: \.shortcutsEnabled)
            return self.defaults.object(forKey: Keys.shortcutsEnabled) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.shortcutsEnabled) {
                self.defaults.set(newValue, forKey: Keys.shortcutsEnabled)
            }
        }
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

    // MARK: - Change Notifications

    public func setAlertAffectingSettingsChangeHandler(
        _ handler: AlertAffectingSettingsChangeHandler?
    ) {
        self.alertAffectingSettingsChangeHandler = handler
    }

    // MARK: - Private Helpers

    private func notifyAlertAffectingSettingsChanged(_ setting: AlertAffectingSetting) {
        self.alertAffectingSettingsChangeHandler?(setting)
    }

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

    private func loadCodableArray<T: Codable>(forKey key: String) -> [T] {
        guard let jsonString = self.defaults.string(forKey: key),
              let data = jsonString.data(using: .utf8)
        else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func saveCodableArray(_ array: [some Codable], forKey key: String) {
        guard let data = try? JSONEncoder().encode(array),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }
        self.defaults.set(jsonString, forKey: key)
    }
}

import OSLog

/// Unified logging infrastructure for GCalNotifier using OSLog.
///
/// Categories:
/// - `app`: App lifecycle, startup, shutdown
/// - `sync`: Calendar sync operations
/// - `auth`: OAuth authentication flows
/// - `alerts`: Alert scheduling and firing
/// - `settings`: Configuration changes
///
/// Debug mode can be enabled via:
/// ```bash
/// defaults write com.gcal-notifier logLevel debug
/// ```
public extension Logger {
    private static let subsystem = "com.gcal-notifier"

    /// App lifecycle logging (startup, shutdown, state changes)
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Calendar sync operation logging
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// OAuth authentication logging
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Alert scheduling and firing logging
    static let alerts = Logger(subsystem: subsystem, category: "alerts")

    /// Settings and configuration change logging
    static let settings = Logger(subsystem: subsystem, category: "settings")
}

/// Log level configuration for debug mode support.
public enum LogLevel: String, Sendable {
    case `default`
    case info
    case debug

    /// UserDefaults key for log level configuration.
    public static let userDefaultsKey = "logLevel"

    /// The bundle identifier used for UserDefaults domain.
    public static let bundleIdentifier = "com.gcal-notifier"

    /// Reads the current log level from UserDefaults.
    /// Returns `.default` if not set or invalid.
    public static var current: LogLevel {
        guard let value = UserDefaults(suiteName: bundleIdentifier)?.string(forKey: userDefaultsKey),
              let level = LogLevel(rawValue: value)
        else {
            return .default
        }
        return level
    }

    /// Whether debug logging is currently enabled.
    public static var isDebugEnabled: Bool {
        current == .debug
    }
}

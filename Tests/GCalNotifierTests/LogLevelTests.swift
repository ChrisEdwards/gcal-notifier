import Foundation
import Testing

@testable import GCalNotifierCore

@Suite("LogLevel Tests")
struct LogLevelTests {
    @Test("Raw values are correct")
    func rawValues() {
        #expect(LogLevel.default.rawValue == "default")
        #expect(LogLevel.info.rawValue == "info")
        #expect(LogLevel.debug.rawValue == "debug")
    }

    @Test("UserDefaults key is correct")
    func userDefaultsKey() {
        #expect(LogLevel.userDefaultsKey == "logLevel")
    }

    @Test("Bundle identifier is correct")
    func bundleIdentifier() {
        #expect(LogLevel.bundleIdentifier == "com.gcal-notifier")
    }

    @Test("Initializes from valid raw value")
    func initFromRawValue() {
        #expect(LogLevel(rawValue: "default") == .default)
        #expect(LogLevel(rawValue: "info") == .info)
        #expect(LogLevel(rawValue: "debug") == .debug)
    }

    @Test("Returns nil for invalid raw value")
    func initFromInvalidRawValue() {
        #expect(LogLevel(rawValue: "invalid") == nil)
        #expect(LogLevel(rawValue: "") == nil)
        #expect(LogLevel(rawValue: "DEBUG") == nil)
    }
}

/// Tests that interact with UserDefaults must run serially to avoid interference
@Suite("LogLevel UserDefaults Tests", .serialized)
struct LogLevelUserDefaultsTests {
    private func clearLogLevel() {
        guard let defaults = UserDefaults(suiteName: LogLevel.bundleIdentifier) else { return }
        defaults.removeObject(forKey: LogLevel.userDefaultsKey)
        CFPreferencesAppSynchronize(LogLevel.bundleIdentifier as CFString)
    }

    private func setLogLevel(_ value: String) {
        guard let defaults = UserDefaults(suiteName: LogLevel.bundleIdentifier) else { return }
        defaults.set(value, forKey: LogLevel.userDefaultsKey)
        CFPreferencesAppSynchronize(LogLevel.bundleIdentifier as CFString)
    }

    @Test("Returns default when no value set")
    func defaultWhenNoValueSet() {
        self.clearLogLevel()

        #expect(LogLevel.current == .default)
        #expect(LogLevel.isDebugEnabled == false)
    }

    @Test("Reads debug level from UserDefaults")
    func readsDebugFromDefaults() {
        self.clearLogLevel()
        self.setLogLevel("debug")

        #expect(LogLevel.current == .debug)
        #expect(LogLevel.isDebugEnabled == true)

        self.clearLogLevel()
    }

    @Test("Reads info level from UserDefaults")
    func readsInfoFromDefaults() {
        self.clearLogLevel()
        self.setLogLevel("info")

        #expect(LogLevel.current == .info)
        #expect(LogLevel.isDebugEnabled == false)

        self.clearLogLevel()
    }

    @Test("Returns default for invalid UserDefaults value")
    func invalidDefaultsValue() {
        self.clearLogLevel()
        self.setLogLevel("invalid_level")

        #expect(LogLevel.current == .default)
        #expect(LogLevel.isDebugEnabled == false)

        self.clearLogLevel()
    }
}

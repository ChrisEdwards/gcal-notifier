import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates an isolated UserDefaults suite for test isolation.
/// Returns standard defaults if suite creation fails (should never happen in tests).
private func makeTestDefaults() -> UserDefaults {
    let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return .standard
    }
    return defaults
}

/// Cleans up a test UserDefaults suite.
private func cleanupTestDefaults(_ defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
}

// MARK: - Default Value Tests

@Suite("SettingsStore Default Values")
struct SettingsStoreDefaultValueTests {
    @Test("Default alertStage1Minutes is 10 minutes")
    func defaultAlertStage1_is10Minutes() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.alertStage1Minutes == 10)
    }

    @Test("Default alertStage2Minutes is 2 minutes")
    func defaultAlertStage2_is2Minutes() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.alertStage2Minutes == 2)
    }

    @Test("Default launchAtLogin is true")
    func defaultLaunchAtLogin_isTrue() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.launchAtLogin == true)
    }

    @Test("Default stage1Sound is glass")
    func stage1Sound_defaultsToGlass() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.stage1Sound == "glass")
    }

    @Test("Default stage2Sound is hero")
    func stage2Sound_defaultsToHero() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.stage2Sound == "hero")
    }

    @Test("Default customSoundPath is nil")
    func customSoundPath_defaultsToNil() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.customSoundPath == nil)
    }

    @Test("Default enabledCalendars is empty array")
    func enabledCalendars_defaultsToEmptyArray() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.enabledCalendars.isEmpty)
    }

    @Test("Default blockedKeywords is empty array")
    func blockedKeywords_defaultsToEmptyArray() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.blockedKeywords.isEmpty)
    }

    @Test("Default forceAlertKeywords contains Interview and IMPORTANT")
    func forceAlertKeywords_defaultsToInterviewAndImportant() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.forceAlertKeywords == ["Interview", "IMPORTANT"])
    }

    @Test("Default suppressDuringScreenShare is true")
    func suppressDuringScreenShare_defaultsToTrue() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.suppressDuringScreenShare == true)
    }

    @Test("Default shortcutsEnabled is true")
    func shortcutsEnabled_defaultsToTrue() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.shortcutsEnabled == true)
    }
}

// MARK: - Persistence Tests

@Suite("SettingsStore Persistence")
struct SettingsStorePersistenceTests {
    @Test("Alert timing persists")
    func alertTiming_persists() {
        let defaults = makeTestDefaults()

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.alertStage1Minutes = 15
            store.alertStage2Minutes = 5
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.alertStage1Minutes == 15)
            #expect(store.alertStage2Minutes == 5)
        }
    }

    @Test("Enabled calendars array persists")
    func enabledCalendars_persistsArray() {
        let defaults = makeTestDefaults()
        let calendars = ["primary", "work@example.com", "personal@example.com"]

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.enabledCalendars = calendars
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.enabledCalendars == calendars)
        }
    }

    @Test("Blocked keywords array persists")
    func blockedKeywords_persistsArray() {
        let defaults = makeTestDefaults()
        let keywords = ["lunch", "break", "optional"]

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.blockedKeywords = keywords
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.blockedKeywords == keywords)
        }
    }

    @Test("Force alert keywords array persists")
    func forceAlertKeywords_persistsArray() {
        let defaults = makeTestDefaults()
        let keywords = ["URGENT", "Interview", "Must Attend"]

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.forceAlertKeywords = keywords
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.forceAlertKeywords == keywords)
        }
    }

    @Test("Sound settings persist")
    func soundSettings_persist() {
        let defaults = makeTestDefaults()

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.stage1Sound = "soft-bell"
            store.stage2Sound = "alarm"
            store.customSoundPath = "/Users/test/sounds/custom.mp3"
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.stage1Sound == "soft-bell")
            #expect(store.stage2Sound == "alarm")
            #expect(store.customSoundPath == "/Users/test/sounds/custom.mp3")
        }
    }

    @Test("Optional values persist nil")
    func optionalValues_persistNil() {
        let defaults = makeTestDefaults()

        // Set then clear
        do {
            let store = SettingsStore(defaults: defaults)
            store.customSoundPath = "/some/path"
            store.customSoundPath = nil
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.customSoundPath == nil)
        }
    }

    @Test("Boolean values persist")
    func booleanValues_persist() {
        let defaults = makeTestDefaults()

        // Set values
        do {
            let store = SettingsStore(defaults: defaults)
            store.launchAtLogin = false
            store.suppressDuringScreenShare = false
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.launchAtLogin == false)
            #expect(store.suppressDuringScreenShare == false)
        }
    }

    @Test("Empty arrays persist correctly")
    func emptyArrays_persist() {
        let defaults = makeTestDefaults()

        // Set to non-empty then clear
        do {
            let store = SettingsStore(defaults: defaults)
            store.enabledCalendars = ["cal1", "cal2"]
            store.enabledCalendars = []
        }

        // Verify with new store instance
        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.enabledCalendars.isEmpty)
        }
    }
}

// MARK: - Value Update Tests

@Suite("SettingsStore Value Updates")
struct SettingsStoreValueUpdateTests {
    @Test("Alert timing values can be set to 0 (disabled)")
    func alertTiming_canBeDisabled() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        store.alertStage1Minutes = 0
        store.alertStage2Minutes = 0

        #expect(store.alertStage1Minutes == 0)
        #expect(store.alertStage2Minutes == 0)
    }

    @Test("Arrays can be appended to")
    func arrays_canBeModified() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        var calendars = store.enabledCalendars
        calendars.append("new-calendar")
        store.enabledCalendars = calendars

        #expect(store.enabledCalendars.contains("new-calendar"))
    }

    @Test("Multiple settings can be changed independently")
    func multipleSettings_independent() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        store.alertStage1Minutes = 20
        store.stage1Sound = "custom-sound"
        store.blockedKeywords = ["lunch"]
        store.launchAtLogin = false

        #expect(store.alertStage1Minutes == 20)
        #expect(store.alertStage2Minutes == 2) // Default unchanged
        #expect(store.stage1Sound == "custom-sound")
        #expect(store.stage2Sound == "hero") // Default unchanged
        #expect(store.blockedKeywords == ["lunch"])
        #expect(store.forceAlertKeywords == ["Interview", "IMPORTANT"]) // Default unchanged
        #expect(store.launchAtLogin == false)
        #expect(store.suppressDuringScreenShare == true) // Default unchanged
    }
}

// MARK: - JSON Encoding Tests

@Suite("SettingsStore JSON Encoding")
struct SettingsStoreJSONEncodingTests {
    @Test("Arrays with special characters persist")
    func arraysWithSpecialCharacters_persist() {
        let defaults = makeTestDefaults()
        let keywords = ["Meeting: Important!", "Team/Project", "Q&A Session"]

        do {
            let store = SettingsStore(defaults: defaults)
            store.blockedKeywords = keywords
        }

        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.blockedKeywords == keywords)
        }
    }

    @Test("Arrays with unicode persist")
    func arraysWithUnicode_persist() {
        let defaults = makeTestDefaults()
        let keywords = ["会议", "Réunion", "Совещание"]

        do {
            let store = SettingsStore(defaults: defaults)
            store.forceAlertKeywords = keywords
        }

        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.forceAlertKeywords == keywords)
        }
    }
}

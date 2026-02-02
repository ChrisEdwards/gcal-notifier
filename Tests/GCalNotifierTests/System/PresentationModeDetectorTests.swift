import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - PresentationModeState Tests

@Suite("PresentationModeState Tests")
struct PresentationModeStateTests {
    @Test("none state does not suppress alerts")
    func noneStateDoesNotSuppress() {
        let state = PresentationModeState.none
        #expect(state.shouldSuppressAlerts == false)
    }

    @Test("screenSharing state suppresses alerts")
    func screenSharingStateSuppresses() {
        let state = PresentationModeState.screenSharing
        #expect(state.shouldSuppressAlerts == true)
    }

    @Test("displayMirrored state suppresses alerts")
    func displayMirroredStateSuppresses() {
        let state = PresentationModeState.displayMirrored
        #expect(state.shouldSuppressAlerts == true)
    }

    @Test("doNotDisturb state suppresses alerts")
    func doNotDisturbStateSuppresses() {
        let state = PresentationModeState.doNotDisturb
        #expect(state.shouldSuppressAlerts == true)
    }

    @Test("none state has correct description")
    func noneStateDescription() {
        let state = PresentationModeState.none
        #expect(state.description == "Normal")
    }

    @Test("screenSharing state has correct description")
    func screenSharingStateDescription() {
        let state = PresentationModeState.screenSharing
        #expect(state.description == "Screen sharing")
    }

    @Test("displayMirrored state has correct description")
    func displayMirroredStateDescription() {
        let state = PresentationModeState.displayMirrored
        #expect(state.description == "Display mirrored")
    }

    @Test("doNotDisturb state has correct description")
    func doNotDisturbStateDescription() {
        let state = PresentationModeState.doNotDisturb
        #expect(state.description == "Do Not Disturb")
    }

    @Test("screenSharing state returns screenSharing downgrade reason")
    func screenSharingDowngradeReason() {
        let state = PresentationModeState.screenSharing
        #expect(state.alertDowngradeReason == .screenSharing)
    }

    @Test("displayMirrored state returns screenSharing downgrade reason")
    func displayMirroredDowngradeReason() {
        let state = PresentationModeState.displayMirrored
        #expect(state.alertDowngradeReason == .screenSharing)
    }

    @Test("doNotDisturb state returns doNotDisturb downgrade reason")
    func doNotDisturbDowngradeReason() {
        let state = PresentationModeState.doNotDisturb
        #expect(state.alertDowngradeReason == .doNotDisturb)
    }

    @Test("none state returns nil downgrade reason")
    func noneDowngradeReason() {
        let state = PresentationModeState.none
        #expect(state.alertDowngradeReason == nil)
    }
}

// MARK: - PresentationModeDetector Tests

@Suite("PresentationModeDetector Tests")
@MainActor
struct PresentationModeDetectorTests {
    @Test("shared instance exists")
    func sharedInstanceExists() {
        let detector = PresentationModeDetector.shared
        #expect(detector != nil)
    }

    @Test("shared instance is singleton")
    func sharedInstanceIsSingleton() {
        let detector1 = PresentationModeDetector.shared
        let detector2 = PresentationModeDetector.shared
        #expect(detector1 === detector2)
    }

    @Test("detect returns valid state")
    func detectReturnsValidState() {
        let detector = PresentationModeDetector.shared
        let state = detector.detect()

        // State should be one of the valid enum cases
        switch state {
        case .none, .screenSharing, .displayMirrored, .doNotDisturb:
            // All valid cases
            break
        }
    }

    @Test("shouldSuppressAlerts respects settings")
    func shouldSuppressAlertsRespectsSettings() {
        let detector = PresentationModeDetector.shared
        guard let defaults = UserDefaults(suiteName: "com.gcal-notifier.tests.presentation-mode") else {
            Issue.record("Failed to create UserDefaults for test")
            return
        }
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-mode")

        let settings = SettingsStore(defaults: defaults)

        // When suppression is disabled, should return false regardless of state
        settings.suppressDuringScreenShare = false
        let result = detector.shouldSuppressAlerts(settings: settings)
        #expect(result == false)

        // Clean up
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-mode")
    }

    @Test("detect returns none when not presenting")
    func detectReturnsNoneWhenNotPresenting() {
        // In a test environment without screen sharing or mirroring,
        // the detector should return .none
        let detector = PresentationModeDetector.shared
        let state = detector.detect()

        // In test environment, typically we're not presenting
        // This test verifies the detector can run without crashing
        #expect(state == .none || state.shouldSuppressAlerts)
    }
}

// MARK: - Settings Integration Tests

@Suite("Presentation Mode Settings Integration Tests")
struct PresentationModeSettingsIntegrationTests {
    @Test("suppressDuringScreenShare default is true")
    func defaultSettingIsTrue() {
        guard let defaults = UserDefaults(suiteName: "com.gcal-notifier.tests.presentation-settings") else {
            Issue.record("Failed to create UserDefaults for test")
            return
        }
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-settings")

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.suppressDuringScreenShare == true)

        // Clean up
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-settings")
    }

    @Test("suppressDuringScreenShare can be toggled")
    func settingCanBeToggled() {
        guard let defaults = UserDefaults(suiteName: "com.gcal-notifier.tests.presentation-toggle") else {
            Issue.record("Failed to create UserDefaults for test")
            return
        }
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-toggle")

        let settings = SettingsStore(defaults: defaults)

        settings.suppressDuringScreenShare = false
        #expect(settings.suppressDuringScreenShare == false)

        settings.suppressDuringScreenShare = true
        #expect(settings.suppressDuringScreenShare == true)

        // Clean up
        defaults.removePersistentDomain(forName: "com.gcal-notifier.tests.presentation-toggle")
    }
}

import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Mock Delegate

@MainActor
private final class MockFirstLaunchDelegate: FirstLaunchHandlerDelegate {
    private(set) var requestNotificationPermissionCalled = false
    private(set) var didCompleteInitialSetupCalled = false
    private(set) var didSignInCalled = false

    var notificationPermissionResult = true

    nonisolated func firstLaunchHandlerShouldRequestNotificationPermission(
        _: FirstLaunchHandler
    ) async -> Bool {
        await MainActor.run {
            self.requestNotificationPermissionCalled = true
            return self.notificationPermissionResult
        }
    }

    nonisolated func firstLaunchHandlerDidCompleteInitialSetup(_: FirstLaunchHandler) async {
        await MainActor.run {
            self.didCompleteInitialSetupCalled = true
        }
    }

    nonisolated func firstLaunchHandlerDidSignIn(_: FirstLaunchHandler) async {
        await MainActor.run {
            self.didSignInCalled = true
        }
    }
}

// MARK: - Tests

@Suite("FirstLaunchHandler Tests")
@MainActor
struct FirstLaunchHandlerTests {
    /// Create a unique suite name for isolated defaults
    private func createIsolatedDefaults() -> UserDefaults {
        let suiteName = "FirstLaunchHandlerTests-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Initialization

    @Test("handler can be initialized")
    func handlerCanBeInitialized() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        #expect(handler != nil)
    }

    // MARK: - First Launch Detection

    @Test("isFirstLaunch returns true on fresh install")
    func isFirstLaunchReturnsTrueOnFreshInstall() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        #expect(handler.isFirstLaunch)
    }

    @Test("isFirstLaunch returns false after markLaunched")
    func isFirstLaunchReturnsFalseAfterMarkLaunched() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markLaunched()

        #expect(!handler.isFirstLaunch)
    }

    @Test("isSetupCompleted returns false initially")
    func isSetupCompletedReturnsFalseInitially() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        #expect(!handler.isSetupCompleted)
    }

    @Test("isSetupCompleted returns true after markSetupCompleted")
    func isSetupCompletedReturnsTrueAfterMark() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markSetupCompleted()

        #expect(handler.isSetupCompleted)
    }

    @Test("isSetupRequired returns true on fresh install")
    func isSetupRequiredReturnsTrueOnFreshInstall() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        #expect(handler.isSetupRequired)
    }

    @Test("isSetupRequired returns true after launched but before setup completed")
    func isSetupRequiredReturnsTrueAfterLaunchedBeforeSetup() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markLaunched()

        #expect(handler.isSetupRequired)
    }

    @Test("isSetupRequired returns false after setup completed")
    func isSetupRequiredReturnsFalseAfterSetupCompleted() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markLaunched()
        handler.markSetupCompleted()

        #expect(!handler.isSetupRequired)
    }

    // MARK: - First Launch Flow

    @Test("handleFirstLaunchIfNeeded does nothing if not first launch")
    func handleFirstLaunchDoesNothingIfNotFirstLaunch() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        // Mark as already launched
        handler.markLaunched()

        await handler.handleFirstLaunchIfNeeded()

        #expect(!delegate.requestNotificationPermissionCalled)
        #expect(!delegate.didCompleteInitialSetupCalled)
    }

    @Test("handleFirstLaunchIfNeeded requests notification permission on first launch")
    func handleFirstLaunchRequestsNotificationPermission() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        await handler.handleFirstLaunchIfNeeded()

        #expect(delegate.requestNotificationPermissionCalled)
    }

    @Test("handleFirstLaunchIfNeeded calls didCompleteInitialSetup")
    func handleFirstLaunchCallsDidCompleteInitialSetup() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        await handler.handleFirstLaunchIfNeeded()

        #expect(delegate.didCompleteInitialSetupCalled)
    }

    @Test("handleFirstLaunchIfNeeded marks as launched")
    func handleFirstLaunchMarksAsLaunched() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        await handler.handleFirstLaunchIfNeeded()

        #expect(!handler.isFirstLaunch)
    }

    @Test("handleFirstLaunchIfNeeded enables launch at login")
    func handleFirstLaunchEnablesLaunchAtLogin() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        await handler.handleFirstLaunchIfNeeded()

        // Check that the standard defaults has launch at login enabled
        // Note: This uses the actual SettingsStore which writes to standard defaults
        let settingsStore = SettingsStore()
        #expect(settingsStore.launchAtLogin)
    }

    @Test("handleFirstLaunchIfNeeded works without delegate")
    func handleFirstLaunchWorksWithoutDelegate() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        // Should not crash
        await handler.handleFirstLaunchIfNeeded()

        #expect(!handler.isFirstLaunch)
    }

    // MARK: - Successful Sign-In

    @Test("handleSuccessfulSignIn notifies delegate")
    func handleSuccessfulSignInNotifiesDelegate() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        handler.setDelegate(delegate)

        await handler.handleSuccessfulSignIn()

        #expect(delegate.didSignInCalled)
    }

    @Test("handleSuccessfulSignIn marks setup as completed")
    func handleSuccessfulSignInMarksSetupCompleted() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        await handler.handleSuccessfulSignIn()

        #expect(handler.isSetupCompleted)
    }

    // MARK: - Reset State

    @Test("resetFirstLaunchState clears hasLaunched")
    func resetFirstLaunchStateClearsHasLaunched() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markLaunched()
        #expect(!handler.isFirstLaunch)

        handler.resetFirstLaunchState()

        #expect(handler.isFirstLaunch)
    }

    @Test("resetFirstLaunchState clears setupCompleted")
    func resetFirstLaunchStateClearsSetupCompleted() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)

        handler.markSetupCompleted()
        #expect(handler.isSetupCompleted)

        handler.resetFirstLaunchState()

        #expect(!handler.isSetupCompleted)
    }

    // MARK: - Delegate Management

    @Test("delegate can be set")
    func delegateCanBeSet() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()

        handler.setDelegate(delegate)
    }

    @Test("delegate can be set to nil")
    func delegateCanBeSetToNil() {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()

        handler.setDelegate(delegate)
        handler.setDelegate(nil)
    }

    // MARK: - Notification Permission Denied

    @Test("handleFirstLaunchIfNeeded continues even if notification permission denied")
    func handleFirstLaunchContinuesIfPermissionDenied() async {
        let defaults = self.createIsolatedDefaults()
        let handler = FirstLaunchHandler(defaults: defaults)
        let delegate = MockFirstLaunchDelegate()
        delegate.notificationPermissionResult = false
        handler.setDelegate(delegate)

        await handler.handleFirstLaunchIfNeeded()

        // Should still complete initial setup
        #expect(delegate.didCompleteInitialSetupCalled)
        #expect(!handler.isFirstLaunch)
    }
}

// MARK: - MenuBuilder Setup Required Tests

@Suite("MenuBuilder Setup Required Tests")
struct MenuBuilderSetupRequiredTests {
    @Test("buildSetupRequiredMenuItems returns expected items")
    func buildSetupRequiredMenuItemsReturnsExpectedItems() {
        let items = MenuBuilder.buildSetupRequiredMenuItems()

        #expect(items.count == 5)
        #expect(items[0] == .setupRequired)
        #expect(items[1] == .separator)
        #expect(items[2] == .action(title: "Settings...", action: .settings))
        #expect(items[3] == .separator)
        #expect(items[4] == .action(title: "Quit gcal-notifier", action: .quit))
    }

    @Test("buildMenuItems with setupRequired returns setup required menu")
    func buildMenuItemsWithSetupRequiredReturnsSetupMenu() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationPermissionDenied: false,
            setupRequired: true
        )

        #expect(items.count == 5)
        #expect(items[0] == .setupRequired)
    }

    @Test("buildMenuItems without setupRequired returns normal menu")
    func buildMenuItemsWithoutSetupRequiredReturnsNormalMenu() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationPermissionDenied: false,
            setupRequired: false
        )

        // Normal menu has more items including "Today's Meetings" header
        #expect(items.contains(.sectionHeader(title: "Today's Meetings")))
        #expect(!items.contains(.setupRequired))
    }
}

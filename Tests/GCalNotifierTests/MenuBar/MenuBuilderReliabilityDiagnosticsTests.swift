import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

@Suite("MenuBuilder Reliability Diagnostics Tests")
struct MenuBuilderReliabilityDiagnosticsTests {
    @Test("Shows notification warning when permission is unavailable")
    func showsNotificationWarningWhenPermissionUnavailable() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationAuthorizationStatus: .notDetermined
        )

        guard case .notificationWarning = items[0] else {
            Issue.record("Expected notificationWarning item first")
            return
        }
    }

    @Test("Restored notification permission hides durable delivery warning")
    func restoredNotificationPermissionHidesDurableDeliveryWarning() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationAuthorizationStatus: .authorized
        )

        #expect(!items.contains { if case .notificationWarning = $0 { return true }; return false })
    }

    @Test("Shows launch-at-login warning when disabled")
    func showsLaunchAtLoginWarningWhenDisabled() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            launchAtLoginStatus: .disabled
        )

        guard case let .launchAtLoginWarning(status) = items[0] else {
            Issue.record("Expected launchAtLoginWarning item first")
            return
        }
        #expect(status == .disabled)
    }

    @Test("Shows launch-at-login warning when approval is required")
    func showsLaunchAtLoginWarningWhenApprovalRequired() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            launchAtLoginStatus: .requiresApproval
        )

        guard case let .launchAtLoginWarning(status) = items[0] else {
            Issue.record("Expected launchAtLoginWarning item first")
            return
        }
        #expect(status == .requiresApproval)
    }

    @Test("No launch-at-login warning when enabled")
    func noLaunchAtLoginWarningWhenEnabled() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            launchAtLoginStatus: .enabled
        )

        #expect(!items.contains { if case .launchAtLoginWarning = $0 { return true }; return false })
    }
}

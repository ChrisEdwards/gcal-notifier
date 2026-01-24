import Foundation
import Testing
@preconcurrency import UserNotifications

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Mock Notification Center

/// Mock notification center for permission testing.
final class MockPermissionNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    private var _requestAuthorizationCalled = false
    private var _requestAuthorizationResult = true

    var authorizationStatus: NotificationAuthorizationStatus {
        get { self.lock.withLock { self._authorizationStatus } }
        set { self.lock.withLock { self._authorizationStatus = newValue } }
    }

    var requestAuthorizationCalled: Bool {
        self.lock.withLock { self._requestAuthorizationCalled }
    }

    var requestAuthorizationResult: Bool {
        get { self.lock.withLock { self._requestAuthorizationResult } }
        set { self.lock.withLock { self._requestAuthorizationResult = newValue } }
    }

    func add(_: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers _: [String]) {}
    func removeAllPendingNotificationRequests() {}
    func removeDeliveredNotifications(withIdentifiers _: [String]) {}
    func removeAllDeliveredNotifications() {}
    func setNotificationCategories(_: Set<UNNotificationCategory>) {}
    func setDelegate(_: any UNUserNotificationCenterDelegate) {}

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        self.lock.withLock {
            self._requestAuthorizationCalled = true
            return self._requestAuthorizationResult
        }
    }

    func notificationSettings() async -> NotificationAuthorizationStatus {
        self.lock.withLock { self._authorizationStatus }
    }
}

// MARK: - Mock Delegate

@MainActor
private final class MockPermissionDelegate: NotificationPermissionHandlerDelegate {
    private(set) var statusChanges: [(isGranted: Bool, count: Int)] = []

    nonisolated func permissionStatusDidChange(_: NotificationPermissionHandler, isGranted: Bool) async {
        await MainActor.run {
            let count = self.statusChanges.count + 1
            self.statusChanges.append((isGranted: isGranted, count: count))
        }
    }
}

// MARK: - Tests

@Suite("NotificationPermissionHandler Tests")
@MainActor
struct NotificationPermissionHandlerTests {
    // MARK: - Initialization

    @Test("handler can be initialized")
    func handlerCanBeInitialized() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        #expect(handler != nil)
    }

    @Test("initial status is notDetermined")
    func initialStatusIsNotDetermined() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        #expect(handler.authorizationStatus == .notDetermined)
        #expect(handler.isNotDetermined)
    }

    // MARK: - Permission Checking

    @Test("checkPermission returns current status")
    func checkPermissionReturnsCurrentStatus() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .authorized

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let status = await handler.checkPermission()

        #expect(status == .authorized)
        #expect(handler.authorizationStatus == .authorized)
    }

    @Test("permissionDenied is true when status is denied")
    func permissionDeniedIsTrueWhenDenied() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .denied

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        await handler.checkPermission()

        #expect(handler.permissionDenied)
        #expect(!handler.isAuthorized)
    }

    @Test("isAuthorized is true when status is authorized")
    func isAuthorizedIsTrueWhenAuthorized() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .authorized

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        await handler.checkPermission()

        #expect(handler.isAuthorized)
        #expect(!handler.permissionDenied)
    }

    @Test("isAuthorized is true when status is provisional")
    func isAuthorizedIsTrueWhenProvisional() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .provisional

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        await handler.checkPermission()

        #expect(handler.isAuthorized)
    }

    // MARK: - Delegate Notifications

    @Test("delegate is notified when status changes")
    func delegateIsNotifiedWhenStatusChanges() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .notDetermined

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let delegate = MockPermissionDelegate()
        handler.setDelegate(delegate)

        // First check - sets initial status
        await handler.checkPermission()

        // Change status
        mockCenter.authorizationStatus = .authorized
        await handler.checkPermission()

        #expect(delegate.statusChanges.count >= 1)
        if let lastChange = delegate.statusChanges.last {
            #expect(lastChange.isGranted)
        }
    }

    @Test("delegate is not notified when status stays the same")
    func delegateIsNotNotifiedWhenStatusStaysSame() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.authorizationStatus = .authorized

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let delegate = MockPermissionDelegate()
        handler.setDelegate(delegate)

        await handler.checkPermission()
        let countAfterFirst = delegate.statusChanges.count

        // Check again with same status
        await handler.checkPermission()

        #expect(delegate.statusChanges.count == countAfterFirst)
    }

    // MARK: - Authorization Request

    @Test("requestAuthorization calls notification center")
    func requestAuthorizationCallsNotificationCenter() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.requestAuthorizationResult = true
        mockCenter.authorizationStatus = .authorized

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let granted = await handler.requestAuthorization()

        #expect(granted)
        #expect(mockCenter.requestAuthorizationCalled)
    }

    @Test("requestAuthorization returns false when denied")
    func requestAuthorizationReturnsFalseWhenDenied() async {
        let mockCenter = MockPermissionNotificationCenter()
        mockCenter.requestAuthorizationResult = false
        mockCenter.authorizationStatus = .denied

        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let granted = await handler.requestAuthorization()

        #expect(!granted)
    }

    // MARK: - Monitoring

    @Test("startMonitoring can be called")
    func startMonitoringCanBeCalled() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)

        handler.startMonitoring()
        handler.stopMonitoring()
    }

    @Test("startMonitoring is idempotent")
    func startMonitoringIsIdempotent() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)

        handler.startMonitoring()
        handler.startMonitoring() // Should be no-op
        handler.stopMonitoring()
    }

    @Test("stopMonitoring is idempotent")
    func stopMonitoringIsIdempotent() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)

        handler.startMonitoring()
        handler.stopMonitoring()
        handler.stopMonitoring() // Should be no-op
    }

    @Test("stopMonitoring can be called without starting")
    func stopMonitoringCanBeCalledWithoutStarting() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)

        handler.stopMonitoring()
    }

    // MARK: - Delegate Management

    @Test("delegate can be set")
    func delegateCanBeSet() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let delegate = MockPermissionDelegate()

        handler.setDelegate(delegate)
    }

    @Test("delegate can be set to nil")
    func delegateCanBeSetToNil() async {
        let mockCenter = MockPermissionNotificationCenter()
        let handler = NotificationPermissionHandler(notificationCenter: mockCenter)
        let delegate = MockPermissionDelegate()

        handler.setDelegate(delegate)
        handler.setDelegate(nil)
    }
}

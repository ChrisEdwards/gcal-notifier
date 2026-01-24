import Foundation
import Testing
@preconcurrency import UserNotifications

@testable import GCalNotifierCore

// MARK: - Captured Request Data

/// Sendable struct to capture notification request data for testing.
struct CapturedNotificationRequest: Sendable {
    let identifier: String
    let categoryIdentifier: String
    let soundIsNil: Bool
    let triggerYear: Int?
    let triggerMonth: Int?
    let triggerDay: Int?
    let triggerHour: Int?
    let triggerMinute: Int?
    let triggerRepeats: Bool?

    init(from request: UNNotificationRequest) {
        self.identifier = request.identifier
        self.categoryIdentifier = request.content.categoryIdentifier
        self.soundIsNil = request.content.sound == nil

        if let trigger = request.trigger as? UNCalendarNotificationTrigger {
            self.triggerYear = trigger.dateComponents.year
            self.triggerMonth = trigger.dateComponents.month
            self.triggerDay = trigger.dateComponents.day
            self.triggerHour = trigger.dateComponents.hour
            self.triggerMinute = trigger.dateComponents.minute
            self.triggerRepeats = trigger.repeats
        } else {
            self.triggerYear = nil
            self.triggerMonth = nil
            self.triggerDay = nil
            self.triggerHour = nil
            self.triggerMinute = nil
            self.triggerRepeats = nil
        }
    }
}

// MARK: - Mock Notification Center

/// Thread-safe storage for mock notification center state.
final class MockNotificationCenterStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _pendingRequests: [CapturedNotificationRequest] = []
    private var _removedIdentifiers: [String] = []
    private var _registeredCategoryIdentifiers: [String] = []
    private var _addCallCount = 0
    private var _delegateSet = false
    private var _authorizationStatus: NotificationAuthorizationStatus = .authorized
    private var _addError: Error?

    var pendingRequests: [CapturedNotificationRequest] { self.lock.withLock { self._pendingRequests } }

    var removedIdentifiers: [String] { self.lock.withLock { self._removedIdentifiers } }

    var registeredCategoryIdentifiers: [String] { self.lock.withLock { self._registeredCategoryIdentifiers } }

    var addCallCount: Int { self.lock.withLock { self._addCallCount } }

    var delegateSet: Bool { self.lock.withLock { self._delegateSet } }

    var authorizationStatus: NotificationAuthorizationStatus {
        get { self.lock.withLock { self._authorizationStatus } }
        set { self.lock.withLock { self._authorizationStatus = newValue } }
    }

    var addError: Error? {
        get { self.lock.withLock { self._addError } }
        set { self.lock.withLock { self._addError = newValue } }
    }

    func addRequest(_ request: CapturedNotificationRequest) {
        self.lock.withLock {
            self._addCallCount += 1
            self._pendingRequests.append(request)
        }
    }

    func incrementAddCount() {
        self.lock.withLock { self._addCallCount += 1 }
    }

    func removePending(identifiers: [String]) {
        self.lock.withLock {
            self._pendingRequests.removeAll { identifiers.contains($0.identifier) }
            self._removedIdentifiers.append(contentsOf: identifiers)
        }
    }

    func removeAllPending() {
        self.lock.withLock { self._pendingRequests.removeAll() }
    }

    func addRemovedIdentifiers(_ identifiers: [String]) {
        self.lock.withLock { self._removedIdentifiers.append(contentsOf: identifiers) }
    }

    func setCategories(_ identifiers: [String]) {
        self.lock.withLock { self._registeredCategoryIdentifiers = identifiers }
    }

    func markDelegateSet() {
        self.lock.withLock { self._delegateSet = true }
    }
}

/// Mock notification center for testing without real system notifications.
final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    let storage = MockNotificationCenterStorage()

    var pendingRequests: [CapturedNotificationRequest] { self.storage.pendingRequests }
    var removedIdentifiers: [String] { self.storage.removedIdentifiers }
    var registeredCategoryIdentifiers: [String] { self.storage.registeredCategoryIdentifiers }
    var addCallCount: Int { self.storage.addCallCount }
    var delegateSet: Bool { self.storage.delegateSet }

    func add(_ request: UNNotificationRequest) async throws {
        if let error = storage.addError {
            self.storage.incrementAddCount()
            throw error
        }
        let captured = CapturedNotificationRequest(from: request)
        self.storage.addRequest(captured)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        self.storage.removePending(identifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        self.storage.removeAllPending()
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        self.storage.addRemovedIdentifiers(identifiers)
    }

    func removeAllDeliveredNotifications() {
        // No-op for mock
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        let identifiers = categories.map(\.identifier)
        self.storage.setCategories(identifiers)
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        self.storage.authorizationStatus == .authorized
    }

    func notificationSettings() async -> NotificationAuthorizationStatus {
        self.storage.authorizationStatus
    }

    func setDelegate(_: any UNUserNotificationCenterDelegate) {
        self.storage.markDelegateSet()
    }

    func setAuthorizationStatus(_ status: NotificationAuthorizationStatus) {
        self.storage.authorizationStatus = status
    }
}

// MARK: - NotificationScheduler Tests

@Suite("NotificationScheduler Tests")
struct NotificationSchedulerTests {
    @Test("Schedule creates notification request with correct identifier")
    func scheduleCreatesRequestWithCorrectIdentifier() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-1", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        #expect(requests.count == 1)
        #expect(requests.first?.identifier == "test-alert-1")
    }

    @Test("Schedule creates notification with correct category")
    func scheduleCreatesRequestWithCorrectCategory() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-2", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first
        #expect(request?.categoryIdentifier == NotificationScheduler.meetingAlertCategory)
    }

    @Test("Schedule creates notification with silent sound")
    func scheduleCreatesRequestWithSilentSound() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-3", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first
        #expect(request?.soundIsNil == true)
    }

    @Test("Schedule creates calendar trigger with correct date")
    func scheduleCreatesCalendarTriggerWithCorrectDate() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let calendar = Calendar.current
        guard let fireDate = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 0)
        ) else {
            Issue.record("Failed to create test date")
            return
        }

        await scheduler.schedule(alertId: "test-alert-4", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first

        #expect(request?.triggerYear == 2026)
        #expect(request?.triggerMonth == 6)
        #expect(request?.triggerDay == 15)
        #expect(request?.triggerHour == 14)
        #expect(request?.triggerMinute == 30)
        #expect(request?.triggerRepeats == false)
    }

    @Test("Cancel removes pending notification")
    func cancelRemovesPendingNotification() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-5", fireDate: fireDate) {}

        let requestsBefore = mockCenter.pendingRequests
        #expect(requestsBefore.count == 1)

        await scheduler.cancel(alertId: "test-alert-5")

        let removedIds = mockCenter.removedIdentifiers
        #expect(removedIds.contains("test-alert-5"))
    }

    @Test("CancelAll removes all pending notifications")
    func cancelAllRemovesAllPendingNotifications() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-7a", fireDate: fireDate) {}
        await scheduler.schedule(alertId: "test-alert-7b", fireDate: fireDate) {}
        await scheduler.schedule(alertId: "test-alert-7c", fireDate: fireDate) {}

        let requestsBefore = mockCenter.pendingRequests
        #expect(requestsBefore.count == 3)

        await scheduler.cancelAll()

        let requestsAfter = mockCenter.pendingRequests
        #expect(requestsAfter.isEmpty)
    }

    @Test("Categories are registered on initialization")
    func categoriesAreRegisteredOnInitialization() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        _ = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let categoryIds = mockCenter.registeredCategoryIdentifiers
        #expect(categoryIds.count == 2)
        #expect(categoryIds.contains(NotificationScheduler.meetingAlertCategory))
        #expect(categoryIds.contains(NotificationScheduler.backToBackAlertCategory))
    }

    @Test("Delegate is set on initialization")
    func delegateIsSetOnInitialization() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        _ = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let delegateSet = mockCenter.delegateSet
        #expect(delegateSet)
    }

    @Test("Authorization status returns correct value")
    func authorizationStatusReturnsCorrectValue() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        mockCenter.setAuthorizationStatus(.denied)
        let status = await scheduler.authorizationStatus()
        #expect(status == .denied)
    }
}

// MARK: - NotificationDelegate Tests

@Suite("NotificationDelegate Tests")
struct NotificationDelegateTests {
    @Test("Register stores handler for alert ID")
    func registerStoresHandler() async throws {
        let delegate = NotificationDelegate()
        let handlerCalled = SendableBox(false)

        await delegate.register(alertId: "delegate-test-1") {
            handlerCalled.value = true
        }

        // Verify handler can be fired
        await delegate.testFireHandler(alertId: "delegate-test-1")
        #expect(handlerCalled.value)
    }

    @Test("Handler is removed after firing")
    func handlerIsRemovedAfterFiring() async throws {
        let delegate = NotificationDelegate()
        let callCount = SendableBox(0)

        await delegate.register(alertId: "delegate-test-2") {
            callCount.value += 1
        }

        await delegate.testFireHandler(alertId: "delegate-test-2")
        await delegate.testFireHandler(alertId: "delegate-test-2")

        #expect(callCount.value == 1)
    }

    @Test("Unregister removes handler")
    func unregisterRemovesHandler() async throws {
        let delegate = NotificationDelegate()
        let handlerCalled = SendableBox(false)

        await delegate.register(alertId: "delegate-test-3") {
            handlerCalled.value = true
        }

        await delegate.unregister(alertId: "delegate-test-3")
        await delegate.testFireHandler(alertId: "delegate-test-3")

        #expect(!handlerCalled.value)
    }

    @Test("UnregisterAll removes all handlers")
    func unregisterAllRemovesAllHandlers() async throws {
        let delegate = NotificationDelegate()
        let count = SendableBox(0)

        await delegate.register(alertId: "delegate-test-4a") { count.value += 1 }
        await delegate.register(alertId: "delegate-test-4b") { count.value += 1 }
        await delegate.register(alertId: "delegate-test-4c") { count.value += 1 }

        await delegate.unregisterAll()

        await delegate.testFireHandler(alertId: "delegate-test-4a")
        await delegate.testFireHandler(alertId: "delegate-test-4b")
        await delegate.testFireHandler(alertId: "delegate-test-4c")

        #expect(count.value == 0)
    }

    @Test("Firing unknown alert ID does nothing")
    func firingUnknownAlertDoesNothing() async throws {
        let delegate = NotificationDelegate()
        // Should not throw or crash
        await delegate.testFireHandler(alertId: "nonexistent-alert")
    }
}

// MARK: - NotificationAuthorizationStatus Tests

@Suite("NotificationAuthorizationStatus Tests")
struct NotificationAuthorizationStatusTests {
    @Test("Conversion from UNAuthorizationStatus")
    func conversionFromUNAuthorizationStatus() {
        #expect(NotificationAuthorizationStatus(from: .notDetermined) == .notDetermined)
        #expect(NotificationAuthorizationStatus(from: .denied) == .denied)
        #expect(NotificationAuthorizationStatus(from: .authorized) == .authorized)
        #expect(NotificationAuthorizationStatus(from: .provisional) == .provisional)
        // Note: .ephemeral is not available on macOS
    }
}

// MARK: - Test Helpers

/// Thread-safe box for use in async closures.
final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    var value: T {
        get {
            self.lock.lock()
            defer { lock.unlock() }
            return self._value
        }
        set {
            self.lock.lock()
            defer { lock.unlock() }
            self._value = newValue
        }
    }

    init(_ value: T) {
        self._value = value
    }
}

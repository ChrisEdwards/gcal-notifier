import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import GCalNotifierCore

// MARK: - Mock Dependencies

struct CapturedNotificationRequest {
    let identifier: String
    let title: String
    let body: String
    let categoryIdentifier: String
    let soundIsNil: Bool
    let isActive: Bool
    let isTimeSensitive: Bool
    let userInfo: [String: String]
    let triggerYear: Int?
    let triggerMonth: Int?
    let triggerDay: Int?
    let triggerHour: Int?
    let triggerMinute: Int?
    let triggerSecond: Int?
    let triggerRepeats: Bool?

    init(from request: UNNotificationRequest) {
        self.identifier = request.identifier
        self.title = request.content.title
        self.body = request.content.body
        self.categoryIdentifier = request.content.categoryIdentifier
        self.soundIsNil = request.content.sound == nil
        self.isActive = request.content.interruptionLevel == .active
        self.isTimeSensitive = request.content.interruptionLevel == .timeSensitive
        self.userInfo = Self.stringUserInfo(from: request.content.userInfo)

        if let trigger = request.trigger as? UNCalendarNotificationTrigger {
            self.triggerYear = trigger.dateComponents.year
            self.triggerMonth = trigger.dateComponents.month
            self.triggerDay = trigger.dateComponents.day
            self.triggerHour = trigger.dateComponents.hour
            self.triggerMinute = trigger.dateComponents.minute
            self.triggerSecond = trigger.dateComponents.second
            self.triggerRepeats = trigger.repeats
        } else {
            self.triggerYear = nil
            self.triggerMonth = nil
            self.triggerDay = nil
            self.triggerHour = nil
            self.triggerMinute = nil
            self.triggerSecond = nil
            self.triggerRepeats = nil
        }
    }

    private static func stringUserInfo(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            values[key] = String(describing: value)
        }
        return values
    }
}

final class MockNotificationCenterStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _pendingRequests: [CapturedNotificationRequest] = []
    private var _removedPendingIdentifiers: [String] = []
    private var _removedDeliveredIdentifiers: [String] = []
    private var _registeredCategoryIdentifiers: [String] = []
    private var _addCallCount = 0
    private var _delegateSet = false
    private var _authorizationStatus: NotificationAuthorizationStatus = .authorized
    private var _addError: Error?

    var pendingRequests: [CapturedNotificationRequest] {
        self.lock.withLock { self._pendingRequests }
    }

    var removedPendingIdentifiers: [String] {
        self.lock.withLock { self._removedPendingIdentifiers }
    }

    var removedDeliveredIdentifiers: [String] {
        self.lock.withLock { self._removedDeliveredIdentifiers }
    }

    var registeredCategoryIdentifiers: [String] {
        self.lock.withLock { self._registeredCategoryIdentifiers }
    }

    var addCallCount: Int {
        self.lock.withLock { self._addCallCount }
    }

    var delegateSet: Bool {
        self.lock.withLock { self._delegateSet }
    }

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
            self._removedPendingIdentifiers.append(contentsOf: identifiers)
        }
    }

    func removeAllPending() {
        self.lock.withLock { self._pendingRequests.removeAll() }
    }

    func addRemovedDeliveredIdentifiers(_ identifiers: [String]) {
        self.lock.withLock { self._removedDeliveredIdentifiers.append(contentsOf: identifiers) }
    }

    func setCategories(_ identifiers: [String]) {
        self.lock.withLock { self._registeredCategoryIdentifiers = identifiers }
    }

    func markDelegateSet() {
        self.lock.withLock { self._delegateSet = true }
    }
}

final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    let storage = MockNotificationCenterStorage()

    var pendingRequests: [CapturedNotificationRequest] {
        self.storage.pendingRequests
    }

    var removedPendingIdentifiers: [String] {
        self.storage.removedPendingIdentifiers
    }

    var removedDeliveredIdentifiers: [String] {
        self.storage.removedDeliveredIdentifiers
    }

    var registeredCategoryIdentifiers: [String] {
        self.storage.registeredCategoryIdentifiers
    }

    var addCallCount: Int {
        self.storage.addCallCount
    }

    var delegateSet: Bool {
        self.storage.delegateSet
    }

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
        self.storage.addRemovedDeliveredIdentifiers(identifiers)
    }

    func removeAllDeliveredNotifications() {}

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

struct ScheduledAlertHandler {
    let alertId: String
    let fireDate: Date
    let handler: @Sendable () -> Void
}

/// Mock scheduler that tracks scheduled and cancelled alerts.
actor MockAlertScheduler: AlertScheduler {
    private(set) var scheduledAlerts: [(alertId: String, fireDate: Date)] = []
    private(set) var cancelledAlertIds: [String] = []
    private var handlers: [String: @Sendable () -> Void] = [:]
    private var scheduledHandlers: [ScheduledAlertHandler] = []

    func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) {
        self.scheduledAlerts.append((alertId, fireDate))
        self.scheduledHandlers.append(ScheduledAlertHandler(alertId: alertId, fireDate: fireDate, handler: handler))
        self.handlers[alertId] = handler
    }

    func cancel(alertId: String) {
        self.cancelledAlertIds.append(alertId)
        self.handlers.removeValue(forKey: alertId)
    }

    func cancelAll() {
        for alertId in self.handlers.keys {
            self.cancelledAlertIds.append(alertId)
        }
        self.handlers.removeAll()
    }

    func fireAlert(alertId: String) {
        self.handlers[alertId]?()
    }

    func firstHandler(alertId: String) -> (@Sendable () -> Void)? {
        self.scheduledHandlers.first { $0.alertId == alertId }?.handler
    }

    func reset() {
        self.scheduledAlerts = []
        self.cancelledAlertIds = []
        self.handlers.removeAll()
        self.scheduledHandlers.removeAll()
    }
}

/// Mock delivery that tracks delivered alerts.
actor MockAlertDelivery: AlertDelivery {
    private(set) var deliveredAlerts: [ScheduledAlert] = []
    private(set) var downgradedAlerts: [(alert: ScheduledAlert, reason: AlertDowngradeReason)] = []

    func deliver(alert: ScheduledAlert) async {
        self.deliveredAlerts.append(alert)
    }

    func deliverDowngraded(alert: ScheduledAlert, reason: AlertDowngradeReason) async {
        self.downgradedAlerts.append((alert, reason))
    }

    func reset() {
        self.deliveredAlerts = []
        self.downgradedAlerts = []
    }
}

/// Mock durable notification scheduler that tracks scheduled and cancelled OS notifications.
actor MockDurableAlertNotificationScheduler: DurableAlertNotificationScheduler {
    private(set) var scheduledNotifications: [ScheduledAlert] = []
    private(set) var scheduledSnoozeDurations: [String: [TimeInterval]] = [:]
    private(set) var cancelledPendingNotificationIds: [String] = []
    private(set) var removedDeliveredNotificationIds: [String] = []
    private(set) var cancelAllCallCount = 0

    var cancelledNotificationIds: [String] {
        self.cancelledPendingNotificationIds
    }

    func scheduleNotification(for alert: ScheduledAlert, snoozeDurations: [TimeInterval]) {
        self.scheduledNotifications.append(alert)
        self.scheduledSnoozeDurations[alert.id] = snoozeDurations
    }

    func cancelPendingNotification(alertId: String) {
        self.cancelledPendingNotificationIds.append(alertId)
        self.scheduledNotifications.removeAll { $0.id == alertId }
    }

    func removeDeliveredNotification(alertId: String) {
        self.removedDeliveredNotificationIds.append(alertId)
    }

    func cancelAllNotifications() {
        self.cancelAllCallCount += 1
        let alertIds = self.scheduledNotifications.map(\.id)
        self.cancelledPendingNotificationIds.append(contentsOf: alertIds)
        self.removedDeliveredNotificationIds.append(contentsOf: alertIds)
        self.scheduledNotifications.removeAll()
    }

    func reset() {
        self.scheduledNotifications = []
        self.scheduledSnoozeDurations = [:]
        self.cancelledPendingNotificationIds = []
        self.removedDeliveredNotificationIds = []
        self.cancelAllCallCount = 0
    }
}

// MARK: - Test Helpers

/// Creates a temporary file URL for test isolation.
func makeAlertTestTempFileURL() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent(
        "AlertEngineTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir.appendingPathComponent("alerts.json")
}

/// Cleans up a temporary test directory.
func cleanupAlertTestTempDir(_ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
}

// swiftlint:disable:next function_default_parameter_at_end
/// Creates a test event with specified parameters.
func makeAlertTestEvent(
    id: String = UUID().uuidString,
    calendarId: String = "cal-1",
    title: String = "Test Meeting",
    startTime: Date,
    endTime: Date? = nil,
    isAllDay: Bool = false,
    meetingLinks: [MeetingLink]? = nil,
    isOrganizer: Bool = false,
    attendeeCount: Int = 5,
    responseStatus: ResponseStatus = .accepted,
    htmlLink: URL? = nil
) -> CalendarEvent {
    let links: [MeetingLink] = if let provided = meetingLinks {
        provided
    } else if let url = URL(string: "https://meet.google.com/abc") {
        [MeetingLink(url: url)]
    } else {
        []
    }

    return CalendarEvent(
        id: id,
        calendarId: calendarId,
        title: title,
        startTime: startTime,
        endTime: endTime ?? startTime.addingTimeInterval(3600),
        isAllDay: isAllDay,
        location: nil,
        meetingLinks: links,
        isOrganizer: isOrganizer,
        attendeeCount: attendeeCount,
        responseStatus: responseStatus,
        htmlLink: htmlLink
    )
}

/// Creates a test settings store with the specified suite name.
func makeAlertTestSettings() throws -> SettingsStore {
    guard let defaults = UserDefaults(suiteName: UUID().uuidString) else {
        throw AlertTestError.settingsCreationFailed
    }
    return SettingsStore(defaults: defaults)
}

/// Creates a test settings store with custom stage minutes.
func makeAlertTestSettings(stage1Minutes: Int, stage2Minutes: Int) throws -> SettingsStore {
    guard let defaults = UserDefaults(suiteName: UUID().uuidString) else {
        throw AlertTestError.settingsCreationFailed
    }
    defaults.set(stage1Minutes, forKey: "alertStage1Minutes")
    defaults.set(stage2Minutes, forKey: "alertStage2Minutes")
    return SettingsStore(defaults: defaults)
}

/// Alert test-specific errors.
enum AlertTestError: Error {
    case settingsCreationFailed
}

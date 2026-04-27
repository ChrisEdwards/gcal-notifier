import Foundation
import OSLog
import UserNotifications

// MARK: - NotificationCenterProtocol

/// Protocol abstracting UNUserNotificationCenter for testability.
public protocol NotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removeAllDeliveredNotifications()
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> NotificationAuthorizationStatus
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
}

/// Simplified authorization status for protocol abstraction.
public enum NotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    init(from status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .notDetermined
        }
    }
}

// MARK: - SystemNotificationCenter

/// Wrapper around UNUserNotificationCenter conforming to our protocol.
public final class SystemNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init() {
        self.center = UNUserNotificationCenter.current()
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await self.center.add(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPendingNotificationRequests() {
        self.center.removeAllPendingNotificationRequests()
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removeAllDeliveredNotifications() {
        self.center.removeAllDeliveredNotifications()
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.center.setNotificationCategories(categories)
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await self.center.requestAuthorization(options: options)
    }

    public func notificationSettings() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return NotificationAuthorizationStatus(from: settings.authorizationStatus)
    }

    public func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        self.center.delegate = delegate
    }
}

// MARK: - NotificationScheduler

/// Schedules alerts using UNUserNotificationCenter for reliable timing.
/// Uses system notifications as timing mechanism (survives sleep/wake, DST).
public actor NotificationScheduler: AlertScheduler, DurableAlertNotificationScheduler {
    // MARK: - Constants

    /// Category identifier for meeting alerts.
    public static let meetingAlertCategory = AlertNotificationPayload.modalTimingCategoryIdentifier

    /// Category identifier for visible urgent stage 2 alerts.
    public static let stage2AlertCategory = AlertNotificationPayload.stage2CategoryIdentifier

    // MARK: - Dependencies

    private let center: any NotificationCenterProtocol
    private var handlers: [String: @Sendable () -> Void] = [:]
    private let delegate: NotificationDelegate

    // MARK: - Initialization

    /// Creates a NotificationScheduler with the default notification center.
    public init() async {
        let center: any NotificationCenterProtocol = SystemNotificationCenter()
        let delegate = NotificationDelegate()
        center.setDelegate(delegate)
        self.center = center
        self.delegate = delegate

        // Register notification category
        await self.registerCategory()
    }

    /// Creates a NotificationScheduler with custom dependencies (for testing).
    public init(center: any NotificationCenterProtocol, delegate: NotificationDelegate) async {
        center.setDelegate(delegate)
        self.center = center
        self.delegate = delegate
        await self.registerCategory()
    }

    // MARK: - AlertScheduler Protocol

    public func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) async {
        // Store the handler for when the notification fires
        self.handlers[alertId] = handler
        await self.delegate.register(alertId: alertId) { [weak self] in
            await self?.fireAlert(alertId: alertId)
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.meetingAlertCategory
        // Use silent delivery - we show our own modal
        content.sound = nil
        content.interruptionLevel = .passive

        // Create calendar-based trigger for exact timing
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        // Create and add the request
        let request = UNNotificationRequest(
            identifier: alertId,
            content: content,
            trigger: trigger
        )

        do {
            try await self.center.add(request)
        } catch {
            Logger.alerts.error(
                "Failed to schedule notification for alert \(alertId): \(error.localizedDescription)"
            )
        }
    }

    public func cancel(alertId: String) async {
        self.center.removePendingNotificationRequests(withIdentifiers: [alertId])
        self.center.removeDeliveredNotifications(withIdentifiers: [alertId])
        self.handlers.removeValue(forKey: alertId)
        await self.delegate.unregister(alertId: alertId)
    }

    public func cancelAll() async {
        self.center.removeAllPendingNotificationRequests()
        self.center.removeAllDeliveredNotifications()
        self.handlers.removeAll()
        await self.delegate.unregisterAll()
    }

    // MARK: - DurableAlertNotificationScheduler Protocol

    public func scheduleNotification(for alert: ScheduledAlert) async {
        let content = Self.makeNotificationContent(for: alert)
        let trigger = Self.makeCalendarTrigger(fireDate: alert.scheduledFireTime)
        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: trigger
        )

        do {
            try await self.center.add(request)
        } catch {
            Logger.alerts.error(
                "Failed to schedule durable notification for alert \(alert.id): \(error.localizedDescription)"
            )
        }
    }

    public func cancelNotification(alertId: String) async {
        self.center.removePendingNotificationRequests(withIdentifiers: [alertId])
        self.center.removeDeliveredNotifications(withIdentifiers: [alertId])
    }

    public func cancelAllNotifications() async {
        self.center.removeAllPendingNotificationRequests()
        self.center.removeAllDeliveredNotifications()
    }

    // MARK: - Permission Management

    /// Requests notification authorization from the user.
    /// Returns the current authorization status after the request.
    public func requestAuthorization() async -> NotificationAuthorizationStatus {
        do {
            // Request authorization for alerts (timing mechanism)
            _ = try await self.center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Permission denied or error - fall back to checking status
        }
        return await self.authorizationStatus()
    }

    /// Returns the current notification authorization status.
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        await self.center.notificationSettings()
    }

    // MARK: - Banner Notifications

    /// Shows an immediate notification banner for a downgraded alert.
    ///
    /// Unlike scheduled alerts that fire our custom modal, this shows a system
    /// notification banner for less intrusive notifications during back-to-back meetings.
    ///
    /// - Parameters:
    ///   - title: The notification title (e.g., "Up Next").
    ///   - body: The notification body (e.g., "Meeting in 10m").
    ///   - identifier: Unique identifier for the notification.
    public func showBannerNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // Sound is handled separately by SoundPlayer
        content.categoryIdentifier = Self.backToBackAlertCategory
        content.interruptionLevel = .passive

        // Immediate trigger (nil trigger means deliver immediately)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await self.center.add(request)
        } catch {
            Logger.alerts.error(
                "Failed to deliver banner notification \(identifier): \(error.localizedDescription)"
            )
        }
    }

    /// Category identifier for back-to-back (downgraded) alerts.
    public static let backToBackAlertCategory = "BACK_TO_BACK_ALERT"

    // MARK: - Private Helpers

    private func registerCategory() async {
        // Define category with hidden presentation
        // We intercept the notification before display to show our own modal
        let meetingCategory = UNNotificationCategory(
            identifier: Self.meetingAlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )

        // Define category for durable urgent alerts - these must be visible when
        // macOS presents them outside the app's modal path.
        let stage2Category = UNNotificationCategory(
            identifier: Self.stage2AlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )

        // Define category for back-to-back alerts - these show as banners
        let backToBackCategory = UNNotificationCategory(
            identifier: Self.backToBackAlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        self.center.setNotificationCategories([meetingCategory, stage2Category, backToBackCategory])
    }

    private func fireAlert(alertId: String) async {
        guard let handler = handlers[alertId] else { return }
        self.handlers.removeValue(forKey: alertId)
        handler()
    }

    private static func makeNotificationContent(for alert: ScheduledAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.notificationPayload.title
        content.body = alert.notificationPayload.body
        content.categoryIdentifier = alert.notificationPayload.categoryIdentifier
        content.sound = Self.notificationSound(for: alert.notificationPayload.soundBehavior)
        content.interruptionLevel = Self.interruptionLevel(for: alert.notificationPayload.urgency)
        content.userInfo = Self.userInfo(for: alert)
        return content
    }

    private static func makeCalendarTrigger(fireDate: Date) -> UNCalendarNotificationTrigger {
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
    }

    private static func notificationSound(
        for behavior: AlertNotificationSoundBehavior
    ) -> UNNotificationSound? {
        switch behavior {
        case .none:
            nil
        case .defaultSound:
            .default
        }
    }

    private static func interruptionLevel(
        for urgency: AlertNotificationUrgency
    ) -> UNNotificationInterruptionLevel {
        switch urgency {
        case .passive:
            .passive
        case .active:
            .active
        case .timeSensitive:
            .timeSensitive
        }
    }

    private static func userInfo(for alert: ScheduledAlert) -> [String: String] {
        var userInfo = [
            "alertId": alert.id,
            "eventId": alert.eventId,
            "stage": alert.stage.rawValue,
            "scheduledFireTime": Self.iso8601String(from: alert.scheduledFireTime),
            "eventTitle": alert.eventTitle,
            "eventStartTime": Self.iso8601String(from: alert.eventStartTime),
            "eventEndTime": Self.iso8601String(from: alert.eventEndTime),
            "notificationTitle": alert.notificationPayload.title,
            "notificationBody": alert.notificationPayload.body,
            "notificationCategory": alert.notificationPayload.categoryIdentifier,
            "notificationSoundBehavior": alert.notificationPayload.soundBehavior.rawValue,
            "notificationUrgency": alert.notificationPayload.urgency.rawValue,
        ]

        if let joinURL = alert.joinURL {
            userInfo["joinURL"] = joinURL.absoluteString
        }

        if let calendarURL = alert.calendarURL {
            userInfo["calendarURL"] = calendarURL.absoluteString
        }

        return userInfo
    }

    private static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - NotificationDelegate

/// Delegate that intercepts notification delivery to invoke custom handlers.
/// Acts as the bridge between system notifications and our alert system.
public actor NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private var alertHandlers: [String: @Sendable () async -> Void] = [:]

    override public init() {
        super.init()
    }

    // MARK: - Presentation Options

    /// Returns the presentation options for a given notification category.
    static func presentationOptions(forCategoryIdentifier identifier: String) -> UNNotificationPresentationOptions {
        let shouldShowBanner = identifier == NotificationScheduler.backToBackAlertCategory ||
            identifier == NotificationScheduler.stage2AlertCategory

        if shouldShowBanner {
            return [.banner, .list]
        }
        return []
    }

    /// Registers a handler for when a notification with the given ID is delivered.
    public func register(alertId: String, handler: @escaping @Sendable () async -> Void) {
        self.alertHandlers[alertId] = handler
    }

    /// Unregisters the handler for a notification.
    public func unregister(alertId: String) {
        self.alertHandlers.removeValue(forKey: alertId)
    }

    /// Unregisters all handlers.
    public func unregisterAll() {
        self.alertHandlers.removeAll()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is about to be presented while the app is in foreground.
    /// We intercept this to show our custom modal instead of the system banner.
    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let categoryIdentifier = notification.request.content.categoryIdentifier

        if categoryIdentifier == NotificationScheduler.meetingAlertCategory {
            // Fire the handler asynchronously for intercepted alerts.
            Task {
                await self.fireHandlerInternal(for: identifier)
            }
        }

        return Self.presentationOptions(forCategoryIdentifier: categoryIdentifier)
    }

    /// Called when user interacts with a notification (app in background).
    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier

        // Fire the handler for background delivery
        await self.fireHandlerInternal(for: identifier)
    }

    // MARK: - Internal (for testing)

    /// Fires the handler for a given alert ID. Exposed for testing purposes.
    public func testFireHandler(alertId: String) async {
        await self.fireHandlerInternal(for: alertId)
    }

    private func fireHandlerInternal(for alertId: String) async {
        guard let handler = alertHandlers[alertId] else { return }
        self.alertHandlers.removeValue(forKey: alertId)
        await handler()
    }
}

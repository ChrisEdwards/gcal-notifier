import Foundation
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
public actor NotificationScheduler: AlertScheduler {
    // MARK: - Constants

    /// Category identifier for meeting alerts.
    public static let meetingAlertCategory = "MEETING_ALERT"

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
            // Log error but don't throw - handler is already registered
            // The alert may still fire if there's a retry mechanism
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

    // MARK: - Private Helpers

    private func registerCategory() async {
        // Define category with hidden presentation
        // We intercept the notification before display to show our own modal
        let category = UNNotificationCategory(
            identifier: Self.meetingAlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )

        self.center.setNotificationCategories([category])
    }

    private func fireAlert(alertId: String) async {
        guard let handler = handlers[alertId] else { return }
        self.handlers.removeValue(forKey: alertId)
        handler()
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

        // Fire the handler asynchronously
        Task {
            await self.fireHandlerInternal(for: identifier)
        }

        // Return empty options to suppress system presentation
        return []
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

import Foundation
import OSLog
@preconcurrency import UserNotifications

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

public actor NotificationScheduler {
    private let center: any NotificationCenterProtocol
    private var handlers: [String: @Sendable () -> Void] = [:]
    private let delegate: NotificationDelegate

    public init() async {
        let center: any NotificationCenterProtocol = SystemNotificationCenter()
        let delegate = NotificationDelegate()
        center.setDelegate(delegate)
        self.center = center
        self.delegate = delegate

        await self.registerCategory()
    }

    public init(center: any NotificationCenterProtocol, delegate: NotificationDelegate) async {
        center.setDelegate(delegate)
        self.center = center
        self.delegate = delegate
        await self.registerCategory()
    }
}

extension NotificationScheduler: AlertScheduler {
    public func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) async {
        self.handlers[alertId] = handler
        await self.delegate.register(alertId: alertId) { [weak self] in
            await self?.fireAlert(alertId: alertId)
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.meetingAlertCategory
        content.sound = nil
        content.interruptionLevel = .passive

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

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
}

extension NotificationScheduler: DurableAlertNotificationScheduler {
    public func scheduleNotification(for alert: ScheduledAlert, snoozeDurations: [TimeInterval]) async {
        let content = Self.makeNotificationContent(for: alert, snoozeDurations: snoozeDurations)
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

    public func setAlertCommandHandler(_ handler: @escaping @Sendable (AlertCommand) async -> Void) async {
        await self.delegate.setAlertCommandHandler(handler)
    }
}

public extension NotificationScheduler {
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        do {
            _ = try await self.center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {}
        return await self.authorizationStatus()
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        await self.center.notificationSettings()
    }

    func showBannerNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = Self.backToBackAlertCategory
        content.interruptionLevel = .passive

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

    static var meetingAlertCategory: String {
        AlertNotificationPayload.modalTimingCategoryIdentifier
    }

    static var stage1AlertCategory: String {
        AlertNotificationPayload.stage1CategoryIdentifier
    }

    static var stage2AlertCategory: String {
        AlertNotificationPayload.stage2CategoryIdentifier
    }

    static var stage1Snooze1Category: String {
        "\(AlertNotificationPayload.stage1CategoryIdentifier)_SNOOZE_1M"
    }

    static var stage1Snooze3Category: String {
        "\(AlertNotificationPayload.stage1CategoryIdentifier)_SNOOZE_3M"
    }

    static var stage1Snooze5Category: String {
        "\(AlertNotificationPayload.stage1CategoryIdentifier)_SNOOZE_5M"
    }

    static var stage1Snooze1ActionIdentifier: String {
        "STAGE1_SNOOZE_1M"
    }

    static var stage1Snooze3ActionIdentifier: String {
        "STAGE1_SNOOZE_3M"
    }

    static var stage1Snooze5ActionIdentifier: String {
        "STAGE1_SNOOZE_5M"
    }

    static var stage2JoinActionIdentifier: String {
        "STAGE2_JOIN"
    }

    static var stage2SnoozeActionIdentifier: String {
        "STAGE2_SNOOZE_1M"
    }

    static var stage2DismissActionIdentifier: String {
        "STAGE2_DISMISS"
    }

    static var stage2SnoozeDuration: TimeInterval {
        60
    }

    static var backToBackAlertCategory: String {
        "BACK_TO_BACK_ALERT"
    }

    static func stage1CategoryIdentifier(validSnoozeDurations durations: [TimeInterval]) -> String {
        if durations.contains(300) { return self.stage1Snooze5Category }
        if durations.contains(180) { return self.stage1Snooze3Category }
        if durations.contains(60) { return self.stage1Snooze1Category }
        return self.stage1AlertCategory
    }

    static func snoozeDuration(forActionIdentifier identifier: String) -> TimeInterval? {
        switch identifier {
        case self.stage1Snooze1ActionIdentifier, self.stage2SnoozeActionIdentifier:
            60
        case self.stage1Snooze3ActionIdentifier:
            180
        case self.stage1Snooze5ActionIdentifier:
            300
        default:
            nil
        }
    }
}

private extension NotificationScheduler {
    private func registerCategory() async {
        self.center.setNotificationCategories(Self.registeredCategories)
    }

    private static var registeredCategories: Set<UNNotificationCategory> {
        Set([self.meetingCategory, self.stage2Category, self.backToBackCategory] + self.stage1Categories)
    }

    private static var meetingCategory: UNNotificationCategory {
        self.makeCategory(identifier: self.meetingAlertCategory, actions: [], options: [.hiddenPreviewsShowTitle])
    }

    private static var stage1Categories: [UNNotificationCategory] {
        [
            self.makeStage1Category(identifier: self.stage1AlertCategory, snoozeActions: []),
            self.makeStage1Category(identifier: self.stage1Snooze1Category, snoozeActions: [self.stage1Snooze1Action]),
            self.makeStage1Category(identifier: self.stage1Snooze3Category, snoozeActions: self.stage1Snooze3Actions),
            self.makeStage1Category(identifier: self.stage1Snooze5Category, snoozeActions: self.stage1Snooze5Actions),
        ]
    }

    private static var stage2Category: UNNotificationCategory {
        self.makeCategory(
            identifier: self.stage2AlertCategory,
            actions: self.stage2Actions,
            options: [.hiddenPreviewsShowTitle]
        )
    }

    private static var backToBackCategory: UNNotificationCategory {
        self.makeCategory(identifier: self.backToBackAlertCategory, actions: [], options: [])
    }

    private static var stage1Snooze3Actions: [UNNotificationAction] {
        [self.stage1Snooze1Action, self.stage1Snooze3Action]
    }

    private static var stage1Snooze5Actions: [UNNotificationAction] {
        [self.stage1Snooze1Action, self.stage1Snooze3Action, self.stage1Snooze5Action]
    }

    private static var stage2Actions: [UNNotificationAction] {
        [self.stage2JoinAction, self.stage2SnoozeAction, self.stage2DismissAction]
    }

    private static var stage1Snooze1Action: UNNotificationAction {
        UNNotificationAction(identifier: stage1Snooze1ActionIdentifier, title: "Snooze 1m", options: [])
    }

    private static var stage1Snooze3Action: UNNotificationAction {
        UNNotificationAction(identifier: stage1Snooze3ActionIdentifier, title: "Snooze 3m", options: [])
    }

    private static var stage1Snooze5Action: UNNotificationAction {
        UNNotificationAction(identifier: stage1Snooze5ActionIdentifier, title: "Snooze 5m", options: [])
    }

    private static var stage2JoinAction: UNNotificationAction {
        UNNotificationAction(identifier: stage2JoinActionIdentifier, title: "Join", options: [.foreground])
    }

    private static var stage2SnoozeAction: UNNotificationAction {
        UNNotificationAction(identifier: stage2SnoozeActionIdentifier, title: "Snooze 1m", options: [])
    }

    private static var stage2DismissAction: UNNotificationAction {
        UNNotificationAction(identifier: stage2DismissActionIdentifier, title: "Dismiss", options: [])
    }

    private static func makeStage1Category(
        identifier: String,
        snoozeActions: [UNNotificationAction]
    ) -> UNNotificationCategory {
        self.makeCategory(identifier: identifier, actions: snoozeActions, options: [.hiddenPreviewsShowTitle])
    }

    private static func makeCategory(
        identifier: String,
        actions: [UNNotificationAction],
        options: UNNotificationCategoryOptions
    ) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: identifier,
            actions: actions,
            intentIdentifiers: [],
            options: options
        )
    }

    private func fireAlert(alertId: String) async {
        guard let handler = handlers[alertId] else { return }
        self.handlers.removeValue(forKey: alertId)
        handler()
    }

    private static func makeNotificationContent(
        for alert: ScheduledAlert,
        snoozeDurations: [TimeInterval]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.notificationPayload.title
        content.body = alert.notificationPayload.body
        content.categoryIdentifier = Self.categoryIdentifier(for: alert, snoozeDurations: snoozeDurations)
        content.sound = Self.notificationSound(for: alert.notificationPayload.soundBehavior)
        content.interruptionLevel = Self.interruptionLevel(for: alert.notificationPayload.urgency)
        content.userInfo = Self.userInfo(for: alert)
        return content
    }

    private static func categoryIdentifier(
        for alert: ScheduledAlert,
        snoozeDurations: [TimeInterval]
    ) -> String {
        guard alert.stage == .stage1 else { return alert.notificationPayload.categoryIdentifier }
        return self.stage1CategoryIdentifier(validSnoozeDurations: snoozeDurations)
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

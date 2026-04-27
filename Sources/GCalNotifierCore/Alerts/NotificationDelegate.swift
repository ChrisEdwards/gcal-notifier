import UserNotifications

public actor NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private var alertHandlers: [String: @Sendable () async -> Void] = [:]
    private var alertCommandHandler: (@Sendable (AlertCommand) async -> Void)?

    override public init() {
        super.init()
    }

    static func presentationOptions(forCategoryIdentifier identifier: String) -> UNNotificationPresentationOptions {
        let shouldShowBanner = identifier == NotificationScheduler.stage1AlertCategory ||
            identifier == NotificationScheduler.backToBackAlertCategory ||
            identifier == NotificationScheduler.stage2AlertCategory
        return shouldShowBanner ? [.banner, .list] : []
    }

    public func register(alertId: String, handler: @escaping @Sendable () async -> Void) {
        self.alertHandlers[alertId] = handler
    }

    public func unregister(alertId: String) {
        self.alertHandlers.removeValue(forKey: alertId)
    }

    public func unregisterAll() {
        self.alertHandlers.removeAll()
    }

    public func setAlertCommandHandler(_ handler: @escaping @Sendable (AlertCommand) async -> Void) {
        self.alertCommandHandler = handler
    }

    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let categoryIdentifier = notification.request.content.categoryIdentifier

        if categoryIdentifier == NotificationScheduler.meetingAlertCategory {
            Task {
                await self.fireHandlerInternal(for: identifier)
            }
        }

        return Self.presentationOptions(forCategoryIdentifier: categoryIdentifier)
    }

    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await self.handleResponse(
            alertId: response.notification.request.identifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier
        )
    }

    public func testFireHandler(alertId: String) async {
        await self.fireHandlerInternal(for: alertId)
    }

    public func testHandleResponse(
        alertId: String,
        categoryIdentifier: String,
        actionIdentifier: String
    ) async {
        await self.handleResponse(
            alertId: alertId,
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier
        )
    }

    private func handleResponse(
        alertId: String,
        categoryIdentifier: String,
        actionIdentifier: String
    ) async {
        if categoryIdentifier == NotificationScheduler.stage1AlertCategory {
            await self.fireCommandInternal(.showContext(alertId: alertId))
            return
        }

        if categoryIdentifier == NotificationScheduler.stage2AlertCategory {
            await self.fireCommandInternal(Self.command(alertId: alertId, actionIdentifier: actionIdentifier))
            return
        }

        if categoryIdentifier == NotificationScheduler.meetingAlertCategory {
            await self.fireHandlerInternal(for: alertId)
        }
    }

    private static func command(alertId: String, actionIdentifier: String) -> AlertCommand {
        switch actionIdentifier {
        case NotificationScheduler.stage2JoinActionIdentifier:
            .join(alertId: alertId)
        case NotificationScheduler.stage2SnoozeActionIdentifier:
            .snooze(alertId: alertId, duration: NotificationScheduler.stage2SnoozeDuration)
        case NotificationScheduler.stage2DismissActionIdentifier, UNNotificationDismissActionIdentifier:
            .dismiss(alertId: alertId)
        default:
            .showContext(alertId: alertId)
        }
    }

    private func fireHandlerInternal(for alertId: String) async {
        guard let handler = alertHandlers[alertId] else { return }
        self.alertHandlers.removeValue(forKey: alertId)
        await handler()
    }

    private func fireCommandInternal(_ command: AlertCommand) async {
        guard let handler = self.alertCommandHandler else { return }
        await handler(command)
    }
}

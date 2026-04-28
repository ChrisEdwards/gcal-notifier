import UserNotifications

public actor NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private var alertHandlers: [String: @Sendable () async -> Void] = [:]
    private var alertCommandHandler: (@Sendable (AlertCommand) async -> Void)?

    override public init() {
        super.init()
    }

    static func presentationOptions(forCategoryIdentifier identifier: String) -> UNNotificationPresentationOptions {
        let shouldShowBanner = NotificationScheduler.isStage1Category(identifier) ||
            NotificationScheduler.isStage2Category(identifier) ||
            identifier == NotificationScheduler.backToBackAlertCategory
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
        if NotificationScheduler.isStage1Category(categoryIdentifier) {
            await self.fireCommandInternal(Self.stageCommand(alertId: alertId, actionIdentifier: actionIdentifier))
            return
        }

        if NotificationScheduler.isStage2Category(categoryIdentifier) {
            await self.fireCommandInternal(Self.stageCommand(alertId: alertId, actionIdentifier: actionIdentifier))
            return
        }

        if categoryIdentifier == NotificationScheduler.meetingAlertCategory {
            await self.fireHandlerInternal(for: alertId)
        }
    }

    private static func stageCommand(alertId: String, actionIdentifier: String) -> AlertCommand {
        switch actionIdentifier {
        case NotificationScheduler.stage1JoinActionIdentifier,
             NotificationScheduler.stage2JoinActionIdentifier:
            return .join(alertId: alertId)
        case NotificationScheduler.stage1DismissActionIdentifier,
             NotificationScheduler.stage2DismissActionIdentifier,
             UNNotificationDismissActionIdentifier:
            return .dismiss(alertId: alertId)
        default:
            if let duration = NotificationScheduler.snoozeDuration(forActionIdentifier: actionIdentifier) {
                return .snooze(alertId: alertId, duration: duration)
            }
            return .showContext(alertId: alertId)
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

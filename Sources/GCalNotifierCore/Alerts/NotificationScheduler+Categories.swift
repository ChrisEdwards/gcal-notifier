import Foundation
import UserNotifications

public extension NotificationScheduler {
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

    static var stage2Snooze1Category: String {
        "\(AlertNotificationPayload.stage2CategoryIdentifier)_SNOOZE_1M"
    }

    static var stage2Snooze3Category: String {
        "\(AlertNotificationPayload.stage2CategoryIdentifier)_SNOOZE_3M"
    }

    static var stage2Snooze5Category: String {
        "\(AlertNotificationPayload.stage2CategoryIdentifier)_SNOOZE_5M"
    }

    static var stage1JoinActionIdentifier: String {
        "STAGE1_JOIN"
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

    static var stage1DismissActionIdentifier: String {
        "STAGE1_DISMISS"
    }

    static var stage2JoinActionIdentifier: String {
        "STAGE2_JOIN"
    }

    static var stage2SnoozeActionIdentifier: String {
        self.stage2Snooze1ActionIdentifier
    }

    static var stage2Snooze1ActionIdentifier: String {
        "STAGE2_SNOOZE_1M"
    }

    static var stage2Snooze3ActionIdentifier: String {
        "STAGE2_SNOOZE_3M"
    }

    static var stage2Snooze5ActionIdentifier: String {
        "STAGE2_SNOOZE_5M"
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
        self.categoryIdentifier(
            baseCategory: self.stage1AlertCategory,
            snooze1Category: self.stage1Snooze1Category,
            snooze3Category: self.stage1Snooze3Category,
            snooze5Category: self.stage1Snooze5Category,
            validSnoozeDurations: durations
        )
    }

    static func stage2CategoryIdentifier(validSnoozeDurations durations: [TimeInterval]) -> String {
        self.categoryIdentifier(
            baseCategory: self.stage2AlertCategory,
            snooze1Category: self.stage2Snooze1Category,
            snooze3Category: self.stage2Snooze3Category,
            snooze5Category: self.stage2Snooze5Category,
            validSnoozeDurations: durations
        )
    }

    static func snoozeDuration(forActionIdentifier identifier: String) -> TimeInterval? {
        switch identifier {
        case self.stage1Snooze1ActionIdentifier, self.stage2Snooze1ActionIdentifier:
            60
        case self.stage1Snooze3ActionIdentifier, self.stage2Snooze3ActionIdentifier:
            180
        case self.stage1Snooze5ActionIdentifier, self.stage2Snooze5ActionIdentifier:
            300
        default:
            nil
        }
    }
}

extension NotificationScheduler {
    static var registeredCategories: Set<UNNotificationCategory> {
        Set([self.meetingCategory, self.backToBackCategory] + self.stage1Categories + self.stage2Categories)
    }

    static func isStage1Category(_ identifier: String) -> Bool {
        self.stage1CategoryIdentifiers.contains(identifier)
    }

    static func isStage2Category(_ identifier: String) -> Bool {
        self.stage2CategoryIdentifiers.contains(identifier)
    }

    private static var stage1CategoryIdentifiers: Set<String> {
        [self.stage1AlertCategory, self.stage1Snooze1Category, self.stage1Snooze3Category, self.stage1Snooze5Category]
    }

    private static var stage2CategoryIdentifiers: Set<String> {
        [self.stage2AlertCategory, self.stage2Snooze1Category, self.stage2Snooze3Category, self.stage2Snooze5Category]
    }

    private static var meetingCategory: UNNotificationCategory {
        self.makeCategory(identifier: self.meetingAlertCategory, actions: [], options: [.hiddenPreviewsShowTitle])
    }

    private static var stage1Categories: [UNNotificationCategory] {
        [
            self.makeStageCategory(
                identifier: self.stage1AlertCategory,
                join: self.stage1JoinAction,
                snoozeActions: [],
                dismiss: self.stage1DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage1Snooze1Category,
                join: self.stage1JoinAction,
                snoozeActions: [self.stage1Snooze1Action],
                dismiss: self.stage1DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage1Snooze3Category,
                join: self.stage1JoinAction,
                snoozeActions: self.stage1Snooze3Actions,
                dismiss: self.stage1DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage1Snooze5Category,
                join: self.stage1JoinAction,
                snoozeActions: self.stage1Snooze5Actions,
                dismiss: self.stage1DismissAction
            ),
        ]
    }

    private static var stage2Categories: [UNNotificationCategory] {
        [
            self.makeStageCategory(
                identifier: self.stage2AlertCategory,
                join: self.stage2JoinAction,
                snoozeActions: [],
                dismiss: self.stage2DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage2Snooze1Category,
                join: self.stage2JoinAction,
                snoozeActions: [self.stage2Snooze1Action],
                dismiss: self.stage2DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage2Snooze3Category,
                join: self.stage2JoinAction,
                snoozeActions: self.stage2Snooze3Actions,
                dismiss: self.stage2DismissAction
            ),
            self.makeStageCategory(
                identifier: self.stage2Snooze5Category,
                join: self.stage2JoinAction,
                snoozeActions: self.stage2Snooze5Actions,
                dismiss: self.stage2DismissAction
            ),
        ]
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

    private static var stage2Snooze3Actions: [UNNotificationAction] {
        [self.stage2Snooze1Action, self.stage2Snooze3Action]
    }

    private static var stage2Snooze5Actions: [UNNotificationAction] {
        [self.stage2Snooze1Action, self.stage2Snooze3Action, self.stage2Snooze5Action]
    }

    private static var stage1JoinAction: UNNotificationAction {
        UNNotificationAction(identifier: self.stage1JoinActionIdentifier, title: "Join", options: [.foreground])
    }

    private static var stage1Snooze1Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage1Snooze1ActionIdentifier, title: "Snooze 1m", options: [])
    }

    private static var stage1Snooze3Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage1Snooze3ActionIdentifier, title: "Snooze 3m", options: [])
    }

    private static var stage1Snooze5Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage1Snooze5ActionIdentifier, title: "Snooze 5m", options: [])
    }

    private static var stage1DismissAction: UNNotificationAction {
        UNNotificationAction(identifier: self.stage1DismissActionIdentifier, title: "Dismiss", options: [])
    }

    private static var stage2JoinAction: UNNotificationAction {
        UNNotificationAction(identifier: self.stage2JoinActionIdentifier, title: "Join", options: [.foreground])
    }

    private static var stage2Snooze1Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage2Snooze1ActionIdentifier, title: "Snooze 1m", options: [])
    }

    private static var stage2Snooze3Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage2Snooze3ActionIdentifier, title: "Snooze 3m", options: [])
    }

    private static var stage2Snooze5Action: UNNotificationAction {
        UNNotificationAction(identifier: self.stage2Snooze5ActionIdentifier, title: "Snooze 5m", options: [])
    }

    private static var stage2DismissAction: UNNotificationAction {
        UNNotificationAction(identifier: self.stage2DismissActionIdentifier, title: "Dismiss", options: [])
    }

    private static func makeStageCategory(
        identifier: String,
        join: UNNotificationAction,
        snoozeActions: [UNNotificationAction],
        dismiss: UNNotificationAction
    ) -> UNNotificationCategory {
        self.makeCategory(
            identifier: identifier,
            actions: [join] + snoozeActions + [dismiss],
            options: [.hiddenPreviewsShowTitle]
        )
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

    private static func categoryIdentifier(
        baseCategory: String,
        snooze1Category: String,
        snooze3Category: String,
        snooze5Category: String,
        validSnoozeDurations durations: [TimeInterval]
    ) -> String {
        if durations.contains(300) { return snooze5Category }
        if durations.contains(180) { return snooze3Category }
        if durations.contains(60) { return snooze1Category }
        return baseCategory
    }
}

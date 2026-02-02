import Foundation

/// Protocol for delivering alerts when they fire.
/// Abstracted to allow testing with mocks.
public protocol AlertDelivery: Sendable {
    func deliver(alert: ScheduledAlert) async
    func deliverDowngraded(alert: ScheduledAlert, reason: AlertDowngradeReason) async
}

// MARK: - Alert Downgrade Reason

/// Reason why an alert was downgraded from modal to notification banner.
public enum AlertDowngradeReason: Sendable, Equatable {
    /// User is currently in another meeting (back-to-back situation).
    case backToBackMeeting
    /// User is currently sharing their screen.
    case screenSharing
    /// Do Not Disturb is enabled.
    case doNotDisturb
}

// MARK: - Back-to-Back Alert Context

/// Context for back-to-back alert handling.
public struct BackToBackAlertContext: Sendable, Equatable {
    /// Whether the user is currently in a meeting.
    public let isInMeeting: Bool

    /// Whether this alert is for a back-to-back meeting.
    public let isBackToBackSituation: Bool

    /// The current meeting the user is in (if any).
    public let currentMeeting: CalendarEvent?

    public init(isInMeeting: Bool, isBackToBackSituation: Bool, currentMeeting: CalendarEvent?) {
        self.isInMeeting = isInMeeting
        self.isBackToBackSituation = isBackToBackSituation
        self.currentMeeting = currentMeeting
    }

    /// No back-to-back context (user not in a meeting).
    public static let none = BackToBackAlertContext(
        isInMeeting: false,
        isBackToBackSituation: false,
        currentMeeting: nil
    )
}

// MARK: - MissedAlertResult

/// Result of checking for a missed alert after wake from sleep.
public enum MissedAlertResult: Sendable, Equatable {
    /// The meeting hasn't started yet - fire alert immediately.
    case fireNow(ScheduledAlert)

    /// The meeting just started (within grace period) - show "Meeting started!" alert.
    case meetingJustStarted(ScheduledAlert)

    /// The meeting is too old to alert (started more than 5 minutes ago).
    case tooOld(ScheduledAlert)
}

// MARK: - Alert Errors

/// Errors that can occur during alert operations.
public enum AlertError: Error, Equatable, Sendable {
    /// Cannot snooze - the meeting has already started.
    case meetingAlreadyStarted

    /// Cannot snooze - the snooze duration would exceed the meeting start time.
    case snoozePastMeetingStart

    /// The specified alert was not found.
    case alertNotFound(alertId: String)
}

extension AlertError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .meetingAlreadyStarted:
            "The meeting has already started."
        case .snoozePastMeetingStart:
            "Cannot snooze past the meeting start time."
        case let .alertNotFound(alertId):
            "Alert not found: \(alertId)"
        }
    }
}

// MARK: - NoOp Delivery

/// Default no-op delivery for production use before real delivery is wired up.
public struct NoOpAlertDelivery: AlertDelivery {
    public init() {}

    public func deliver(alert _: ScheduledAlert) async {
        // No-op - real delivery will be implemented in UNUserNotificationCenter integration
    }

    public func deliverDowngraded(alert _: ScheduledAlert, reason _: AlertDowngradeReason) async {
        // No-op - real delivery will show notification banner instead of modal
    }
}

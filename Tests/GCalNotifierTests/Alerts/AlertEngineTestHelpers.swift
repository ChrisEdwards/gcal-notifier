import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Mock Dependencies

/// Mock scheduler that tracks scheduled and cancelled alerts.
actor MockAlertScheduler: AlertScheduler {
    private(set) var scheduledAlerts: [(alertId: String, fireDate: Date)] = []
    private(set) var cancelledAlertIds: [String] = []
    private var handlers: [String: @Sendable () -> Void] = [:]

    func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) {
        self.scheduledAlerts.append((alertId, fireDate))
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

    func reset() {
        self.scheduledAlerts = []
        self.cancelledAlertIds = []
        self.handlers.removeAll()
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
    responseStatus: ResponseStatus = .accepted
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
        responseStatus: responseStatus
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

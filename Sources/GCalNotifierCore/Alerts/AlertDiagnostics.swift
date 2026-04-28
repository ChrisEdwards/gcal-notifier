import Foundation
import OSLog

public enum AlertDiagnosticEvent: String, Sendable {
    case alertRecordCreated = "alert_record_created"
    case localModalTriggerScheduled = "local_modal_trigger_scheduled"
    case osNotificationScheduled = "os_notification_scheduled"
    case modalPresented = "modal_presented"
    case modalDowngraded = "modal_downgraded"
    case snapshotFallbackUsed = "snapshot_fallback_used"
    case scheduledEffectsCanceled = "scheduled_effects_canceled"
    case deliveryDropped = "delivery_dropped"
    case commandCompleted = "command_completed"
    case commandSnoozed = "command_snoozed"
}

public struct AlertDiagnosticRecord: Equatable, Sendable {
    public let event: AlertDiagnosticEvent
    public let alertId: String
    public let eventId: String?
    public let stage: AlertStage?
    public let scheduledFireTime: Date?
    public let eventStartTime: Date?
    public let snapshotFingerprint: String?
    public let reason: String?
}

public enum AlertDiagnostics {
    public static func makeRecord(
        _ event: AlertDiagnosticEvent,
        alert: ScheduledAlert,
        reason: String? = nil
    ) -> AlertDiagnosticRecord {
        AlertDiagnosticRecord(
            event: event,
            alertId: alert.id,
            eventId: alert.eventId,
            stage: alert.stage,
            scheduledFireTime: alert.scheduledFireTime,
            eventStartTime: alert.eventStartTime,
            snapshotFingerprint: alert.snapshotFingerprint,
            reason: reason
        )
    }

    public static func makeDroppedRecord(alertId: String, reason: String) -> AlertDiagnosticRecord {
        AlertDiagnosticRecord(
            event: .deliveryDropped,
            alertId: alertId,
            eventId: nil,
            stage: nil,
            scheduledFireTime: nil,
            eventStartTime: nil,
            snapshotFingerprint: nil,
            reason: reason
        )
    }

    public static func log(
        _ event: AlertDiagnosticEvent,
        alert: ScheduledAlert,
        reason: String? = nil
    ) {
        self.log(self.makeRecord(event, alert: alert, reason: reason))
    }

    public static func logDropped(alertId: String, reason: String) {
        self.log(self.makeDroppedRecord(alertId: alertId, reason: reason))
    }

    public static func logMissingAlertRecord(alertId: String) {
        self.logDropped(alertId: alertId, reason: "missing-alert-record")
    }

    public static func logStaleLocalTriggerGeneration(_ alert: ScheduledAlert) {
        self.log(.deliveryDropped, alert: alert, reason: "stale-local-modal-trigger-generation")
    }

    public static func logStaleLocalTrigger(_ alert: ScheduledAlert) {
        self.log(.deliveryDropped, alert: alert, reason: "stale-local-trigger")
    }

    private static func log(_ record: AlertDiagnosticRecord) {
        let scheduledFireTime = record.scheduledFireTime.map { self.iso8601String(from: $0) } ?? ""
        let eventStartTime = record.eventStartTime.map { self.iso8601String(from: $0) } ?? ""
        Logger.alerts.info(
            """
            alert_diagnostic event=\(record.event.rawValue, privacy: .public) \
            alertId=\(record.alertId, privacy: .public) \
            eventId=\(record.eventId ?? "", privacy: .public) \
            stage=\(record.stage?.rawValue ?? "", privacy: .public) \
            scheduledFireTime=\(scheduledFireTime, privacy: .public) \
            eventStartTime=\(eventStartTime, privacy: .public) \
            snapshotFingerprint=\(record.snapshotFingerprint ?? "", privacy: .public) \
            reason=\(record.reason ?? "", privacy: .public)
            """
        )
    }

    private static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

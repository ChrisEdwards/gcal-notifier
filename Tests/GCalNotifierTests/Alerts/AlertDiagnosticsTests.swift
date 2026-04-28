import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("Alert Diagnostics Tests")
struct AlertDiagnosticsTests {
    @Test("diagnostic record keeps stable alert correlation context")
    func diagnosticRecordKeepsStableAlertCorrelationContext() throws {
        let alert = try makeDiagnosticAlert()

        let record = AlertDiagnostics.makeRecord(.osNotificationScheduled, alert: alert, reason: "scheduled")

        #expect(record.event == .osNotificationScheduled)
        #expect(record.alertId == alert.id)
        #expect(record.eventId == alert.eventId)
        #expect(record.stage == alert.stage)
        #expect(record.scheduledFireTime == alert.scheduledFireTime)
        #expect(record.eventStartTime == alert.eventStartTime)
        #expect(record.snapshotFingerprint == alert.snapshotFingerprint)
        #expect(record.reason == "scheduled")
    }

    @Test("dropped diagnostic records preserve alert id and reason")
    func droppedDiagnosticRecordsPreserveAlertIdAndReason() {
        let record = AlertDiagnostics.makeDroppedRecord(alertId: "event-1-stage2", reason: "missing-alert-record")

        #expect(record.event == .deliveryDropped)
        #expect(record.alertId == "event-1-stage2")
        #expect(record.reason == "missing-alert-record")
        #expect(record.eventId == nil)
        #expect(record.stage == nil)
    }

    @Test("representative alert lifecycle events are available")
    func representativeAlertLifecycleEventsAreAvailable() {
        let events: Set<AlertDiagnosticEvent> = [
            .alertRecordCreated,
            .localModalTriggerScheduled,
            .osNotificationScheduled,
            .modalPresented,
            .commandCompleted,
            .scheduledEffectsCanceled,
            .deliveryDropped,
        ]

        #expect(events.contains(.alertRecordCreated))
        #expect(events.contains(.osNotificationScheduled))
        #expect(events.contains(.deliveryDropped))
    }
}

private func makeDiagnosticAlert() throws -> ScheduledAlert {
    let eventStart = Date(timeIntervalSince1970: 1_803_000_000)
    let joinURL = try #require(URL(string: "https://meet.google.com/diagnostic-room"))
    return ScheduledAlert(
        id: "event-1-stage2",
        eventId: "calendar-1/event-1",
        stage: .stage2,
        scheduledFireTime: eventStart.addingTimeInterval(-2 * 60),
        eventTitle: "Diagnostic Review",
        eventStartTime: eventStart,
        eventEndTime: eventStart.addingTimeInterval(30 * 60),
        joinURL: joinURL,
        contextLine: "after Planning"
    )
}

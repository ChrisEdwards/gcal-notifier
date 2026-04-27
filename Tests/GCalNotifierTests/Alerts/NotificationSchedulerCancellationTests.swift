import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("NotificationScheduler Cancellation Tests")
struct NotificationSchedulerCancellationTests {
    @Test("Cancel durable notification removes pending and delivered notification")
    func cancelDurableNotificationRemovesPendingAndDelivered() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)
        let alert = ScheduledAlert(
            id: "alert-1",
            eventId: "cal-1::event-1",
            stage: .stage2,
            scheduledFireTime: Date(timeIntervalSince1970: 1_801_200_000),
            eventTitle: "Meeting",
            eventStartTime: Date(timeIntervalSince1970: 1_801_200_120)
        )

        await scheduler.scheduleNotification(for: alert)
        await scheduler.cancelNotification(alertId: alert.id)

        #expect(mockCenter.pendingRequests.isEmpty)
        #expect(mockCenter.removedIdentifiers.count { $0 == alert.id } == 2)
    }
}

import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("NotificationScheduler Cancellation Tests")
struct NotificationSchedulerCancellationTests {
    @Test("Cancel pending durable notification leaves delivered notification visible")
    func cancelPendingDurableNotificationLeavesDeliveredVisible() async {
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
        await scheduler.cancelPendingNotification(alertId: alert.id)

        #expect(mockCenter.pendingRequests.isEmpty)
        #expect(mockCenter.removedPendingIdentifiers == [alert.id])
        #expect(mockCenter.removedDeliveredIdentifiers.isEmpty)
    }

    @Test("Remove delivered durable notification removes delivered only")
    func removeDeliveredDurableNotificationRemovesDeliveredOnly() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        await scheduler.removeDeliveredNotification(alertId: "alert-1")

        #expect(mockCenter.pendingRequests.isEmpty)
        #expect(mockCenter.removedPendingIdentifiers.isEmpty)
        #expect(mockCenter.removedDeliveredIdentifiers == ["alert-1"])
    }
}

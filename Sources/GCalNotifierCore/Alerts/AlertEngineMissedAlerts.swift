import Foundation

public extension AlertEngine {
    private static let missedAlertGracePeriod: TimeInterval = 5 * 60

    func rearmScheduledTimers() async {
        let now = self.dateProvider()
        for alert in self.alerts.values where alert.scheduledFireTime > now {
            await self.scheduleTimer(for: alert)
        }
    }

    func checkForMissedAlerts() async -> [MissedAlertResult] {
        let now = self.dateProvider()
        var results: [MissedAlertResult] = []
        let missedAlerts = self.alerts.values.filter {
            $0.scheduledFireTime < now && $0.missedDeliveryTime == nil
        }
        for alert in missedAlerts {
            let timeSinceMeetingStart = now.timeIntervalSince(alert.eventStartTime)
            let result: MissedAlertResult
            var shouldKeepAlert = false
            if timeSinceMeetingStart < 0 {
                result = .fireNow(alert)
                await self.delivery.deliver(alert: alert)
                shouldKeepAlert = true
            } else if timeSinceMeetingStart < Self.missedAlertGracePeriod {
                result = .meetingJustStarted(alert)
                await self.delivery.deliver(alert: alert)
                shouldKeepAlert = true
            } else {
                result = .tooOld(alert)
            }
            results.append(result)
            await self.cancelScheduledDelivery(for: alert, deliveredNotificationPolicy: .keepDelivered)
            if shouldKeepAlert {
                self.alerts[alert.id] = self.updatedAlertForMissed(alert, now: now)
            } else {
                self.alerts.removeValue(forKey: alert.id)
            }
        }
        if !results.isEmpty {
            await self.persistAlerts()
        }
        return results
    }

    private func updatedAlertForMissed(_ alert: ScheduledAlert, now: Date) -> ScheduledAlert {
        ScheduledAlert(
            id: alert.id,
            eventId: alert.eventId,
            stage: alert.stage,
            scheduledFireTime: now,
            snoozeCount: alert.snoozeCount,
            originalFireTime: alert.originalFireTime,
            missedDeliveryTime: now,
            eventTitle: alert.eventTitle,
            eventStartTime: alert.eventStartTime,
            eventEndTime: alert.eventEndTime,
            joinURL: alert.joinURL,
            calendarURL: alert.calendarURL,
            contextLine: alert.contextLine,
            notificationPayload: alert.notificationPayload
        )
    }
}

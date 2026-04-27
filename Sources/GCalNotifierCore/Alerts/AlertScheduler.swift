import Foundation

/// Protocol for scheduling and canceling timer-based alert delivery.
/// Abstracted to allow testing with mocks.
public protocol AlertScheduler: Sendable {
    func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) async
    func cancel(alertId: String) async
    func cancelAll() async
}

/// Protocol for durable OS notification delivery that can survive app process interruptions.
public protocol DurableAlertNotificationScheduler: Sendable {
    func scheduleNotification(for alert: ScheduledAlert) async
    func cancelNotification(alertId: String) async
    func cancelAllNotifications() async
}

/// No-op durable scheduler for tests and contexts without notification support.
public struct NoOpDurableAlertNotificationScheduler: DurableAlertNotificationScheduler {
    public init() {}

    public func scheduleNotification(for _: ScheduledAlert) async {}

    public func cancelNotification(alertId _: String) async {}

    public func cancelAllNotifications() async {}
}

/// Default alert scheduler using DispatchSourceTimer.
public actor DispatchAlertScheduler: AlertScheduler {
    private var timers: [String: DispatchSourceTimer] = [:]

    public init() {}

    public func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) {
        self.cancel(alertId: alertId)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        let interval = max(0, fireDate.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { handler() }
        timer.resume()
        self.timers[alertId] = timer
    }

    public func cancel(alertId: String) {
        if let timer = timers.removeValue(forKey: alertId) {
            timer.cancel()
        }
    }

    public func cancelAll() {
        for (_, timer) in self.timers {
            timer.cancel()
        }
        self.timers.removeAll()
    }
}

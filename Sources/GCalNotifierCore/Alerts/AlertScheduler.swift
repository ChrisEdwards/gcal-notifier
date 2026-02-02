import Foundation

/// Protocol for scheduling and canceling timer-based alert delivery.
/// Abstracted to allow testing with mocks.
public protocol AlertScheduler: Sendable {
    func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) async
    func cancel(alertId: String) async
    func cancelAll() async
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

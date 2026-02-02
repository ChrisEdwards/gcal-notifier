import Foundation
import Testing
@testable import GCalNotifier

// MARK: - Mock Delegate

@MainActor
private final class MockSleepWakeDelegate: SleepWakeHandlerDelegate {
    private(set) var wakeCount = 0
    private(set) var sleepCount = 0

    nonisolated func sleepWakeHandlerDidWake(_: SleepWakeHandler) async {
        await MainActor.run {
            self.wakeCount += 1
        }
    }

    nonisolated func sleepWakeHandlerWillSleep(_: SleepWakeHandler) async {
        await MainActor.run {
            self.sleepCount += 1
        }
    }
}

// MARK: - Tests

@Suite("SleepWakeHandler Tests")
@MainActor
struct SleepWakeHandlerTests {
    @Test("handler can be initialized")
    func handlerCanBeInitialized() {
        let handler = SleepWakeHandler()
        #expect(handler != nil)
    }

    @Test("startMonitoring can be called")
    func startMonitoringCanBeCalled() {
        let handler = SleepWakeHandler()
        handler.startMonitoring()
        // Clean up
        handler.stopMonitoring()
    }

    @Test("stopMonitoring can be called without starting")
    func stopMonitoringCanBeCalledWithoutStarting() {
        let handler = SleepWakeHandler()
        handler.stopMonitoring()
        // Should not crash
    }

    @Test("startMonitoring is idempotent")
    func startMonitoringIsIdempotent() {
        let handler = SleepWakeHandler()
        handler.startMonitoring()
        handler.startMonitoring() // Should be no-op
        handler.stopMonitoring()
    }

    @Test("stopMonitoring is idempotent")
    func stopMonitoringIsIdempotent() {
        let handler = SleepWakeHandler()
        handler.startMonitoring()
        handler.stopMonitoring()
        handler.stopMonitoring() // Should be no-op
    }

    @Test("delegate can be set")
    func delegateCanBeSet() {
        let handler = SleepWakeHandler()
        let delegate = MockSleepWakeDelegate()
        handler.setDelegate(delegate)
        // Should not crash
    }

    @Test("delegate can be set to nil")
    func delegateCanBeSetToNil() {
        let handler = SleepWakeHandler()
        let delegate = MockSleepWakeDelegate()
        handler.setDelegate(delegate)
        handler.setDelegate(nil)
        // Should not crash
    }
}

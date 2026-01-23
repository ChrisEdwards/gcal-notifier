import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Errors

private enum TestError: Error, LocalizedError {
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case let .syncFailed(message):
            "Sync failed: \(message)"
        }
    }
}

// MARK: - Mock Delegate

private struct HealthChange: Sendable {
    let calendarId: String
    let from: CalendarHealth
    let to: CalendarHealth
}

private actor MockHealthDelegate: CalendarHealthDelegate {
    var changes: [HealthChange] = []

    func healthTracker(
        _: CalendarHealthTracker,
        didChangeHealthFor calendarId: String,
        from oldHealth: CalendarHealth,
        to newHealth: CalendarHealth
    ) async {
        self.changes.append(HealthChange(calendarId: calendarId, from: oldHealth, to: newHealth))
    }

    func getChanges() -> [HealthChange] { self.changes }
    func reset() { self.changes.removeAll() }
}

// MARK: - Test Helpers

private func makeTracker() -> CalendarHealthTracker {
    CalendarHealthTracker(disabledCalendarsPersistence: MockDisabledCalendarsPersistence())
}

private func reachFailingState(_ tracker: CalendarHealthTracker, calendarId: String) async {
    for _ in 0 ..< CalendarHealthTracker.failureThreshold {
        await tracker.markFailure(for: calendarId, error: TestError.syncFailed("test"))
    }
}

// MARK: - Health State Tests

@Suite("HealthTracker State Tests")
struct HealthTrackerStateTests {
    @Test("new calendar starts healthy")
    func newCalendarStartsHealthy() async {
        let tracker = makeTracker()
        #expect(await tracker.health(for: "new-cal") == .healthy)
    }

    @Test("consecutive failures count increments")
    func consecutiveFailuresIncrement() async {
        let tracker = makeTracker()
        await tracker.markFailure(for: "cal-1", error: TestError.syncFailed("test"))
        #expect(await tracker.consecutiveFailures(for: "cal-1") == 1)
    }

    @Test("transitions to failing after threshold")
    func transitionsToFailingAfterThreshold() async {
        let tracker = makeTracker()
        await reachFailingState(tracker, calendarId: "cal-1")
        #expect(await tracker.health(for: "cal-1") == .failing)
    }

    @Test("stays healthy below threshold")
    func staysHealthyBelowThreshold() async {
        let tracker = makeTracker()
        await tracker.markFailure(for: "cal-1", error: TestError.syncFailed("test"))
        await tracker.markFailure(for: "cal-1", error: TestError.syncFailed("test"))
        #expect(await tracker.health(for: "cal-1") == .healthy)
        #expect(await tracker.consecutiveFailures(for: "cal-1") == 2)
    }

    @Test("success resets failures and health")
    func successResetsFailuresAndHealth() async {
        let tracker = makeTracker()
        await reachFailingState(tracker, calendarId: "cal-1")
        await tracker.markSuccess(for: "cal-1")
        #expect(await tracker.consecutiveFailures(for: "cal-1") == 0)
        #expect(await tracker.health(for: "cal-1") == .healthy)
    }

    @Test("tracks and clears last error")
    func tracksAndClearsLastError() async {
        let tracker = makeTracker()
        await tracker.markFailure(for: "cal-1", error: TestError.syncFailed("network timeout"))
        #expect(await tracker.lastError(for: "cal-1")?.contains("network timeout") == true)
        await tracker.markSuccess(for: "cal-1")
        #expect(await tracker.lastError(for: "cal-1") == nil)
    }
}

// MARK: - Disabled State Tests

@Suite("HealthTracker Disabled Tests")
struct HealthTrackerDisabledTests {
    @Test("disable and enable calendar")
    func disableAndEnableCalendar() async {
        let tracker = makeTracker()
        await tracker.disable("cal-1")
        #expect(await tracker.health(for: "cal-1") == .disabled)
        await tracker.enable("cal-1")
        #expect(await tracker.health(for: "cal-1") == .healthy)
    }

    @Test("disabled not affected by sync operations")
    func disabledNotAffectedBySyncOperations() async {
        let tracker = makeTracker()
        await tracker.disable("cal-1")
        await tracker.markFailure(for: "cal-1", error: TestError.syncFailed("test"))
        #expect(await tracker.health(for: "cal-1") == .disabled)
        await tracker.markSuccess(for: "cal-1")
        #expect(await tracker.health(for: "cal-1") == .disabled)
    }

    @Test("disabledCalendarIds returns correct set")
    func disabledCalendarIdsReturnsCorrectSet() async {
        let tracker = makeTracker()
        await tracker.disable("cal-1")
        await tracker.disable("cal-2")
        await tracker.disable("cal-3")
        await tracker.enable("cal-2")
        #expect(await tracker.disabledCalendarIds() == ["cal-1", "cal-3"])
    }

    @Test("disabled state persists across instances")
    func disabledStatePersistsAcrossInstances() async {
        let persistence = MockDisabledCalendarsPersistence()
        let tracker1 = CalendarHealthTracker(disabledCalendarsPersistence: persistence)
        await tracker1.disable("cal-1")
        let tracker2 = CalendarHealthTracker(disabledCalendarsPersistence: persistence)
        #expect(await tracker2.health(for: "cal-1") == .disabled)
    }
}

// MARK: - Polling Multiplier Tests

@Suite("HealthTracker Polling Tests")
struct HealthTrackerPollingTests {
    @Test("healthy has 1x multiplier")
    func healthyHas1xMultiplier() async {
        let tracker = makeTracker()
        #expect(await tracker.pollingMultiplier(for: "cal-1") == 1.0)
    }

    @Test("failing has 4x multiplier")
    func failingHas4xMultiplier() async {
        let tracker = makeTracker()
        await reachFailingState(tracker, calendarId: "cal-1")
        #expect(await tracker.pollingMultiplier(for: "cal-1") == CalendarHealthTracker.failingPollingMultiplier)
    }

    @Test("disabled has infinity multiplier")
    func disabledHasInfinityMultiplier() async {
        let tracker = makeTracker()
        await tracker.disable("cal-1")
        #expect(await tracker.pollingMultiplier(for: "cal-1") == Double.infinity)
    }

    @Test("shouldPoll returns correct values")
    func shouldPollReturnsCorrectValues() async {
        let tracker = makeTracker()
        #expect(await tracker.shouldPoll("cal-1") == true)
        await reachFailingState(tracker, calendarId: "cal-1")
        #expect(await tracker.shouldPoll("cal-1") == true)
        await tracker.disable("cal-2")
        #expect(await tracker.shouldPoll("cal-2") == false)
    }
}

// MARK: - Delegate Tests

@Suite("HealthTracker Delegate Tests")
struct HealthTrackerDelegateTests {
    @Test("delegate notified on state transitions")
    func delegateNotifiedOnStateTransitions() async {
        let tracker = makeTracker()
        let delegate = MockHealthDelegate()
        await tracker.setDelegate(delegate)

        // Transition to failing
        await reachFailingState(tracker, calendarId: "cal-1")
        var changes = await delegate.getChanges()
        #expect(changes.count == 1)
        #expect(changes[0].calendarId == "cal-1")
        #expect(changes[0].from == .healthy)
        #expect(changes[0].to == .failing)

        // Recovery to healthy
        await delegate.reset()
        await tracker.markSuccess(for: "cal-1")
        changes = await delegate.getChanges()
        #expect(changes.count == 1)
        #expect(changes[0].from == .failing)
        #expect(changes[0].to == .healthy)
    }

    @Test("delegate notified on disable/enable")
    func delegateNotifiedOnDisableEnable() async {
        let tracker = makeTracker()
        let delegate = MockHealthDelegate()
        await tracker.setDelegate(delegate)

        await tracker.disable("cal-1")
        var changes = await delegate.getChanges()
        #expect(changes.count == 1)
        #expect(changes[0].to == .disabled)

        await delegate.reset()
        await tracker.enable("cal-1")
        changes = await delegate.getChanges()
        #expect(changes.count == 1)
        #expect(changes[0].from == .disabled)
        #expect(changes[0].to == .healthy)
    }

    @Test("delegate not notified when no change")
    func delegateNotNotifiedWhenNoChange() async {
        let tracker = makeTracker()
        let delegate = MockHealthDelegate()
        await tracker.setDelegate(delegate)

        await tracker.markSuccess(for: "cal-1") // Already healthy
        #expect(await delegate.getChanges().isEmpty)

        await tracker.disable("cal-1")
        await delegate.reset()
        await tracker.disable("cal-1") // Already disabled
        #expect(await delegate.getChanges().isEmpty)
    }
}

// MARK: - Reset Tests

@Suite("HealthTracker Reset Tests")
struct HealthTrackerResetTests {
    @Test("resetTransientStates clears failing but not disabled")
    func resetTransientStatesClearsFailingButNotDisabled() async {
        let tracker = makeTracker()
        await reachFailingState(tracker, calendarId: "cal-1")
        await tracker.disable("cal-2")
        await tracker.markFailure(for: "cal-3", error: TestError.syncFailed("test"))

        await tracker.resetTransientStates()

        #expect(await tracker.health(for: "cal-1") == .healthy)
        #expect(await tracker.health(for: "cal-2") == .disabled)
        #expect(await tracker.consecutiveFailures(for: "cal-3") == 0)
    }
}

// MARK: - All States & Multi-Calendar Tests

@Suite("HealthTracker Multi-Calendar Tests")
struct HealthTrackerMultiCalendarTests {
    @Test("allHealthStates returns combined states")
    func allHealthStatesReturnsCombinedStates() async {
        let tracker = makeTracker()
        await tracker.markSuccess(for: "healthy-cal")
        await reachFailingState(tracker, calendarId: "failing-cal")
        await tracker.disable("disabled-cal")

        let states = await tracker.allHealthStates()
        #expect(states["healthy-cal"] == .healthy)
        #expect(states["failing-cal"] == .failing)
        #expect(states["disabled-cal"] == .disabled)
    }

    @Test("disabled overrides in-memory state")
    func disabledOverridesInMemoryState() async {
        let persistence = MockDisabledCalendarsPersistence()
        let tracker = CalendarHealthTracker(disabledCalendarsPersistence: persistence)
        await tracker.markSuccess(for: "cal-1")
        persistence.setDisabled(true, for: "cal-1")
        let states = await tracker.allHealthStates()
        #expect(states["cal-1"] == .disabled)
    }

    @Test("tracks multiple calendars independently")
    func tracksMultipleCalendarsIndependently() async {
        let tracker = makeTracker()
        await reachFailingState(tracker, calendarId: "cal-1")
        await tracker.markFailure(for: "cal-2", error: TestError.syncFailed("test"))
        await tracker.disable("cal-3")

        #expect(await tracker.health(for: "cal-1") == .failing)
        #expect(await tracker.health(for: "cal-2") == .healthy)
        #expect(await tracker.health(for: "cal-3") == .disabled)
        #expect(await tracker.consecutiveFailures(for: "cal-4") == 0)
    }
}

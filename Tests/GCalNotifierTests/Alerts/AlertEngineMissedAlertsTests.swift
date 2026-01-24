import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - MockDateProvider

/// Thread-safe mock date provider for tests that need to advance time.
private final class MockDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentDate: Date

    init(_ date: Date = Date()) {
        self._currentDate = date
    }

    var now: Date {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._currentDate
    }

    func advance(by seconds: TimeInterval) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self._currentDate = self._currentDate.addingTimeInterval(seconds)
    }
}

@Suite("AlertEngine Missed Alerts Tests")
struct AlertEngineMissedAlertsTests {
    // MARK: - Test: No missed alerts when all alerts are in the future

    @Test("checkForMissedAlerts returns empty when no alerts are missed")
    func checkForMissedAlertsReturnsEmptyWhenNoMissedAlerts() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create an event 30 minutes in the future
        let futureEventStart = dateProvider.now.addingTimeInterval(30 * 60)
        let event = makeAlertTestEvent(startTime: futureEventStart)

        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Check for missed alerts - should be empty since alerts are in the future
        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.isEmpty)
    }

    // MARK: - Test: Missed alert - meeting not started yet

    @Test("checkForMissedAlerts fires alert immediately when meeting hasn't started")
    func checkForMissedAlertsFiringWhenMeetingNotStarted() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create an event 20 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(20 * 60)
        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)

        // Schedule alerts with 10-minute warning
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance time by 15 minutes to simulate wake
        dateProvider.advance(by: 15 * 60)

        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.count == 1)

        if case let .fireNow(alert) = missedResults.first {
            #expect(alert.eventId == event.qualifiedId)
        } else {
            Issue.record("Expected .fireNow result, got \(String(describing: missedResults.first))")
        }

        let deliveredAlerts = await delivery.deliveredAlerts
        #expect(deliveredAlerts.count == 1)
        #expect(deliveredAlerts.first?.eventId == event.qualifiedId)
    }

    // MARK: - Test: Missed alert - meeting just started

    @Test("checkForMissedAlerts returns meetingJustStarted when meeting started <5 min ago")
    func checkForMissedAlertsReturnsMeetingJustStartedWithinGracePeriod() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create an event 10 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(10 * 60)
        let event = makeAlertTestEvent(id: "event-2", startTime: eventStart)

        // Schedule alerts with 5-minute warning
        let settings = try makeAlertTestSettings(stage1Minutes: 5, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance time 13 minutes - meeting started 3 minutes ago (within grace period)
        dateProvider.advance(by: 13 * 60)

        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.count == 1)

        if case let .meetingJustStarted(alert) = missedResults.first {
            #expect(alert.eventId == event.qualifiedId)
        } else {
            Issue.record("Expected .meetingJustStarted result, got \(String(describing: missedResults.first))")
        }

        let deliveredAlerts = await delivery.deliveredAlerts
        #expect(deliveredAlerts.count == 1)
    }

    // MARK: - Test: Missed alert - meeting too old

    @Test("checkForMissedAlerts returns tooOld when meeting started >5 min ago")
    func checkForMissedAlertsReturnsTooOldBeyondGracePeriod() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create an event 10 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(10 * 60)
        let event = makeAlertTestEvent(id: "event-3", startTime: eventStart)

        // Schedule alerts with 5-minute warning
        let settings = try makeAlertTestSettings(stage1Minutes: 5, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance time 20 minutes - meeting started 10 minutes ago (beyond grace period)
        dateProvider.advance(by: 20 * 60)

        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.count == 1)

        if case let .tooOld(alert) = missedResults.first {
            #expect(alert.eventId == event.qualifiedId)
        } else {
            Issue.record("Expected .tooOld result, got \(String(describing: missedResults.first))")
        }

        // Verify alert was NOT delivered (too old)
        let deliveredAlerts = await delivery.deliveredAlerts
        #expect(deliveredAlerts.isEmpty)
    }

    // MARK: - Test: Missed alerts are removed from the engine

    @Test("checkForMissedAlerts removes processed alerts from engine")
    func checkForMissedAlertsRemovesProcessedAlerts() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create an event 20 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(20 * 60)
        let event = makeAlertTestEvent(id: "event-4", startTime: eventStart)

        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Verify alert is scheduled
        let alertsBefore = await engine.scheduledAlerts
        #expect(alertsBefore.count == 1)

        // Advance time 15 minutes (alert is now missed)
        dateProvider.advance(by: 15 * 60)

        _ = await engine.checkForMissedAlerts()

        // Verify alert is removed
        let alertsAfter = await engine.scheduledAlerts
        #expect(alertsAfter.isEmpty)
    }

    // MARK: - Test: Multiple missed alerts

    @Test("checkForMissedAlerts returns three results for three missed alerts")
    func checkForMissedAlertsReturnsThreeResultsForThreeMissedAlerts() async throws {
        let scenario = try await setupMultipleMissedAlertsScenario()
        #expect(scenario.results.count == 3)
    }

    @Test("checkForMissedAlerts categorizes multiple alerts correctly")
    func checkForMissedAlertsCategoriesCorrectly() async throws {
        let scenario = try await setupMultipleMissedAlertsScenario()
        let counts = self.countMissedAlertTypes(scenario.results)
        #expect(counts.fireNow == 1)
        #expect(counts.justStarted == 1)
        #expect(counts.tooOld == 1)
    }

    @Test("checkForMissedAlerts delivers only non-stale alerts")
    func checkForMissedAlertsDeliversOnlyNonStaleAlerts() async throws {
        let scenario = try await setupMultipleMissedAlertsScenario()
        let deliveredAlerts = await scenario.delivery.deliveredAlerts
        #expect(deliveredAlerts.count == 2)
    }

    // MARK: - Test Helpers

    private struct MissedAlertScenarioResult {
        let engine: AlertEngine
        let delivery: MockAlertDelivery
        let results: [MissedAlertResult]
    }

    private struct MissedAlertCounts {
        var fireNow: Int
        var justStarted: Int
        var tooOld: Int
    }

    private func setupMultipleMissedAlertsScenario() async throws -> MissedAlertScenarioResult {
        let tempURL = makeAlertTestTempFileURL()
        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Using 5-minute warning: alert fires at (eventStart - 5 min)
        // All alerts must be schedulable (fire time in future at t=0) AND missed (fire time in past at check)
        //
        // At t=0 (schedule time):
        //   Event 1: starts t+20, alert fires t+15 (in future)
        //   Event 2: starts t+12, alert fires t+7  (in future)
        //   Event 3: starts t+10, alert fires t+5  (in future)
        //
        // At t=17 (check time):
        //   Alert 1 (t+15) is 2 min in past - missed. Meeting (t+20) is 3 min away -> fireNow
        //   Alert 2 (t+7) is 10 min in past - missed. Meeting (t+12) was 5 min ago -> tooOld (at boundary)
        //   Alert 3 (t+5) is 12 min in past - missed. Meeting (t+10) was 7 min ago -> tooOld
        //
        // Need to adjust for one justStarted. Let's use t=14 check time:
        //   Alert 1 (t+15) is 1 min in future - NOT missed
        //   Alert 2 (t+7) is 7 min in past - missed. Meeting (t+12) was 2 min ago -> justStarted
        //   Alert 3 (t+5) is 9 min in past - missed. Meeting (t+10) was 4 min ago -> justStarted
        //
        // Final setup: Use different event times to get all 3 scenarios
        // At t=0:
        //   Event 1: starts t+25, alert fires t+20 (fireNow scenario: alert missed, meeting not started)
        //   Event 2: starts t+18, alert fires t+13 (justStarted: alert missed, meeting 0-5 min ago)
        //   Event 3: starts t+12, alert fires t+7  (tooOld: alert missed, meeting >5 min ago)
        //
        // At t=22:
        //   Alert 1 (t+20) is 2 min past - missed. Meeting (t+25) is 3 min away -> fireNow
        //   Alert 2 (t+13) is 9 min past - missed. Meeting (t+18) was 4 min ago -> justStarted
        //   Alert 3 (t+7) is 15 min past - missed. Meeting (t+12) was 10 min ago -> tooOld
        let baseTime = dateProvider.now
        let event1 = makeAlertTestEvent(id: "event-future", startTime: baseTime.addingTimeInterval(25 * 60))
        let event2 = makeAlertTestEvent(id: "event-recent", startTime: baseTime.addingTimeInterval(18 * 60))
        let event3 = makeAlertTestEvent(id: "event-old", startTime: baseTime.addingTimeInterval(12 * 60))

        let settings = try makeAlertTestSettings(stage1Minutes: 5, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event1, event2, event3], settings: settings)

        // Advance by 22 minutes
        dateProvider.advance(by: 22 * 60)
        let missedResults = await engine.checkForMissedAlerts()

        return MissedAlertScenarioResult(engine: engine, delivery: delivery, results: missedResults)
    }

    private func countMissedAlertTypes(_ results: [MissedAlertResult]) -> MissedAlertCounts {
        var counts = MissedAlertCounts(fireNow: 0, justStarted: 0, tooOld: 0)
        for result in results {
            switch result {
            case .fireNow: counts.fireNow += 1
            case .meetingJustStarted: counts.justStarted += 1
            case .tooOld: counts.tooOld += 1
            }
        }
        return counts
    }

    // MARK: - Test: Grace period boundary

    @Test("checkForMissedAlerts uses exactly 5 minute grace period")
    func checkForMissedAlertsUsesExactGracePeriod() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create event 10 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(10 * 60)
        let event = makeAlertTestEvent(id: "event-boundary", startTime: eventStart)

        let settings = try makeAlertTestSettings(stage1Minutes: 5, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance 15 minutes - meeting started exactly 5 minutes ago
        dateProvider.advance(by: 15 * 60)

        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.count == 1)

        // At exactly 5 minutes, it should be "too old" (>= 5 min is too old)
        if case .tooOld = missedResults.first {
            // Expected - 5 minutes is at the boundary, treated as too old
        } else {
            Issue.record("Expected .tooOld at 5-minute boundary, got \(String(describing: missedResults.first))")
        }
    }

    // MARK: - Test: Just under grace period

    @Test("checkForMissedAlerts returns meetingJustStarted just under 5 minute boundary")
    func checkForMissedAlertsReturnsMeetingJustStartedUnderBoundary() async throws {
        let tempURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(tempURL) }

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let scheduler = await MockAlertScheduler()
        let delivery = await MockAlertDelivery()
        let dateProvider = MockDateProvider()

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            dateProvider: { dateProvider.now }
        )

        // Create event 10 minutes in the future
        let eventStart = dateProvider.now.addingTimeInterval(10 * 60)
        let event = makeAlertTestEvent(id: "event-under-boundary", startTime: eventStart)

        let settings = try makeAlertTestSettings(stage1Minutes: 5, stage2Minutes: 0)
        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance so meeting started 4 minutes 59 seconds ago
        dateProvider.advance(by: 10 * 60 + 4 * 60 + 59)

        let missedResults = await engine.checkForMissedAlerts()

        #expect(missedResults.count == 1)

        // Just under 5 minutes should be "meeting just started"
        if case .meetingJustStarted = missedResults.first {
            // Expected
        } else {
            Issue.record(
                "Expected .meetingJustStarted under boundary, got \(String(describing: missedResults.first))"
            )
        }
    }
}

import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Context

/// Context for AlertEngine presentation mode tests
private struct PresentationModeTestContext {
    let engine: AlertEngine
    let scheduler: MockAlertScheduler
    let delivery: MockAlertDelivery
    let fileURL: URL
    let baseTime: Date
    let eventStart: Date

    func cleanup() {
        cleanupAlertTestTempDir(self.fileURL)
    }
}

/// Creates a test context with all dependencies
private func makePresentationModeContext() async -> PresentationModeTestContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let delivery = MockAlertDelivery()

    // Use a fixed base time for consistent testing
    let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    let eventStart = baseTime.addingTimeInterval(3600) // 1 hour from base time

    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: delivery,
        dateProvider: { baseTime }
    )

    return PresentationModeTestContext(
        engine: engine,
        scheduler: scheduler,
        delivery: delivery,
        fileURL: fileURL,
        baseTime: baseTime,
        eventStart: eventStart
    )
}

// MARK: - AlertEngine Presentation Mode Suppression Tests

@Suite("AlertEngine Presentation Mode Suppression Tests")
struct AlertEnginePresentationModeTests {
    // MARK: - Provider Configuration Tests

    @Test("setting presentation mode provider stores it")
    func settingPresentationModeProvider() async {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // We can't easily track if provider was called due to Sendable requirements
        // Just verify that setting the provider doesn't crash
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .screenSharing
        }

        // Provider is set - verify by clearing and checking behavior
        await context.engine.clearPresentationModeProvider()
    }

    @Test("clearing presentation mode provider removes it")
    func clearingPresentationModeProvider() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up a provider that would downgrade
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .screenSharing
        }

        // Clear the provider
        await context.engine.clearPresentationModeProvider()

        // Schedule and fire an alert - it should NOT be downgraded
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be delivered normally, not downgraded
        let delivered = await context.delivery.deliveredAlerts
        let downgraded = await context.delivery.downgradedAlerts

        #expect(delivered.count == 1)
        #expect(downgraded.isEmpty)
    }

    // MARK: - Suppression Logic Tests

    @Test("alert is downgraded when screen sharing detected")
    func alertDowngradedWhenScreenSharing() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up provider to indicate screen sharing
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .screenSharing
        }

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be downgraded with screenSharing reason
        let downgraded = await context.delivery.downgradedAlerts
        #expect(downgraded.count == 1)
        #expect(downgraded.first?.reason == .screenSharing)
    }

    @Test("alert is downgraded when DND enabled")
    func alertDowngradedWhenDND() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up provider to indicate DND
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .doNotDisturb
        }

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be downgraded with doNotDisturb reason
        let downgraded = await context.delivery.downgradedAlerts
        #expect(downgraded.count == 1)
        #expect(downgraded.first?.reason == .doNotDisturb)
    }

    @Test("alert is delivered normally when no presentation mode")
    func alertDeliveredNormallyWhenNotPresenting() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up provider to indicate no presentation mode
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            nil // Not presenting
        }

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be delivered normally
        let delivered = await context.delivery.deliveredAlerts
        let downgraded = await context.delivery.downgradedAlerts

        #expect(delivered.count == 1)
        #expect(downgraded.isEmpty)
    }

    @Test("presentation mode takes priority over back-to-back")
    func presentationModeTakesPriorityOverBackToBack() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up BOTH providers - presentation mode and back-to-back
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .screenSharing // Screen sharing active
        }

        await context.engine.setBackToBackContextProvider { _ in
            BackToBackAlertContext(
                isInMeeting: true,
                isBackToBackSituation: true,
                currentMeeting: nil
            )
        }

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be downgraded with screenSharing reason (not backToBackMeeting)
        let downgraded = await context.delivery.downgradedAlerts
        #expect(downgraded.count == 1)
        #expect(downgraded.first?.reason == .screenSharing)
    }

    @Test("back-to-back used when no presentation mode")
    func backToBackUsedWhenNoPresentationMode() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Set up presentation mode provider to return nil
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            nil // Not presenting
        }

        // Set up back-to-back provider to indicate in meeting
        await context.engine.setBackToBackContextProvider { _ in
            BackToBackAlertContext(
                isInMeeting: true,
                isBackToBackSituation: true,
                currentMeeting: nil
            )
        }

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be downgraded with backToBackMeeting reason
        let downgraded = await context.delivery.downgradedAlerts
        #expect(downgraded.count == 1)
        #expect(downgraded.first?.reason == .backToBackMeeting)
    }

    @Test("stage 2 alerts are suppressed by presentation mode")
    func stage2AlertsSuppressedByPresentationMode() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Presentation mode suppresses ALL alerts, including stage 2
        await context.engine.setPresentationModeProvider { () -> AlertDowngradeReason? in
            .screenSharing
        }

        // Schedule an alert with stage 2 (event start 120s from base time)
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let stage2EventStart = context.baseTime.addingTimeInterval(180) // 3 minutes from base
        let event = makeAlertTestEvent(startTime: stage2EventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the stage 2 alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage2")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Stage 2 alert should also be downgraded due to presentation mode
        let downgraded = await context.delivery.downgradedAlerts
        #expect(downgraded.count == 1)
        #expect(downgraded.first?.reason == .screenSharing)
    }

    @Test("no provider means normal delivery")
    func noProviderMeansNormalDelivery() async throws {
        let context = await makePresentationModeContext()
        defer { context.cleanup() }

        // Don't set any provider

        // Schedule an alert
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
        let event = makeAlertTestEvent(startTime: context.eventStart)
        await context.engine.scheduleAlerts(for: [event], settings: settings)

        // Fire the alert
        await context.scheduler.fireAlert(alertId: "\(event.id)-stage1")

        // Wait for async handling
        try await Task.sleep(nanoseconds: 100_000_000)

        // Alert should be delivered normally
        let delivered = await context.delivery.deliveredAlerts
        let downgraded = await context.delivery.downgradedAlerts

        #expect(delivered.count == 1)
        #expect(downgraded.isEmpty)
    }
}

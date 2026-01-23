import AppKit
import Foundation
import Testing

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a test CalendarEvent with default values.
private func makeTestEvent(
    id: String = "test-event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date().addingTimeInterval(600),
    endTime: Date = Date().addingTimeInterval(3600),
    isAllDay: Bool = false,
    location: String? = nil,
    meetingLinks: [MeetingLink] = [],
    isOrganizer: Bool = false,
    attendeeCount: Int = 2,
    responseStatus: ResponseStatus = .accepted
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: calendarId,
        title: title,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
        meetingLinks: meetingLinks,
        isOrganizer: isOrganizer,
        attendeeCount: attendeeCount,
        responseStatus: responseStatus
    )
}

/// Creates a test MeetingLink.
private func makeTestMeetingLink(
    urlString: String = "https://meet.google.com/abc-defg-hij"
) -> MeetingLink? {
    guard let url = URL(string: urlString) else { return nil }
    return MeetingLink(url: url, platform: .googleMeet)
}

// MARK: - AlertWindowActions Tests

@Suite("AlertWindowActions Tests")
struct AlertWindowActionsTests {
    @MainActor
    @Test("Actions struct initializes with closures")
    func actionsInitialization() {
        var joinCalled = false
        var snoozeCalled = false
        var snoozeValue: TimeInterval = 0
        var openCalendarCalled = false
        var dismissCalled = false

        let actions = AlertWindowActions(
            onJoin: { joinCalled = true },
            onSnooze: { duration in
                snoozeCalled = true
                snoozeValue = duration
            },
            onOpenCalendar: { openCalendarCalled = true },
            onDismiss: { dismissCalled = true }
        )

        actions.onJoin()
        #expect(joinCalled)

        actions.onSnooze(300)
        #expect(snoozeCalled)
        #expect(snoozeValue == 300)

        actions.onOpenCalendar()
        #expect(openCalendarCalled)

        actions.onDismiss()
        #expect(dismissCalled)
    }
}

// MARK: - AlertWindowController Tests

@Suite("AlertWindowController Tests")
struct AlertWindowControllerTests {
    @MainActor
    @Test("Controller creates NSPanel as window")
    func createsNSPanel() {
        let controller = AlertWindowController()
        #expect(controller.window is NSPanel)
    }

    @MainActor
    @Test("Panel has floating level")
    func panelHasFloatingLevel() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.level == .floating)
    }

    @MainActor
    @Test("Panel has canJoinAllSpaces collection behavior")
    func panelHasCanJoinAllSpaces() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @MainActor
    @Test("Panel has fullScreenAuxiliary collection behavior")
    func panelHasFullScreenAuxiliary() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @MainActor
    @Test("Panel has transparent titlebar")
    func panelHasTransparentTitlebar() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.titlebarAppearsTransparent)
    }

    @MainActor
    @Test("Panel has hidden title")
    func panelHasHiddenTitle() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.titleVisibility == .hidden)
    }

    @MainActor
    @Test("Panel has shadow")
    func panelHasShadow() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.hasShadow)
    }

    @MainActor
    @Test("Panel is movable by window background")
    func panelIsMovableByBackground() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.isMovableByWindowBackground)
    }

    @MainActor
    @Test("Panel has closable style")
    func panelHasClosableStyle() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.styleMask.contains(.closable))
    }

    @MainActor
    @Test("Panel has non-activating panel style")
    func panelHasNonActivatingStyle() {
        let controller = AlertWindowController()
        guard let panel = controller.window as? NSPanel else {
            Issue.record("Window is not an NSPanel")
            return
        }
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }
}

// MARK: - AlertContentProvider Tests

@Suite("AlertContentProvider Tests")
struct AlertContentProviderTests {
    @MainActor
    @Test("DefaultAlertContentProvider creates view with event info")
    func defaultProviderCreatesView() {
        let event = makeTestEvent(title: "Test Meeting")
        let provider = DefaultAlertContentProvider()

        var joinCalled = false
        let actions = AlertWindowActions(
            onJoin: { joinCalled = true },
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        let view = provider.makeContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            actions: actions
        )

        // Just verify it returns something - can't really test SwiftUI view internals
        #expect(type(of: view) == PlaceholderAlertContent.self)
    }

    @MainActor
    @Test("DefaultAlertContentProvider handles snooze context without error")
    func providerHandlesSnoozeContext() {
        let event = makeTestEvent()
        let provider = DefaultAlertContentProvider()

        let actions = AlertWindowActions(
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        // Should create view successfully with snooze info
        // We can't inspect SwiftUI view internals, but we verify it doesn't crash
        let view = provider.makeContentView(
            event: event,
            stage: .stage2,
            isSnoozed: true,
            snoozeContext: "10:00 AM",
            actions: actions
        )

        // Verify it returns the expected type
        #expect(type(of: view) == PlaceholderAlertContent.self)
    }
}

// MARK: - Show Alert Tests

@Suite("Show Alert Tests")
struct ShowAlertTests {
    @MainActor
    @Test("showAlert sets content view on window")
    func showAlertSetsContentView() {
        let controller = AlertWindowController()
        let event = makeTestEvent()

        controller.showAlert(for: event, stage: .stage1)

        #expect(controller.window?.contentView != nil)
    }

    @MainActor
    @Test("showAlert makes window visible")
    func showAlertMakesWindowVisible() {
        let controller = AlertWindowController()
        let event = makeTestEvent()

        controller.showAlert(for: event, stage: .stage1)

        #expect(controller.window?.isVisible == true)
    }

    @MainActor
    @Test("showAlert with snoozed flag works")
    func showAlertWithSnoozed() {
        let controller = AlertWindowController()
        let event = makeTestEvent()

        // Should not throw or crash
        controller.showAlert(
            for: event,
            stage: .stage2,
            snoozed: true,
            snoozeContext: "Originally at 9:30 AM"
        )

        #expect(controller.window?.contentView != nil)
    }
}

// MARK: - Alert Engine Integration Tests

@Suite("Alert Engine Integration Tests")
struct AlertEngineIntegrationTests {
    @MainActor
    @Test("setAlertEngine stores engine reference")
    func setAlertEngineStoresReference() async throws {
        let controller = AlertWindowController()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString)")
            .appendingPathComponent("alerts.json")

        try FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let store = ScheduledAlertsStore(fileURL: tempURL)
        let engine = await AlertEngine(alertsStore: store)

        controller.setAlertEngine(engine)

        // Engine is stored internally - we can verify by showing an alert
        // and checking the controller doesn't crash when dismissing
        let event = makeTestEvent()
        controller.showAlert(for: event, stage: .stage1)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }
}

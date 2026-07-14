import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import GCalNotifierCore

@Suite("DispatchAlertScheduler Tests")
struct DispatchAlertSchedulerTests {
    @Test("Short wall-clock timer fires")
    func shortWallClockTimerFires() async throws {
        let scheduler = DispatchAlertScheduler()
        let didFire = SendableBox(false)

        await scheduler.schedule(
            alertId: "short-wall-clock-timer",
            fireDate: Date().addingTimeInterval(0.02)
        ) {
            didFire.value = true
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(didFire.value)
        await scheduler.cancelAll()
    }
}

@Suite("NotificationScheduler Tests")
struct NotificationSchedulerTests {
    @Test("Schedule creates notification request with correct identifier")
    func scheduleCreatesRequestWithCorrectIdentifier() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-1", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        #expect(requests.count == 1)
        #expect(requests.first?.identifier == "test-alert-1")
    }

    @Test("Schedule creates notification with correct category")
    func scheduleCreatesRequestWithCorrectCategory() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-2", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first
        #expect(request?.categoryIdentifier == NotificationScheduler.meetingAlertCategory)
    }

    @Test("Schedule creates notification with silent sound")
    func scheduleCreatesRequestWithSilentSound() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-3", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first
        #expect(request?.soundIsNil == true)
    }

    @Test("Immediate fallback notification is visible and audible")
    func immediateFallbackNotificationIsVisibleAndAudible() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        await scheduler.showBannerNotification(
            title: "Upcoming meeting",
            body: "Planning starts soon",
            identifier: "fallback-alert"
        )

        let request = mockCenter.pendingRequests.first
        #expect(request?.isActive == true)
        #expect(request?.soundIsNil == false)
    }

    @Test("Schedule creates calendar trigger with correct date")
    func scheduleCreatesCalendarTriggerWithCorrectDate() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let calendar = Calendar.current
        guard let fireDate = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 0)
        ) else {
            Issue.record("Failed to create test date")
            return
        }

        await scheduler.schedule(alertId: "test-alert-4", fireDate: fireDate) {}

        let requests = mockCenter.pendingRequests
        let request = requests.first

        #expect(request?.triggerYear == 2026)
        #expect(request?.triggerMonth == 6)
        #expect(request?.triggerDay == 15)
        #expect(request?.triggerHour == 14)
        #expect(request?.triggerMinute == 30)
        #expect(request?.triggerRepeats == false)
    }

    @Test("Cancel removes pending notification")
    func cancelRemovesPendingNotification() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-5", fireDate: fireDate) {}

        let requestsBefore = mockCenter.pendingRequests
        #expect(requestsBefore.count == 1)

        await scheduler.cancel(alertId: "test-alert-5")

        #expect(mockCenter.removedPendingIdentifiers.contains("test-alert-5"))
        #expect(mockCenter.removedDeliveredIdentifiers.contains("test-alert-5"))
    }

    @Test("CancelAll removes all pending notifications")
    func cancelAllRemovesAllPendingNotifications() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date().addingTimeInterval(3600)

        await scheduler.schedule(alertId: "test-alert-7a", fireDate: fireDate) {}
        await scheduler.schedule(alertId: "test-alert-7b", fireDate: fireDate) {}
        await scheduler.schedule(alertId: "test-alert-7c", fireDate: fireDate) {}

        let requestsBefore = mockCenter.pendingRequests
        #expect(requestsBefore.count == 3)

        await scheduler.cancelAll()

        let requestsAfter = mockCenter.pendingRequests
        #expect(requestsAfter.isEmpty)
    }

    @Test("Categories are registered on initialization")
    func categoriesAreRegisteredOnInitialization() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        _ = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let categoryIds = mockCenter.registeredCategoryIdentifiers
        let expectedIds = [
            NotificationScheduler.meetingAlertCategory, NotificationScheduler.backToBackAlertCategory,
            NotificationScheduler.stage1AlertCategory, NotificationScheduler.stage1Snooze1Category,
            NotificationScheduler.stage1Snooze3Category, NotificationScheduler.stage1Snooze5Category,
            NotificationScheduler.stage2AlertCategory, NotificationScheduler.stage2Snooze1Category,
            NotificationScheduler.stage2Snooze3Category, NotificationScheduler.stage2Snooze5Category,
        ]
        #expect(Set(categoryIds) == Set(expectedIds))
    }

    @Test("Delegate is set on initialization")
    func delegateIsSetOnInitialization() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        _ = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let delegateSet = mockCenter.delegateSet
        #expect(delegateSet)
    }

    @Test("Authorization status returns correct value")
    func authorizationStatusReturnsCorrectValue() async {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        mockCenter.setAuthorizationStatus(.denied)
        let status = await scheduler.authorizationStatus()
        #expect(status == .denied)
    }
}

@Suite("NotificationDelegate Tests")
struct NotificationDelegateTests {
    @Test("Register stores handler for alert ID")
    func registerStoresHandler() async {
        let delegate = NotificationDelegate()
        let handlerCalled = SendableBox(false)

        await delegate.register(alertId: "delegate-test-1") {
            handlerCalled.value = true
        }

        // Verify handler can be fired
        await delegate.testFireHandler(alertId: "delegate-test-1")
        #expect(handlerCalled.value)
    }

    @Test("Handler is removed after firing")
    func handlerIsRemovedAfterFiring() async {
        let delegate = NotificationDelegate()
        let callCount = SendableBox(0)

        await delegate.register(alertId: "delegate-test-2") {
            callCount.value += 1
        }

        await delegate.testFireHandler(alertId: "delegate-test-2")
        await delegate.testFireHandler(alertId: "delegate-test-2")

        #expect(callCount.value == 1)
    }

    @Test("Unregister removes handler")
    func unregisterRemovesHandler() async {
        let delegate = NotificationDelegate()
        let handlerCalled = SendableBox(false)

        await delegate.register(alertId: "delegate-test-3") {
            handlerCalled.value = true
        }

        await delegate.unregister(alertId: "delegate-test-3")
        await delegate.testFireHandler(alertId: "delegate-test-3")

        #expect(!handlerCalled.value)
    }

    @Test("UnregisterAll removes all handlers")
    func unregisterAllRemovesAllHandlers() async {
        let delegate = NotificationDelegate()
        let count = SendableBox(0)

        await delegate.register(alertId: "delegate-test-4a") { count.value += 1 }
        await delegate.register(alertId: "delegate-test-4b") { count.value += 1 }
        await delegate.register(alertId: "delegate-test-4c") { count.value += 1 }

        await delegate.unregisterAll()

        await delegate.testFireHandler(alertId: "delegate-test-4a")
        await delegate.testFireHandler(alertId: "delegate-test-4b")
        await delegate.testFireHandler(alertId: "delegate-test-4c")

        #expect(count.value == 0)
    }

    @Test("Firing unknown alert ID does nothing")
    func firingUnknownAlertDoesNothing() async {
        let delegate = NotificationDelegate()
        await delegate.testFireHandler(alertId: "nonexistent-alert")
    }

    @Test("Back-to-back category allows banner presentation")
    func backToBackCategoryAllowsBannerPresentation() {
        let options = NotificationDelegate.presentationOptions(
            forCategoryIdentifier: NotificationScheduler.backToBackAlertCategory
        )
        #expect(options.contains(.banner))
        #expect(options.contains(.list))
    }

    @Test("Meeting category suppresses presentation")
    func meetingCategorySuppressesPresentation() {
        let options = NotificationDelegate.presentationOptions(
            forCategoryIdentifier: NotificationScheduler.meetingAlertCategory
        )
        #expect(options.isEmpty)
    }

    @Test("Stage 1 category allows banner presentation")
    func stage1CategoryAllowsBannerPresentation() {
        let options = NotificationDelegate.presentationOptions(
            forCategoryIdentifier: NotificationScheduler.stage1AlertCategory
        )
        #expect(options.contains(.banner))
        #expect(options.contains(.list))
    }

    @Test("Stage 2 category allows banner presentation")
    func stage2CategoryAllowsBannerPresentation() {
        let options = NotificationDelegate.presentationOptions(
            forCategoryIdentifier: NotificationScheduler.stage2AlertCategory
        )
        #expect(options.contains(.banner))
        #expect(options.contains(.list))
    }
}

@Suite("NotificationAuthorizationStatus Tests")
struct NotificationAuthorizationStatusTests {
    @Test("Conversion from UNAuthorizationStatus")
    func conversionFromUNAuthorizationStatus() {
        #expect(NotificationAuthorizationStatus(from: .notDetermined) == .notDetermined)
        #expect(NotificationAuthorizationStatus(from: .denied) == .denied)
        #expect(NotificationAuthorizationStatus(from: .authorized) == .authorized)
        #expect(NotificationAuthorizationStatus(from: .provisional) == .provisional)
        // Note: .ephemeral is not available on macOS
    }
}

final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    var value: T {
        get {
            self.lock.lock()
            defer { lock.unlock() }
            return self._value
        }
        set {
            self.lock.lock()
            defer { lock.unlock() }
            self._value = newValue
        }
    }

    init(_ value: T) {
        self._value = value
    }
}

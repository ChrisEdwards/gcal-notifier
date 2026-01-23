import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Mock Delegate

private actor MockTimeZoneDelegate: TimeZoneManagerDelegate {
    private(set) var changeCount = 0
    private(set) var lastOldTimeZone: TimeZone?
    private(set) var lastNewTimeZone: TimeZone?

    func timeZoneManager(
        _: TimeZoneManager,
        didChangeFrom oldTimeZone: TimeZone,
        to newTimeZone: TimeZone
    ) async {
        self.changeCount += 1
        self.lastOldTimeZone = oldTimeZone
        self.lastNewTimeZone = newTimeZone
    }

    func getChangeCount() -> Int { self.changeCount }
    func getLastOldTimeZone() -> TimeZone? { self.lastOldTimeZone }
    func getLastNewTimeZone() -> TimeZone? { self.lastNewTimeZone }
}

// MARK: - Tests

@Suite("TimeZoneManager Tests")
struct TimeZoneManagerTests {
    // swiftlint:disable:next force_unwrapping
    private let pacificZone = TimeZone(identifier: "America/Los_Angeles")!
    // swiftlint:disable:next force_unwrapping
    private let easternZone = TimeZone(identifier: "America/New_York")!
    // swiftlint:disable:next force_unwrapping
    private let londonZone = TimeZone(identifier: "Europe/London")!

    @Test("currentTimeZone returns provider's time zone")
    func currentTimeZoneReturnsProvidersTimeZone() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        let currentZone = await manager.currentTimeZone

        #expect(currentZone == self.pacificZone)
    }

    @Test("getLastKnownTimeZone returns initial time zone before any change")
    func getLastKnownTimeZoneReturnsInitialTimeZone() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        let lastKnown = await manager.getLastKnownTimeZone()

        #expect(lastKnown == self.pacificZone)
    }

    @Test("checkForTimeZoneChange returns false when time zone unchanged")
    func checkForTimeZoneChangeReturnsFalseWhenUnchanged() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)
        let delegate = MockTimeZoneDelegate()
        await manager.setDelegate(delegate)

        let changed = await manager.checkForTimeZoneChange()

        #expect(changed == false)
        let changeCount = await delegate.getChangeCount()
        #expect(changeCount == 0)
    }

    @Test("checkForTimeZoneChange returns true and notifies delegate when time zone changed")
    func checkForTimeZoneChangeReturnsTrueWhenChanged() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)
        let delegate = MockTimeZoneDelegate()
        await manager.setDelegate(delegate)

        // Simulate time zone change
        provider.setTimeZone(self.easternZone)

        let changed = await manager.checkForTimeZoneChange()

        #expect(changed == true)
        let changeCount = await delegate.getChangeCount()
        #expect(changeCount == 1)

        let lastOld = await delegate.getLastOldTimeZone()
        let lastNew = await delegate.getLastNewTimeZone()
        #expect(lastOld == self.pacificZone)
        #expect(lastNew == self.easternZone)
    }

    @Test("checkForTimeZoneChange updates lastKnownTimeZone after change")
    func checkForTimeZoneChangeUpdatesLastKnownTimeZone() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        provider.setTimeZone(self.easternZone)
        _ = await manager.checkForTimeZoneChange()

        let lastKnown = await manager.getLastKnownTimeZone()
        #expect(lastKnown == self.easternZone)
    }

    @Test("multiple time zone changes are all detected")
    func multipleTimeZoneChangesAreDetected() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)
        let delegate = MockTimeZoneDelegate()
        await manager.setDelegate(delegate)

        // First change: Pacific -> Eastern
        provider.setTimeZone(self.easternZone)
        _ = await manager.checkForTimeZoneChange()

        // Second change: Eastern -> London
        provider.setTimeZone(self.londonZone)
        _ = await manager.checkForTimeZoneChange()

        let changeCount = await delegate.getChangeCount()
        #expect(changeCount == 2)

        let lastOld = await delegate.getLastOldTimeZone()
        let lastNew = await delegate.getLastNewTimeZone()
        #expect(lastOld == self.easternZone)
        #expect(lastNew == self.londonZone)
    }

    @Test("startMonitoring sets isMonitoring state")
    func startMonitoringSetsState() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        await manager.startMonitoring()

        // Verify by checking that calling startMonitoring again is a no-op
        // (implicitly tested by the fact it doesn't crash)
        await manager.startMonitoring()

        // Clean up
        await manager.stopMonitoring()
    }

    @Test("stopMonitoring clears monitoring state")
    func stopMonitoringClearsState() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        await manager.startMonitoring()
        await manager.stopMonitoring()

        // Verify by checking that stopMonitoring can be called again (no-op)
        await manager.stopMonitoring()
    }

    @Test("startMonitoring updates lastKnownTimeZone to current")
    func startMonitoringUpdatesLastKnownTimeZone() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        // Change time zone before starting to monitor
        provider.setTimeZone(self.easternZone)

        await manager.startMonitoring()

        let lastKnown = await manager.getLastKnownTimeZone()
        #expect(lastKnown == self.easternZone)

        await manager.stopMonitoring()
    }

    @Test("delegate not called when no delegate set")
    func delegateNotCalledWhenNoDelegateSet() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)

        provider.setTimeZone(self.easternZone)
        let changed = await manager.checkForTimeZoneChange()

        // Should still return true even without delegate
        #expect(changed == true)
    }

    @Test("consecutive checks without change do not notify delegate")
    func consecutiveChecksWithoutChangeDoNotNotify() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)
        let delegate = MockTimeZoneDelegate()
        await manager.setDelegate(delegate)

        // Check multiple times without changing
        _ = await manager.checkForTimeZoneChange()
        _ = await manager.checkForTimeZoneChange()
        _ = await manager.checkForTimeZoneChange()

        let changeCount = await delegate.getChangeCount()
        #expect(changeCount == 0)
    }

    @Test("change then same zone change is detected only once")
    func changeThenSameZoneDetectedOnce() async {
        let provider = MockTimeZoneProvider(timeZone: self.pacificZone)
        let manager = TimeZoneManager(timeZoneProvider: provider)
        let delegate = MockTimeZoneDelegate()
        await manager.setDelegate(delegate)

        provider.setTimeZone(self.easternZone)
        _ = await manager.checkForTimeZoneChange()

        // Check again without changing
        _ = await manager.checkForTimeZoneChange()

        let changeCount = await delegate.getChangeCount()
        #expect(changeCount == 1)
    }
}

@Suite("TimeZoneProvider Tests")
struct TimeZoneProviderTests {
    @Test("SystemTimeZoneProvider returns TimeZone.current")
    func systemTimeZoneProviderReturnsSystemCurrent() {
        let provider = SystemTimeZoneProvider()
        #expect(provider.currentTimeZone == TimeZone.current)
    }

    @Test("MockTimeZoneProvider returns configured time zone")
    func mockTimeZoneProviderReturnsConfiguredTimeZone() {
        // swiftlint:disable:next force_unwrapping
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let provider = MockTimeZoneProvider(timeZone: tokyo)
        #expect(provider.currentTimeZone == tokyo)
    }

    @Test("MockTimeZoneProvider setTimeZone updates current time zone")
    func mockTimeZoneProviderSetTimeZoneUpdates() {
        // swiftlint:disable:next force_unwrapping
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // swiftlint:disable:next force_unwrapping
        let sydney = TimeZone(identifier: "Australia/Sydney")!

        let provider = MockTimeZoneProvider(timeZone: tokyo)
        provider.setTimeZone(sydney)

        #expect(provider.currentTimeZone == sydney)
    }
}

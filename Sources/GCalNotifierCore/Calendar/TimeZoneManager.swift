import Foundation
import OSLog

// MARK: - TimeZoneManagerDelegate

/// Delegate protocol for receiving time zone change notifications.
public protocol TimeZoneManagerDelegate: AnyObject, Sendable {
    /// Called when the system time zone changes.
    /// - Parameters:
    ///   - manager: The TimeZoneManager that detected the change.
    ///   - oldTimeZone: The previous time zone.
    ///   - newTimeZone: The new current time zone.
    func timeZoneManager(
        _ manager: TimeZoneManager,
        didChangeFrom oldTimeZone: TimeZone,
        to newTimeZone: TimeZone
    ) async
}

// MARK: - TimeZoneManager

/// Monitors system time zone changes for traveling users and DST transitions.
///
/// `TimeZoneManager` observes `NSSystemTimeZoneDidChange` notifications and notifies
/// its delegate when the time zone changes. This enables the app to refresh calendar
/// data when users travel across time zones or when DST transitions occur.
///
/// ## Usage
/// ```swift
/// let manager = TimeZoneManager()
/// manager.setDelegate(syncCoordinator)
/// await manager.startMonitoring()
/// // Later when done:
/// await manager.stopMonitoring()
/// ```
///
/// ## Thread Safety
/// TimeZoneManager is an actor, ensuring all state access is serialized.
/// The delegate callback is dispatched to the main actor-isolated context.
public actor TimeZoneManager {
    // MARK: - Dependencies

    private let notificationCenter: NotificationCenter
    private let logger = Logger.sync
    private let timeZoneProvider: TimeZoneProvider

    // MARK: - State

    private weak var delegate: TimeZoneManagerDelegate?
    private var lastKnownTimeZone: TimeZone
    private var isMonitoring = false
    private var notificationTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a TimeZoneManager with optional custom dependencies for testing.
    /// - Parameters:
    ///   - notificationCenter: The notification center to observe (defaults to `.default`).
    ///   - timeZoneProvider: Provider for current time zone (defaults to system).
    public init(
        notificationCenter: NotificationCenter = .default,
        timeZoneProvider: TimeZoneProvider = SystemTimeZoneProvider()
    ) {
        self.notificationCenter = notificationCenter
        self.timeZoneProvider = timeZoneProvider
        self.lastKnownTimeZone = timeZoneProvider.currentTimeZone
    }

    // MARK: - Public API

    /// Sets the delegate for receiving time zone change notifications.
    public func setDelegate(_ delegate: TimeZoneManagerDelegate?) {
        self.delegate = delegate
    }

    /// Returns the current system time zone.
    public var currentTimeZone: TimeZone {
        self.timeZoneProvider.currentTimeZone
    }

    /// Returns the last known time zone (before any detected change).
    public func getLastKnownTimeZone() -> TimeZone {
        self.lastKnownTimeZone
    }

    /// Starts monitoring for time zone changes.
    /// - Note: Safe to call multiple times; subsequent calls are no-ops.
    public func startMonitoring() {
        guard !self.isMonitoring else {
            self.logger.debug("TimeZoneManager already monitoring")
            return
        }

        self.isMonitoring = true
        self.lastKnownTimeZone = self.timeZoneProvider.currentTimeZone
        self.logger.info("TimeZoneManager started monitoring, current zone: \(self.lastKnownTimeZone.identifier)")

        self.notificationTask = Task { [weak self] in
            await self?.observeNotifications()
        }
    }

    /// Stops monitoring for time zone changes.
    public func stopMonitoring() {
        guard self.isMonitoring else { return }

        self.isMonitoring = false
        self.notificationTask?.cancel()
        self.notificationTask = nil
        self.logger.info("TimeZoneManager stopped monitoring")
    }

    /// Manually checks for time zone change and notifies delegate if changed.
    /// Useful for checking after wake from sleep.
    /// - Returns: True if the time zone changed, false otherwise.
    @discardableResult
    public func checkForTimeZoneChange() async -> Bool {
        let currentZone = self.timeZoneProvider.currentTimeZone

        if currentZone != self.lastKnownTimeZone {
            let oldZone = self.lastKnownTimeZone
            self.lastKnownTimeZone = currentZone

            self.logger.info(
                "Time zone changed: \(oldZone.identifier) → \(currentZone.identifier)"
            )

            await self.delegate?.timeZoneManager(self, didChangeFrom: oldZone, to: currentZone)
            return true
        }

        return false
    }

    // MARK: - Private Methods

    private func observeNotifications() async {
        let notifications = self.notificationCenter.notifications(
            named: .NSSystemTimeZoneDidChange,
            object: nil
        )

        for await _ in notifications {
            guard self.isMonitoring else { break }
            await self.checkForTimeZoneChange()
        }
    }
}

// MARK: - TimeZoneProvider Protocol

/// Protocol for providing the current time zone. Enables testing.
public protocol TimeZoneProvider: Sendable {
    var currentTimeZone: TimeZone { get }
}

// MARK: - SystemTimeZoneProvider

/// Default provider that returns the system's current time zone.
public struct SystemTimeZoneProvider: TimeZoneProvider, Sendable {
    public init() {}

    public var currentTimeZone: TimeZone {
        TimeZone.current
    }
}

// MARK: - MockTimeZoneProvider

/// Mock provider for testing time zone changes.
public final class MockTimeZoneProvider: TimeZoneProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentTimeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self._currentTimeZone = timeZone
    }

    public var currentTimeZone: TimeZone {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._currentTimeZone
    }

    public func setTimeZone(_ timeZone: TimeZone) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self._currentTimeZone = timeZone
    }
}

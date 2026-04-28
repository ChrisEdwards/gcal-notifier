import AppKit
import Foundation
import GCalNotifierCore
import OSLog

// MARK: - SleepWakeHandlerDelegate

/// Delegate protocol for receiving sleep/wake notifications.
public protocol SleepWakeHandlerDelegate: AnyObject, Sendable {
    /// Called when the system wakes from sleep.
    func sleepWakeHandlerDidWake(_ handler: SleepWakeHandler) async

    /// Called when the system is about to sleep.
    func sleepWakeHandlerWillSleep(_ handler: SleepWakeHandler) async
}

// MARK: - SleepWakeHandler

/// Handles system sleep and wake events for proper recovery.
///
/// When the system wakes from sleep, this handler:
/// 1. Triggers an immediate calendar sync
/// 2. Lets alert reconciliation mirror the desired state into OS notifications and local modal triggers
///
/// ## Usage
/// ```swift
/// let handler = SleepWakeHandler()
/// handler.setDelegate(appCoordinator)
/// handler.startMonitoring()
/// ```
@MainActor
public final class SleepWakeHandler {
    // MARK: - Dependencies

    private let logger = Logger.app
    private weak var delegate: SleepWakeHandlerDelegate?

    // MARK: - State

    private var isMonitoring = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Sets the delegate for receiving sleep/wake notifications.
    public func setDelegate(_ delegate: SleepWakeHandlerDelegate?) {
        self.delegate = delegate
    }

    /// Starts monitoring for sleep/wake notifications.
    public func startMonitoring() {
        guard !self.isMonitoring else {
            self.logger.debug("SleepWakeHandler already monitoring")
            return
        }

        self.isMonitoring = true

        let workspace = NSWorkspace.shared

        // Subscribe to sleep notification
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(self.willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        // Subscribe to wake notification
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(self.didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        self.logger.info("SleepWakeHandler started monitoring")
    }

    /// Stops monitoring for sleep/wake notifications.
    public func stopMonitoring() {
        guard self.isMonitoring else { return }

        self.isMonitoring = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        self.logger.info("SleepWakeHandler stopped monitoring")
    }

    // MARK: - Notification Handlers

    @objc private func willSleep(_: Notification) {
        self.logger.info("System going to sleep")

        Task { [weak self] in
            guard let self else { return }
            await self.delegate?.sleepWakeHandlerWillSleep(self)
        }
    }

    @objc private func didWake(_: Notification) {
        self.logger.info("System woke from sleep")

        Task { [weak self] in
            guard let self else { return }
            await self.delegate?.sleepWakeHandlerDidWake(self)
        }
    }
}

// MARK: - WakeRecoveryCoordinator

/// Coordinates wake recovery without reconstructing missed exact-time modal delivery.
struct WakeRecoveryCoordinator: Sendable {
    private let syncAndReconcile: @MainActor @Sendable () async -> Void

    init(syncAndReconcile: @escaping @MainActor @Sendable () async -> Void) {
        self.syncAndReconcile = syncAndReconcile
    }

    @MainActor
    func recoverFromWake() async {
        Logger.app.info("System woke - syncing and reconciling alerts")
        await self.syncAndReconcile()
    }
}

// MARK: - AppDelegate SleepWakeHandlerDelegate

extension AppDelegate: SleepWakeHandlerDelegate {
    nonisolated func sleepWakeHandlerDidWake(_: SleepWakeHandler) async {
        await self.recoverFromSystemWake()
    }

    nonisolated func sleepWakeHandlerWillSleep(_: SleepWakeHandler) async {
        await MainActor.run {
            Logger.app.info("System sleeping - timers may pause")
        }
    }

    @MainActor
    private func recoverFromSystemWake() async {
        let recovery = WakeRecoveryCoordinator {
            await self.performSync()
        }
        await recovery.recoverFromWake()
    }
}

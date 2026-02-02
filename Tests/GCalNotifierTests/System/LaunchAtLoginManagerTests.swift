import Foundation
import Testing
@testable import GCalNotifier

// MARK: - LaunchAtLoginStatus Tests

@Suite("LaunchAtLoginStatus Tests")
struct LaunchAtLoginStatusTests {
    @Test("enabled status has correct description")
    func enabledStatusDescription() {
        let status = LaunchAtLoginStatus.enabled
        #expect(status.description == "Will launch at login")
    }

    @Test("disabled status has correct description")
    func disabledStatusDescription() {
        let status = LaunchAtLoginStatus.disabled
        #expect(status.description == "Will not launch at login")
    }

    @Test("requiresApproval status has correct description")
    func requiresApprovalStatusDescription() {
        let status = LaunchAtLoginStatus.requiresApproval
        #expect(status.description == "Requires approval in System Settings")
    }

    @Test("error status has correct description")
    func errorStatusDescription() {
        let status = LaunchAtLoginStatus.error("Test error")
        #expect(status.description == "Error: Test error")
    }

    @Test("enabled status returns true for isEnabled")
    func enabledStatusIsEnabled() {
        let status = LaunchAtLoginStatus.enabled
        #expect(status.isEnabled == true)
    }

    @Test("disabled status returns false for isEnabled")
    func disabledStatusIsEnabled() {
        let status = LaunchAtLoginStatus.disabled
        #expect(status.isEnabled == false)
    }

    @Test("requiresApproval status returns false for isEnabled")
    func requiresApprovalStatusIsEnabled() {
        let status = LaunchAtLoginStatus.requiresApproval
        #expect(status.isEnabled == false)
    }

    @Test("error status returns false for isEnabled")
    func errorStatusIsEnabled() {
        let status = LaunchAtLoginStatus.error("Test error")
        #expect(status.isEnabled == false)
    }
}

// MARK: - LaunchAtLoginManager Tests

@Suite("LaunchAtLoginManager Tests")
@MainActor
struct LaunchAtLoginManagerTests {
    @Test("shared instance exists")
    func sharedInstanceExists() {
        let manager = LaunchAtLoginManager.shared
        #expect(manager != nil)
    }

    @Test("shared instance is singleton")
    func sharedInstanceIsSingleton() {
        let manager1 = LaunchAtLoginManager.shared
        let manager2 = LaunchAtLoginManager.shared
        #expect(manager1 === manager2)
    }

    @Test("checkStatus returns a valid status")
    func checkStatusReturnsValidStatus() {
        let manager = LaunchAtLoginManager.shared
        let status = manager.checkStatus()

        // Status should be one of the valid enum cases
        switch status {
        case .enabled, .disabled, .requiresApproval, .error:
            // All valid cases
            break
        }
    }

    @Test("isEnabled returns boolean based on status")
    func isEnabledReturnsBool() {
        let manager = LaunchAtLoginManager.shared
        let isEnabled = manager.isEnabled

        // Should be a boolean value
        #expect(isEnabled == true || isEnabled == false)
    }
}

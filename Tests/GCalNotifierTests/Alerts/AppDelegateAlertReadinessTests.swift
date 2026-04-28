import Testing
@testable import GCalNotifier

@Suite("Alert Readiness Gate Tests")
struct AlertReadinessGateTests {
    @MainActor
    @Test("Wait fails hard before alert setup starts")
    func waitFailsHardBeforeAlertSetupStarts() async {
        do {
            _ = try await AlertReadinessGate<Int>().wait()
            Issue.record("Expected alert readiness failure")
        } catch let error as AlertReadinessGateError {
            #expect(error == .notStarted)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test("Wait returns setup result after alert setup completes")
    func waitReturnsSetupResultAfterAlertSetupCompletes() async throws {
        let gate = AlertReadinessGate<Int>()
        gate.start(Task { 42 })

        let value = try await gate.wait()

        #expect(value == 42)
    }
}

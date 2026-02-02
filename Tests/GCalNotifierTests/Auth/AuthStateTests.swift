import Testing
@testable import GCalNotifierCore

/// Tests for AuthState enum and its predicates.
@Suite("AuthState Tests")
struct AuthStateTests {
    // MARK: - canMakeApiCalls Tests

    @Test("canMakeApiCalls returns true for authenticated state")
    func canMakeApiCallsAuthenticated() {
        #expect(AuthState.authenticated.canMakeApiCalls == true)
    }

    @Test("canMakeApiCalls returns true for expired state")
    func canMakeApiCallsExpired() {
        #expect(AuthState.expired.canMakeApiCalls == true)
    }

    @Test("canMakeApiCalls returns false for configured state")
    func canMakeApiCallsConfigured() {
        #expect(AuthState.configured.canMakeApiCalls == false)
    }

    @Test("canMakeApiCalls returns false for unconfigured state")
    func canMakeApiCallsUnconfigured() {
        #expect(AuthState.unconfigured.canMakeApiCalls == false)
    }

    @Test("canMakeApiCalls returns false for authenticating state")
    func canMakeApiCallsAuthenticating() {
        #expect(AuthState.authenticating.canMakeApiCalls == false)
    }

    @Test("canMakeApiCalls returns false for invalid state")
    func canMakeApiCallsInvalid() {
        #expect(AuthState.invalid.canMakeApiCalls == false)
    }

    // MARK: - hasCredentials Tests

    @Test("hasCredentials returns true for configured state")
    func hasCredentialsConfigured() {
        #expect(AuthState.configured.hasCredentials == true)
    }

    @Test("hasCredentials returns false for unconfigured state")
    func hasCredentialsUnconfigured() {
        #expect(AuthState.unconfigured.hasCredentials == false)
    }

    @Test("hasCredentials returns true for authenticating state")
    func hasCredentialsAuthenticating() {
        #expect(AuthState.authenticating.hasCredentials == true)
    }

    @Test("hasCredentials returns true for authenticated state")
    func hasCredentialsAuthenticated() {
        #expect(AuthState.authenticated.hasCredentials == true)
    }

    @Test("hasCredentials returns true for expired state")
    func hasCredentialsExpired() {
        #expect(AuthState.expired.hasCredentials == true)
    }

    @Test("hasCredentials returns true for invalid state")
    func hasCredentialsInvalid() {
        #expect(AuthState.invalid.hasCredentials == true)
    }

    // MARK: - requiresUserAction Tests

    @Test("requiresUserAction returns true for unconfigured state")
    func requiresUserActionUnconfigured() {
        #expect(AuthState.unconfigured.requiresUserAction == true)
    }

    @Test("requiresUserAction returns true for configured state")
    func requiresUserActionConfigured() {
        #expect(AuthState.configured.requiresUserAction == true)
    }

    @Test("requiresUserAction returns true for invalid state")
    func requiresUserActionInvalid() {
        #expect(AuthState.invalid.requiresUserAction == true)
    }

    @Test("requiresUserAction returns false for authenticating state")
    func requiresUserActionAuthenticating() {
        #expect(AuthState.authenticating.requiresUserAction == false)
    }

    @Test("requiresUserAction returns false for authenticated state")
    func requiresUserActionAuthenticated() {
        #expect(AuthState.authenticated.requiresUserAction == false)
    }

    @Test("requiresUserAction returns false for expired state")
    func requiresUserActionExpired() {
        #expect(AuthState.expired.requiresUserAction == false)
    }

    // MARK: - Equatable Tests

    @Test("Same states are equal")
    func equatableSameStates() {
        #expect(AuthState.unconfigured == AuthState.unconfigured)
        #expect(AuthState.configured == AuthState.configured)
        #expect(AuthState.authenticating == AuthState.authenticating)
        #expect(AuthState.authenticated == AuthState.authenticated)
        #expect(AuthState.expired == AuthState.expired)
        #expect(AuthState.invalid == AuthState.invalid)
    }

    @Test("Different states are not equal")
    func equatableDifferentStates() {
        #expect(AuthState.unconfigured != AuthState.configured)
        #expect(AuthState.configured != AuthState.authenticated)
        #expect(AuthState.authenticated != AuthState.expired)
        #expect(AuthState.expired != AuthState.invalid)
    }

    // MARK: - All States Coverage Test

    @Test("All states have complete predicate coverage")
    func allStatesHaveCoverage() {
        let allStates: [AuthState] = [
            .unconfigured,
            .configured,
            .authenticating,
            .authenticated,
            .expired,
            .invalid,
        ]

        // Verify each state has deterministic predicate values
        for state in allStates {
            // These should not crash - verifies all cases are handled
            _ = state.canMakeApiCalls
            _ = state.hasCredentials
            _ = state.requiresUserAction
        }

        #expect(allStates.count == 6, "All 6 states should be tested")
    }
}

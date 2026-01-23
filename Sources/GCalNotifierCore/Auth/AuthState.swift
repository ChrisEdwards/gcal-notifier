/// Authentication state machine for OAuth lifecycle.
///
/// `AuthState` represents the complete set of states the authentication system
/// can be in. It is designed to be explicit and exhaustive, preventing edge cases
/// that arise from implicit or undefined states.
///
/// ## States
/// - `unconfigured`: No OAuth credentials have been entered
/// - `configured`: Has credentials but user hasn't signed in
/// - `authenticating`: OAuth flow is in progress
/// - `authenticated`: Valid tokens present
/// - `expired`: Token expired, will auto-refresh
/// - `invalid`: Refresh failed, needs re-authentication
///
/// ## Example
/// ```swift
/// switch authState {
/// case .unconfigured, .configured, .invalid:
///     showSetupView()
/// case .authenticating:
///     showLoadingSpinner()
/// case .authenticated, .expired:
///     proceedWithApiCalls()
/// }
/// ```
public enum AuthState: Equatable, Sendable {
    /// No OAuth credentials have been entered.
    /// User needs to provide Client ID and Secret.
    case unconfigured

    /// Has credentials but user hasn't completed OAuth sign-in.
    /// Ready to start the OAuth flow.
    case configured

    /// OAuth flow is in progress.
    /// Browser is open, waiting for authorization callback.
    case authenticating

    /// Valid access and refresh tokens are present.
    /// Can make API calls.
    case authenticated

    /// Access token has expired, but refresh token is valid.
    /// Will auto-refresh before next API call.
    case expired

    /// Refresh failed, tokens are invalid.
    /// User needs to re-authenticate.
    case invalid
}

// MARK: - State Predicates

public extension AuthState {
    /// Whether API calls can be attempted in this state.
    ///
    /// Returns `true` for `authenticated` and `expired` states.
    /// In the `expired` state, the system will attempt token refresh
    /// before making the API call.
    var canMakeApiCalls: Bool {
        switch self {
        case .authenticated, .expired:
            true
        case .unconfigured, .configured, .authenticating, .invalid:
            false
        }
    }

    /// Whether OAuth credentials have been configured.
    ///
    /// Returns `true` for all states except `unconfigured`.
    var hasCredentials: Bool {
        self != .unconfigured
    }

    /// Whether the user needs to take action to proceed.
    ///
    /// Returns `true` for states that require user intervention:
    /// - `unconfigured`: User must enter credentials
    /// - `configured`: User must complete OAuth sign-in
    /// - `invalid`: User must re-authenticate
    var requiresUserAction: Bool {
        switch self {
        case .unconfigured, .configured, .invalid:
            true
        case .authenticating, .authenticated, .expired:
            false
        }
    }
}

import Foundation

/// Errors that can occur during Calendar API operations and sync.
///
/// `CalendarError` provides typed errors for all Calendar API and sync
/// operations, enabling proper error handling and user feedback throughout
/// the application.
///
/// ## Error Categories
/// - Authentication: Issues with OAuth tokens
/// - API: Google Calendar API response errors
/// - Network: Connectivity and transport issues
/// - Sync: Synchronization state errors
///
/// ## Example Usage
/// ```swift
/// do {
///     let events = try await calendarClient.fetchEvents()
/// } catch let error as CalendarError {
///     switch error {
///     case .authenticationRequired:
///         // Prompt user to re-authenticate
///     case .rateLimited(let retryAfter):
///         // Wait and retry
///     case .syncTokenInvalid:
///         // Clear token and perform full sync
///     default:
///         // Handle other errors
///     }
/// }
/// ```
public enum CalendarError: Error, Equatable, Sendable {
    // MARK: - Authentication Errors

    /// User authentication is required.
    /// Occurs when the access token is missing or invalid and cannot be refreshed.
    case authenticationRequired

    /// Token refresh failed with the given reason.
    /// The user may need to re-authenticate.
    case tokenRefreshFailed(String)

    // MARK: - API Errors

    /// Rate limited by the Google Calendar API.
    /// - Parameter retryAfter: Optional number of seconds to wait before retrying.
    case rateLimited(retryAfter: Int?)

    /// The sync token is invalid and a full re-sync is required.
    /// This occurs when the API returns HTTP 410 Gone.
    case syncTokenInvalid

    /// The specified calendar was not found.
    /// - Parameter calendarId: The ID of the calendar that wasn't found.
    case calendarNotFound(calendarId: String)

    /// The specified event was not found.
    /// - Parameter eventId: The ID of the event that wasn't found.
    case eventNotFound(eventId: String)

    /// A server error occurred.
    /// - Parameter statusCode: The HTTP status code returned.
    /// - Parameter message: Optional error message from the server.
    case serverError(statusCode: Int, message: String?)

    /// The API request was invalid.
    /// - Parameter message: Description of what was invalid.
    case invalidRequest(String)

    // MARK: - Network Errors

    /// A network error occurred during the API call.
    /// - Parameter underlyingError: Description of the underlying network error.
    case networkError(String)

    /// The device appears to be offline.
    case offline

    /// The request timed out.
    case timeout

    // MARK: - Sync Errors

    /// Partial sync failure - some calendars succeeded but others failed.
    /// - Parameter failures: Dictionary mapping calendar IDs to their error descriptions.
    case partialSyncFailure(failures: [String: String])

    /// Calendar sync is already in progress.
    case syncInProgress

    // MARK: - Data Errors

    /// Failed to parse the API response.
    /// - Parameter message: Description of the parsing failure.
    case parsingError(String)

    /// Failed to persist data locally.
    /// - Parameter message: Description of the persistence failure.
    case persistenceError(String)
}

// MARK: - LocalizedError Conformance

extension CalendarError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Authentication required. Please sign in again."

        case let .tokenRefreshFailed(reason):
            "Failed to refresh authentication token: \(reason)"

        case let .rateLimited(retryAfter):
            retryAfter.map { "Rate limited by Google Calendar. Please wait \($0) seconds." }
                ?? "Rate limited by Google Calendar. Please try again later."

        case .syncTokenInvalid:
            "Sync token expired. A full re-sync will be performed."

        case let .calendarNotFound(calendarId):
            "Calendar not found: \(calendarId)"

        case let .eventNotFound(eventId):
            "Event not found: \(eventId)"

        case let .serverError(statusCode, message):
            message.map { "Server error (\(statusCode)): \($0)" }
                ?? "Server error (\(statusCode))"

        case let .invalidRequest(message):
            "Invalid request: \(message)"

        case let .networkError(underlyingError):
            "Network error: \(underlyingError)"

        case .offline:
            "You appear to be offline. Please check your internet connection."

        case .timeout:
            "The request timed out. Please try again."

        case let .partialSyncFailure(failures):
            "Failed to sync \(failures.count) calendar\(failures.count == 1 ? "" : "s")"

        case .syncInProgress:
            "Sync is already in progress."

        case let .parsingError(message):
            "Failed to parse response: \(message)"

        case let .persistenceError(message):
            "Failed to save data: \(message)"
        }
    }
}

// MARK: - Convenience Properties

public extension CalendarError {
    /// Whether this error indicates the user needs to take action (e.g., re-authenticate).
    var requiresUserAction: Bool {
        switch self {
        case .authenticationRequired, .tokenRefreshFailed:
            true
        default:
            false
        }
    }

    /// Whether this error is recoverable with a retry.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .networkError, .offline, .timeout, .serverError, .syncInProgress:
            true
        case .authenticationRequired, .tokenRefreshFailed, .syncTokenInvalid,
             .calendarNotFound, .eventNotFound, .invalidRequest,
             .partialSyncFailure, .parsingError, .persistenceError:
            false
        }
    }

    /// Whether this error indicates a sync token issue requiring full re-sync.
    var requiresFullResync: Bool {
        switch self {
        case .syncTokenInvalid:
            true
        default:
            false
        }
    }

    /// Suggested retry delay in seconds, if applicable.
    var suggestedRetryDelay: TimeInterval? {
        switch self {
        case let .rateLimited(retryAfter):
            retryAfter.map { TimeInterval($0) } ?? 60.0
        case .networkError, .timeout:
            5.0
        case .offline:
            30.0
        case let .serverError(statusCode, _) where statusCode >= 500:
            10.0
        case .syncInProgress:
            2.0
        default:
            nil
        }
    }
}

// MARK: - HTTP Status Code Factory

public extension CalendarError {
    /// Creates a CalendarError from an HTTP status code and optional message.
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - message: Optional error message from the response.
    ///   - calendarId: Optional calendar ID for context.
    /// - Returns: An appropriate CalendarError, or nil if the status code indicates success.
    static func from(
        httpStatusCode statusCode: Int,
        message: String? = nil,
        calendarId: String? = nil
    ) -> CalendarError? {
        switch statusCode {
        case 200 ..< 300:
            nil
        case 401:
            .authenticationRequired
        case 403:
            .rateLimited(retryAfter: nil)
        case 404:
            calendarId.map { .calendarNotFound(calendarId: $0) }
                ?? .invalidRequest(message ?? "Resource not found")
        case 410:
            .syncTokenInvalid
        case 429:
            .rateLimited(retryAfter: nil)
        case 400 ..< 500:
            .invalidRequest(message ?? "Bad request")
        case 500 ..< 600:
            .serverError(statusCode: statusCode, message: message)
        default:
            .serverError(statusCode: statusCode, message: message)
        }
    }
}

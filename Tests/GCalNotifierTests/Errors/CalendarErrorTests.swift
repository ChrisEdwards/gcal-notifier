import Testing
@testable import GCalNotifierCore

/// Tests for CalendarError enum and its properties.
@Suite("CalendarError Tests")
struct CalendarErrorTests {
    // MARK: - Equatable Tests

    @Test("Same error cases are equal")
    func equatableSameCases() {
        #expect(CalendarError.authenticationRequired == CalendarError.authenticationRequired)
        #expect(CalendarError.offline == CalendarError.offline)
        #expect(CalendarError.timeout == CalendarError.timeout)
        #expect(CalendarError.syncTokenInvalid == CalendarError.syncTokenInvalid)
        #expect(CalendarError.syncInProgress == CalendarError.syncInProgress)
    }

    @Test("Error cases with same associated values are equal")
    func equatableSameAssociatedValues() {
        #expect(
            CalendarError.rateLimited(retryAfter: 60)
                == CalendarError.rateLimited(retryAfter: 60)
        )
        #expect(
            CalendarError.calendarNotFound(calendarId: "abc")
                == CalendarError.calendarNotFound(calendarId: "abc")
        )
        #expect(
            CalendarError.serverError(statusCode: 500, message: "Error")
                == CalendarError.serverError(statusCode: 500, message: "Error")
        )
    }

    @Test("Error cases with different associated values are not equal")
    func equatableDifferentAssociatedValues() {
        #expect(
            CalendarError.rateLimited(retryAfter: 60)
                != CalendarError.rateLimited(retryAfter: 120)
        )
        #expect(
            CalendarError.calendarNotFound(calendarId: "abc")
                != CalendarError.calendarNotFound(calendarId: "xyz")
        )
        #expect(
            CalendarError.serverError(statusCode: 500, message: "Error")
                != CalendarError.serverError(statusCode: 502, message: "Error")
        )
    }

    @Test("Different error cases are not equal")
    func equatableDifferentCases() {
        #expect(CalendarError.authenticationRequired != CalendarError.offline)
        #expect(CalendarError.timeout != CalendarError.syncInProgress)
        #expect(CalendarError.syncTokenInvalid != CalendarError.authenticationRequired)
    }

    // MARK: - requiresUserAction Tests

    @Test("requiresUserAction returns true for authentication errors")
    func requiresUserActionAuthentication() {
        #expect(CalendarError.authenticationRequired.requiresUserAction == true)
        #expect(CalendarError.tokenRefreshFailed("expired").requiresUserAction == true)
    }

    @Test("requiresUserAction returns false for other errors")
    func requiresUserActionOther() {
        #expect(CalendarError.rateLimited(retryAfter: 60).requiresUserAction == false)
        #expect(CalendarError.networkError("timeout").requiresUserAction == false)
        #expect(CalendarError.offline.requiresUserAction == false)
        #expect(CalendarError.syncTokenInvalid.requiresUserAction == false)
        #expect(CalendarError.serverError(statusCode: 500, message: nil).requiresUserAction == false)
    }

    // MARK: - isRetryable Tests

    @Test("isRetryable returns true for transient errors")
    func isRetryableTransient() {
        #expect(CalendarError.rateLimited(retryAfter: 60).isRetryable == true)
        #expect(CalendarError.networkError("connection reset").isRetryable == true)
        #expect(CalendarError.offline.isRetryable == true)
        #expect(CalendarError.timeout.isRetryable == true)
        #expect(CalendarError.serverError(statusCode: 503, message: nil).isRetryable == true)
        #expect(CalendarError.syncInProgress.isRetryable == true)
    }

    @Test("isRetryable returns false for non-transient errors")
    func isRetryableNonTransient() {
        #expect(CalendarError.authenticationRequired.isRetryable == false)
        #expect(CalendarError.tokenRefreshFailed("invalid").isRetryable == false)
        #expect(CalendarError.syncTokenInvalid.isRetryable == false)
        #expect(CalendarError.calendarNotFound(calendarId: "abc").isRetryable == false)
        #expect(CalendarError.eventNotFound(eventId: "123").isRetryable == false)
        #expect(CalendarError.invalidRequest("bad format").isRetryable == false)
        #expect(CalendarError.parsingError("invalid JSON").isRetryable == false)
        #expect(CalendarError.persistenceError("disk full").isRetryable == false)
        #expect(CalendarError.partialSyncFailure(failures: ["cal1": "error"]).isRetryable == false)
    }

    // MARK: - requiresFullResync Tests

    @Test("requiresFullResync returns true for syncTokenInvalid")
    func requiresFullResyncSyncToken() {
        #expect(CalendarError.syncTokenInvalid.requiresFullResync == true)
    }

    @Test("requiresFullResync returns false for other errors")
    func requiresFullResyncOther() {
        #expect(CalendarError.authenticationRequired.requiresFullResync == false)
        #expect(CalendarError.rateLimited(retryAfter: nil).requiresFullResync == false)
        #expect(CalendarError.networkError("error").requiresFullResync == false)
        #expect(CalendarError.serverError(statusCode: 500, message: nil).requiresFullResync == false)
    }

    // MARK: - suggestedRetryDelay Tests

    @Test("suggestedRetryDelay returns retryAfter value for rateLimited")
    func suggestedRetryDelayRateLimited() {
        #expect(CalendarError.rateLimited(retryAfter: 120).suggestedRetryDelay == 120.0)
    }

    @Test("suggestedRetryDelay returns default for rateLimited without retryAfter")
    func suggestedRetryDelayRateLimitedDefault() {
        #expect(CalendarError.rateLimited(retryAfter: nil).suggestedRetryDelay == 60.0)
    }

    @Test("suggestedRetryDelay returns appropriate values for network errors")
    func suggestedRetryDelayNetwork() {
        #expect(CalendarError.networkError("connection reset").suggestedRetryDelay == 5.0)
        #expect(CalendarError.timeout.suggestedRetryDelay == 5.0)
        #expect(CalendarError.offline.suggestedRetryDelay == 30.0)
    }

    @Test("suggestedRetryDelay returns value for server errors")
    func suggestedRetryDelayServerError() {
        #expect(CalendarError.serverError(statusCode: 500, message: nil).suggestedRetryDelay == 10.0)
        #expect(CalendarError.serverError(statusCode: 503, message: nil).suggestedRetryDelay == 10.0)
    }

    @Test("suggestedRetryDelay returns nil for non-retryable errors")
    func suggestedRetryDelayNonRetryable() {
        #expect(CalendarError.authenticationRequired.suggestedRetryDelay == nil)
        #expect(CalendarError.syncTokenInvalid.suggestedRetryDelay == nil)
        #expect(CalendarError.calendarNotFound(calendarId: "abc").suggestedRetryDelay == nil)
        #expect(CalendarError.invalidRequest("bad").suggestedRetryDelay == nil)
    }

    @Test("suggestedRetryDelay returns value for syncInProgress")
    func suggestedRetryDelaySyncInProgress() {
        #expect(CalendarError.syncInProgress.suggestedRetryDelay == 2.0)
    }

    // MARK: - HTTP Status Code Factory Tests

    @Test("from(httpStatusCode:) returns nil for success codes")
    func fromHttpStatusCodeSuccess() {
        #expect(CalendarError.from(httpStatusCode: 200) == nil)
        #expect(CalendarError.from(httpStatusCode: 201) == nil)
        #expect(CalendarError.from(httpStatusCode: 204) == nil)
    }

    @Test("from(httpStatusCode:) returns authenticationRequired for 401")
    func fromHttpStatusCode401() {
        #expect(CalendarError.from(httpStatusCode: 401) == .authenticationRequired)
    }

    @Test("from(httpStatusCode:) returns invalidRequest for 403")
    func fromHttpStatusCode403() {
        #expect(CalendarError.from(httpStatusCode: 403) == .invalidRequest("Forbidden"))
    }

    @Test("from(httpStatusCode:) returns calendarNotFound for 404 with calendarId")
    func fromHttpStatusCode404WithCalendar() {
        let error = CalendarError.from(httpStatusCode: 404, calendarId: "primary")
        #expect(error == .calendarNotFound(calendarId: "primary"))
    }

    @Test("from(httpStatusCode:) returns invalidRequest for 404 without calendarId")
    func fromHttpStatusCode404WithoutCalendar() {
        let error = CalendarError.from(httpStatusCode: 404)
        #expect(error == .invalidRequest("Resource not found"))
    }

    @Test("from(httpStatusCode:) returns syncTokenInvalid for 410")
    func fromHttpStatusCode410() {
        #expect(CalendarError.from(httpStatusCode: 410) == .syncTokenInvalid)
    }

    @Test("from(httpStatusCode:) returns rateLimited for 429")
    func fromHttpStatusCode429() {
        #expect(CalendarError.from(httpStatusCode: 429) == .rateLimited(retryAfter: nil))
    }

    @Test("from(httpStatusCode:) returns serverError for 5xx codes")
    func fromHttpStatusCode5xx() {
        #expect(
            CalendarError.from(httpStatusCode: 500, message: "Internal error")
                == .serverError(statusCode: 500, message: "Internal error")
        )
        #expect(
            CalendarError.from(httpStatusCode: 503)
                == .serverError(statusCode: 503, message: nil)
        )
    }

    @Test("from(httpStatusCode:) returns invalidRequest for other 4xx codes")
    func fromHttpStatusCode4xx() {
        #expect(
            CalendarError.from(httpStatusCode: 400, message: "Bad request")
                == .invalidRequest("Bad request")
        )
        #expect(
            CalendarError.from(httpStatusCode: 422)
                == .invalidRequest("Bad request")
        )
    }

    // MARK: - LocalizedError Tests

    @Test("errorDescription returns appropriate message for all cases")
    func errorDescriptionAllCases() {
        // Authentication errors
        #expect(CalendarError.authenticationRequired.errorDescription != nil)
        #expect(CalendarError.tokenRefreshFailed("expired").errorDescription?.contains("expired") == true)

        // API errors
        #expect(CalendarError.rateLimited(retryAfter: 60).errorDescription?.contains("60") == true)
        #expect(CalendarError.rateLimited(retryAfter: nil).errorDescription?.contains("later") == true)
        #expect(CalendarError.syncTokenInvalid.errorDescription?.contains("re-sync") == true)
        #expect(
            CalendarError.calendarNotFound(calendarId: "abc").errorDescription?.contains("abc")
                == true
        )
        #expect(CalendarError.eventNotFound(eventId: "123").errorDescription?.contains("123") == true)
        #expect(
            CalendarError.serverError(statusCode: 500, message: "Oops").errorDescription?
                .contains("500") == true
        )
        #expect(CalendarError.invalidRequest("bad data").errorDescription?.contains("bad data") == true)

        // Network errors
        #expect(
            CalendarError.networkError("connection reset").errorDescription?
                .contains("connection reset") == true
        )
        #expect(CalendarError.offline.errorDescription?.contains("offline") == true)
        #expect(CalendarError.timeout.errorDescription?.contains("timed out") == true)

        // Sync errors
        let partialError = CalendarError.partialSyncFailure(failures: ["cal1": "err", "cal2": "err"])
        #expect(partialError.errorDescription?.contains("2") == true)
        #expect(CalendarError.syncInProgress.errorDescription?.contains("in progress") == true)

        // Data errors
        #expect(CalendarError.parsingError("invalid").errorDescription?.contains("parse") == true)
        #expect(CalendarError.persistenceError("disk").errorDescription?.contains("save") == true)
    }

    @Test("errorDescription handles singular vs plural for partialSyncFailure")
    func errorDescriptionPartialSyncPluralization() {
        let singleFailure = CalendarError.partialSyncFailure(failures: ["cal1": "error"])
        #expect(singleFailure.errorDescription?.contains("1 calendar") == true)

        let multipleFailures = CalendarError.partialSyncFailure(failures: [
            "cal1": "error",
            "cal2": "error",
            "cal3": "error",
        ])
        #expect(multipleFailures.errorDescription?.contains("3 calendars") == true)
    }

    // MARK: - Sendable Tests

    @Test("CalendarError is Sendable")
    func isSendable() async {
        let error = CalendarError.networkError("test")
        await Task.detached {
            // This compiles because CalendarError is Sendable
            _ = error.errorDescription
        }.value
    }
}

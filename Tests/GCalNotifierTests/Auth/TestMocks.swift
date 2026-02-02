import Foundation
@testable import GCalNotifierCore

// MARK: - Mock HTTP Client

actor MockHTTPClient: HTTPClient {
    var responses: [(Data, URLResponse)] = []
    var requestsReceived: [URLRequest] = []
    var errorToThrow: Error?

    func setErrorToThrow(_ error: Error?) {
        self.errorToThrow = error
    }

    func queueResponse(data: Data, statusCode: Int) {
        guard let url = URL(string: "https://example.com"),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            return
        }
        self.responses.append((data, response))
    }

    func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.requestsReceived.append(request)

        if let error = errorToThrow {
            throw error
        }

        guard !self.responses.isEmpty else {
            throw OAuthError.networkError("No mock response queued")
        }

        return self.responses.removeFirst()
    }
}

// MARK: - Mock Browser Opener

final class MockBrowserOpener: BrowserOpener, @unchecked Sendable {
    private let lock = NSLock()
    private var _openedURLs: [URL] = []
    var onOpen: ((URL) -> Void)?

    var openedURLs: [URL] {
        self.lock.withLock { self._openedURLs }
    }

    var lastStateParameter: String? {
        guard let url = openedURLs.last,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let stateItem = components.queryItems?.first(where: { $0.name == "state" })
        else {
            return nil
        }
        return stateItem.value
    }

    func open(_ url: URL) {
        self.lock.withLock {
            self._openedURLs.append(url)
        }
        self.onOpen?(url)
    }
}

// MARK: - Mock Callback Server

actor MockCallbackServer: CallbackServer {
    var isStarted = false
    var isStopped = false
    var callbackCode: String?
    var callbackError: String?
    var capturedState: String?
    var errorToThrow: Error?

    func start() async throws {
        self.isStarted = true
    }

    func stop() async {
        self.isStopped = true
    }

    func waitForCallback(timeout _: TimeInterval) async throws -> OAuthCallbackResult {
        if let error = errorToThrow {
            throw error
        }

        // Give the browser opener callback a moment to capture the state
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Return the captured state so the provider's state validation passes
        return OAuthCallbackResult(
            code: self.callbackCode,
            state: self.capturedState,
            error: self.callbackError
        )
    }

    func setCallbackResult(_ result: OAuthCallbackResult) {
        self.callbackCode = result.code
        self.callbackError = result.error
    }

    func configureForError(_ error: String) {
        self.callbackCode = nil
        self.callbackError = error
    }

    func configureForSuccess(code: String) {
        self.callbackCode = code
        self.callbackError = nil
    }

    func captureState(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let stateItem = components.queryItems?.first(where: { $0.name == "state" })
        else { return }
        self.capturedState = stateItem.value
    }
}

// MARK: - Mock Callback Server Factory

final class MockCallbackServerFactory: CallbackServerFactory, @unchecked Sendable {
    let mockServer: MockCallbackServer

    init(mockServer: MockCallbackServer) {
        self.mockServer = mockServer
    }

    func createServer() -> CallbackServer {
        self.mockServer
    }
}

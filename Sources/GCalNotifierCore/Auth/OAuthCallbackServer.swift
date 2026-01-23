import Foundation
import OSLog

// MARK: - Callback Server Protocols

/// Factory for creating callback servers.
public protocol CallbackServerFactory: Sendable {
    func createServer() -> CallbackServer
}

/// Result from OAuth callback.
public struct OAuthCallbackResult: Sendable {
    public let code: String?
    public let state: String?
    public let error: String?

    public init(code: String?, state: String?, error: String?) {
        self.code = code
        self.state = state
        self.error = error
    }
}

/// Protocol for localhost callback server.
public protocol CallbackServer: Sendable {
    func start() async throws
    func stop() async
    func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackResult
}

// MARK: - Factory

/// Factory that creates localhost HTTP callback servers.
public final class LocalhostCallbackServerFactory: CallbackServerFactory, @unchecked Sendable {
    private let port: UInt16

    public init(port: UInt16) {
        self.port = port
    }

    public func createServer() -> CallbackServer {
        LocalhostCallbackServer(port: self.port)
    }
}

// MARK: - Localhost Callback Server

/// Localhost HTTP server for receiving OAuth callbacks.
public actor LocalhostCallbackServer: CallbackServer {
    private let port: UInt16
    private var listener: Task<Void, Error>?
    private var callbackContinuation: CheckedContinuation<OAuthCallbackResult, Error>?
    private var serverSocket: Int32 = -1

    public init(port: UInt16) {
        self.port = port
    }

    public func start() async throws {
        try self.createAndBindSocket()
        self.startListening()
    }

    public func stop() async {
        self.listener?.cancel()
        self.listener = nil

        if self.serverSocket >= 0 {
            close(self.serverSocket)
            self.serverSocket = -1
        }

        Logger.auth.debug("Callback server stopped")
    }

    public func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackResult {
        try await withCheckedThrowingContinuation { continuation in
            self.callbackContinuation = continuation

            // Set up timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = await self.callbackContinuation {
                    await self.clearContinuation()
                    cont.resume(throwing: OAuthError.authenticationFailed("Callback timeout"))
                }
            }
        }
    }

    // MARK: - Private Methods

    private func createAndBindSocket() throws {
        // Create socket
        self.serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard self.serverSocket >= 0 else {
            throw OAuthError.authenticationFailed("Failed to create socket")
        }

        // Allow address reuse
        var opt: Int32 = 1
        setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        // Bind to port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = self.port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(self.serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            close(self.serverSocket)
            throw OAuthError.authenticationFailed("Failed to bind to port \(self.port)")
        }

        // Listen
        guard listen(self.serverSocket, 1) >= 0 else {
            close(self.serverSocket)
            throw OAuthError.authenticationFailed("Failed to listen on port \(self.port)")
        }

        Logger.auth.debug("Callback server started on port \(self.port)")
    }

    private func startListening() {
        let socket = self.serverSocket
        self.listener = Task.detached { [weak self] in
            while !Task.isCancelled {
                let clientSocket = accept(socket, nil, nil)
                guard clientSocket >= 0 else {
                    if Task.isCancelled { break }
                    continue
                }
                await self?.handleConnection(clientSocket)
            }
        }
    }

    private func clearContinuation() {
        self.callbackContinuation = nil
    }

    private func handleConnection(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        guard let requestString = self.readRequest(from: clientSocket) else { return }
        guard let callbackResult = self.parseCallbackRequest(requestString) else {
            self.sendNotFoundResponse(to: clientSocket)
            return
        }

        self.sendSuccessResponse(to: clientSocket)
        self.resumeWithResult(callbackResult)
    }

    private func readRequest(from clientSocket: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        guard bytesRead > 0 else { return nil }
        return String(bytes: buffer.prefix(bytesRead), encoding: .utf8)
    }

    private func parseCallbackRequest(_ requestString: String) -> OAuthCallbackResult? {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        let path = parts[1]
        guard let url = URL(string: "http://localhost\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.path == "/oauth/callback"
        else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        return OAuthCallbackResult(
            code: queryItems.first { $0.name == "code" }?.value,
            state: queryItems.first { $0.name == "state" }?.value,
            error: queryItems.first { $0.name == "error" }?.value
        )
    }

    private func sendNotFoundResponse(to clientSocket: Int32) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        _ = response.withCString { write(clientSocket, $0, strlen($0)) }
    }

    private func sendSuccessResponse(to clientSocket: Int32) {
        let htmlBody = """
        <!DOCTYPE html>
        <html>
        <head><title>Authorization Complete</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 50px;">
            <h1>Authorization Complete</h1>
            <p>You can close this window and return to gcal-notifier.</p>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html\r
        Content-Length: \(htmlBody.utf8.count)\r
        Connection: close\r
        \r
        \(htmlBody)
        """
        _ = response.withCString { write(clientSocket, $0, strlen($0)) }
    }

    private func resumeWithResult(_ result: OAuthCallbackResult) {
        if let continuation = callbackContinuation {
            self.callbackContinuation = nil
            continuation.resume(returning: result)
        }
    }
}

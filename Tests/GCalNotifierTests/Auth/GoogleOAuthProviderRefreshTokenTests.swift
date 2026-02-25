import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("GoogleOAuthProvider Refresh Token Tests", .serialized)
struct GoogleOAuthProviderRefreshTokenTests {
    @Test("Authenticate preserves refresh token when response omits it")
    func authenticatePreservesRefreshTokenWhenMissing() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)
        let existingTokens = OAuthTokens(
            accessToken: "old-access",
            refreshToken: "existing-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await ctx.keychainManager.saveTokens(existingTokens)

        try await ctx.provider.loadStoredCredentials()
        await ctx.callbackServer.configureForSuccess(code: "auth-code")
        await ctx.httpClient.queueResponse(
            data: makeTokenResponseJSON(accessToken: "new-access", refreshToken: nil),
            statusCode: 200
        )

        try await ctx.provider.authenticate()

        let storedData = try await ctx.keychainManager.loadOAuthData()
        #expect(storedData?.tokens?.accessToken == "new-access")
        #expect(storedData?.tokens?.refreshToken == "existing-refresh")
    }

    @Test("Authenticate fails when refresh token missing and none stored")
    func authenticateFailsWithoutRefreshToken() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.configure(clientId: "test-client-id", clientSecret: "test-secret")
        await ctx.callbackServer.configureForSuccess(code: "auth-code")
        await ctx.httpClient.queueResponse(
            data: makeTokenResponseJSON(accessToken: "new-access", refreshToken: nil),
            statusCode: 200
        )

        await #expect(throws: OAuthError.authenticationFailed("No refresh token received")) {
            try await ctx.provider.authenticate()
        }

        let state = await ctx.provider.state
        #expect(state == .configured)
    }
}

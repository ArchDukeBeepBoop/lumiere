import Foundation

/// The first run against a brand-new server: it has no account yet, so the
/// first person to arrive makes one. See the server's `/Lumiere/Setup`.
public extension JellyfinSignIn {
    private struct SetupState: Decodable, Sendable {
        let needsAccount: Bool
        enum CodingKeys: String, CodingKey { case needsAccount = "NeedsAccount" }
    }

    /// Whether the server is waiting for its first account. False for any
    /// server that does not know the question.
    static func needsFirstAccount(serverURL: URL) async -> Bool {
        var request = URLRequest(url: serverURL.appendingPathComponent("Lumiere/Setup"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try? await JellyfinClient.execute(request, on: urlSession),
              let state = try? JellyfinClient.decode(SetupState.self, from: data, context: "setup")
        else { return false }
        return state.needsAccount
    }

    /// Makes the first account and signs in with it.
    static func createFirstAccount(
        serverURL: URL, serverInfo: PublicSystemInfo, username: String, password: String
    ) async throws -> (JellyfinSession, String) {
        let deviceId = DeviceIdentity.deviceId
        var request = URLRequest(url: serverURL.appendingPathComponent("Lumiere/Setup/Account"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Password": password])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let auth = JellyfinClient.authorizationValue(deviceId: deviceId, token: nil)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")
        let data = try await JellyfinClient.execute(request, on: urlSession)
        let result = try JellyfinClient.decode(AuthenticationResult.self, from: data, context: "first account")
        let session = JellyfinSession(
            serverURL: serverURL,
            serverName: serverInfo.serverName ?? serverURL.host ?? "Lumiere",
            serverId: result.serverId, userId: result.user.id,
            userName: result.user.name, deviceId: deviceId
        )
        return (session, result.accessToken)
    }
}

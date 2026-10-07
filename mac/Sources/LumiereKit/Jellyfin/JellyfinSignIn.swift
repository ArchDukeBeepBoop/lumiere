import Foundation

/// The sign-in flow. Standalone rather than part of `JellyfinClient` because it
/// runs before a client can exist — there is no session or token yet.
public enum JellyfinSignIn {

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Probing candidate URLs must fail quickly: a wrong guess should cost a
        // couple of seconds, not the default 60.
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - Reaching a server

    /// Tries each candidate URL from `ServerURLNormalizer` in order and returns the
    /// first that answers `/System/Info/Public` with something Jellyfin-shaped.
    public static func resolve(address input: String) async throws -> (URL, PublicSystemInfo) {
        let candidates = ServerURLNormalizer.candidates(from: input)
        guard !candidates.isEmpty else {
            throw JellyfinError.invalidServerURL(input)
        }

        var lastFailure = "No response."
        for candidate in candidates {
            do {
                let info = try await publicInfo(for: candidate)
                // A server that answers but has no id is a reverse proxy or a
                // different product entirely.
                guard info.id != nil else {
                    lastFailure = "That address answered, but it isn’t a Lumiere server."
                    continue
                }
                return (candidate, info)
            } catch let error as JellyfinError {
                lastFailure = error.errorDescription ?? lastFailure
            } catch {
                lastFailure = error.localizedDescription
            }
        }
        throw JellyfinError.notReachable(underlying: lastFailure)
    }

    public static func publicInfo(for serverURL: URL) async throws -> PublicSystemInfo {
        var request = URLRequest(url: serverURL.appendingPathComponent("System/Info/Public"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await JellyfinClient.execute(request, on: urlSession)
        return try JellyfinClient.decode(PublicSystemInfo.self, from: data, context: "system info")
    }

    // MARK: - Password sign-in

    public static func authenticate(
        serverURL: URL,
        serverInfo: PublicSystemInfo,
        username: String,
        password: String
    ) async throws -> (JellyfinSession, String) {
        let deviceId = DeviceIdentity.deviceId
        let body = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password,
        ])

        var request = URLRequest(url: serverURL.appendingPathComponent("Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let auth = JellyfinClient.authorizationValue(deviceId: deviceId, token: nil)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")

        let data = try await JellyfinClient.execute(request, on: urlSession)
        let result = try JellyfinClient.decode(
            AuthenticationResult.self, from: data, context: "authentication"
        )

        let session = JellyfinSession(
            serverURL: serverURL,
            serverName: serverInfo.serverName ?? serverURL.host ?? "Lumiere",
            serverId: result.serverId,
            userId: result.user.id,
            userName: result.user.name,
            deviceId: deviceId
        )
        return (session, result.accessToken)
    }

    // MARK: - Quick Connect

    public static func quickConnectEnabled(serverURL: URL) async -> Bool {
        var request = URLRequest(url: serverURL.appendingPathComponent("QuickConnect/Enabled"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try? await JellyfinClient.execute(request, on: urlSession),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    /// Starts a Quick Connect attempt and returns the code to show the user.
    ///
    /// Jellyfin moved this endpoint from GET to POST around 10.9, so both are
    /// tried — the server version is not knowable in advance without another call.
    public static func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectResult {
        let url = serverURL.appendingPathComponent("QuickConnect/Initiate")
        let auth = JellyfinClient.authorizationValue(deviceId: DeviceIdentity.deviceId, token: nil)

        for method in ["POST", "GET"] {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(auth, forHTTPHeaderField: "Authorization")
            request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")

            guard let data = try? await JellyfinClient.execute(request, on: urlSession) else {
                continue
            }
            if let result = try? JellyfinClient.decode(
                QuickConnectResult.self, from: data, context: "quick connect"
            ) {
                return result
            }
        }
        throw JellyfinError.quickConnectUnavailable
    }

    /// Polls until the code is approved on another device, or the deadline passes.
    /// Jellyfin expires codes after a few minutes; five is a safe ceiling.
    public static func awaitQuickConnectApproval(
        serverURL: URL,
        secret: String,
        timeout: Duration = .seconds(300),
        pollInterval: Duration = .seconds(3)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()

            var components = URLComponents(
                url: serverURL.appendingPathComponent("QuickConnect/Connect"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "secret", value: secret)]
            guard let url = components?.url else {
                throw JellyfinError.quickConnectUnavailable
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let data = try? await JellyfinClient.execute(request, on: urlSession),
               let result = try? JellyfinClient.decode(
                   QuickConnectResult.self, from: data, context: "quick connect"
               ),
               result.authenticated == true {
                return
            }

            try await Task.sleep(for: pollInterval)
        }
        throw JellyfinError.quickConnectNotApproved
    }

    public static func authenticateWithQuickConnect(
        serverURL: URL,
        serverInfo: PublicSystemInfo,
        secret: String
    ) async throws -> (JellyfinSession, String) {
        let deviceId = DeviceIdentity.deviceId
        let body = try JSONSerialization.data(withJSONObject: ["Secret": secret])

        var request = URLRequest(
            url: serverURL.appendingPathComponent("Users/AuthenticateWithQuickConnect")
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let auth = JellyfinClient.authorizationValue(deviceId: deviceId, token: nil)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")

        let data = try await JellyfinClient.execute(request, on: urlSession)
        let result = try JellyfinClient.decode(
            AuthenticationResult.self, from: data, context: "authentication"
        )

        let session = JellyfinSession(
            serverURL: serverURL,
            serverName: serverInfo.serverName ?? serverURL.host ?? "Lumiere",
            serverId: result.serverId,
            userId: result.user.id,
            userName: result.user.name,
            deviceId: deviceId
        )
        return (session, result.accessToken)
    }

    // MARK: - Public users

    /// Servers that allow it publish their user list, which lets the sign-in screen
    /// show avatars instead of a bare username field.
    public static func publicUsers(serverURL: URL) async -> [JellyfinUser] {
        var request = URLRequest(url: serverURL.appendingPathComponent("Users/Public"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try? await JellyfinClient.execute(request, on: urlSession),
              let users = try? JellyfinClient.decode(
                  [JellyfinUser].self, from: data, context: "public users"
              ) else {
            return []
        }
        return users
    }
}

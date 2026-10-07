import Foundation

/// Everything needed to talk to a server as a signed-in user. The token half is
/// stored by `TokenStore`; the rest is safe to keep in `UserDefaults`.
public struct JellyfinSession: Sendable, Equatable, Codable {
    public let serverURL: URL
    public let serverName: String
    public let serverId: String
    public let userId: String
    public let userName: String
    public let deviceId: String

    public init(
        serverURL: URL,
        serverName: String,
        serverId: String,
        userId: String,
        userName: String,
        deviceId: String
    ) {
        self.serverURL = serverURL
        self.serverName = serverName
        self.serverId = serverId
        self.userId = userId
        self.userName = userName
        self.deviceId = deviceId
    }
}

public struct AuthenticationResult: Codable, Sendable {
    public let user: JellyfinUser
    public let accessToken: String
    public let serverId: String

    public enum CodingKeys: String, CodingKey {
        case user = "User", accessToken = "AccessToken", serverId = "ServerId"
    }
}

public struct JellyfinUser: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let primaryImageTag: String?
    public let hasPassword: Bool?

    public enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name"
        case primaryImageTag = "PrimaryImageTag", hasPassword = "HasPassword"
    }
}

public struct PublicSystemInfo: Codable, Sendable {
    public let serverName: String?
    public let version: String?
    public let id: String?
    public let localAddress: String?
    public let startupWizardCompleted: Bool?
    /// Which of Lumiere's own routes the server has; nil on a Jellyfin server.
    /// See `ServerCompatibility`.
    public let lumiereApi: Int?

    public enum CodingKeys: String, CodingKey {
        case serverName = "ServerName", version = "Version", id = "Id"
        case localAddress = "LocalAddress", startupWizardCompleted = "StartupWizardCompleted"
        case lumiereApi = "LumiereApi"
    }
}

/// Quick Connect lets you approve this Mac from a device already signed in,
/// instead of typing a password. It is the nicer path and the one Lumiere offers
/// first when the server has it enabled.
public struct QuickConnectResult: Codable, Sendable {
    public let secret: String
    public let code: String
    public let authenticated: Bool?

    public enum CodingKeys: String, CodingKey {
        case secret = "Secret", code = "Code", authenticated = "Authenticated"
    }
}

public enum JellyfinError: LocalizedError, Sendable {
    case invalidServerURL(String)
    case notReachable(underlying: String)
    case unauthorized
    case quickConnectUnavailable
    case quickConnectNotApproved
    case httpError(status: Int, body: String?)
    case decodingFailed(context: String, underlying: String)
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL(let raw):
            return "\"\(raw)\" is not a valid server address."
        case .notReachable(let underlying):
            return "Couldn't reach the server. \(underlying)"
        case .unauthorized:
            return "Your username or password wasn't accepted."
        case .quickConnectUnavailable:
            return "This server has Quick Connect turned off. Sign in with a password instead."
        case .quickConnectNotApproved:
            return "The code wasn't approved in time."
        case .httpError(let status, let body):
            if let body, !body.isEmpty {
                return "Server returned \(status): \(body.prefix(200))"
            }
            return "Server returned \(status)."
        case .decodingFailed(let context, let underlying):
            return "Couldn't read the \(context) response. \(underlying)"
        case .notSignedIn:
            return "You're not signed in to a server."
        }
    }
}

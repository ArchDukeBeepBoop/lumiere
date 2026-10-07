import Foundation

/// One page of the server's change feed. See the server's store.ChangesSince.
public struct ChangePage: Decodable, Sendable {
    public let next: Int64
    public let reset: Bool
    public let changed: [String]
    public let removed: [String]
    public let more: Bool

    enum CodingKeys: String, CodingKey {
        case next = "Next", reset = "Reset", changed = "Changed", removed = "Removed", more = "More"
    }
}

public extension JellyfinClient {
    /// What changed after `since`. With `wait`, the server holds the request
    /// until something changes or the wait is up — inside the 60-second request
    /// timeout. Throws on a server with no feed (Jellyfin answers 404).
    func changes(since: Int64, wait: Int = 0) async throws -> ChangePage {
        var query = [URLQueryItem(name: "since", value: String(since)),
                     URLQueryItem(name: "limit", value: "600")]
        if wait > 0 { query.append(URLQueryItem(name: "wait", value: String(min(wait, 45)))) }
        return try await send(ChangePage.self, path: "Lumiere/Changes", query: query)
    }
}

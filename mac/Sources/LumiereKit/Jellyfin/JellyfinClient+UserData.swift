import Foundation

public extension JellyfinClient {
    /// The server's watch state for a handful of items, and nothing else.
    ///
    /// For reading back what a watch-state write actually did. The server is
    /// the one that knows how many episodes under a season are unwatched — it
    /// did the cascade — so after a tick the app asks it rather than trusting
    /// its own arithmetic. No artwork and no fields: the payload is the
    /// `UserData` block and the id it belongs to.
    func userData(ids: [String]) async throws -> [JellyfinItem] {
        guard !ids.isEmpty else { return [] }
        let query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "Ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "EnableImageTypes", value: ""),
            URLQueryItem(name: "Limit", value: String(ids.count)),
        ]
        return try await send(ItemsResponse.self, path: "Items", query: query).items
    }
}

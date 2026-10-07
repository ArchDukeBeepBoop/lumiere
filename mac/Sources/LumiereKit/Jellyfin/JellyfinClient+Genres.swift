import Foundation

public extension JellyfinClient {

    /// The genres present in a music library.
    ///
    /// Its own endpoint, like `/Artists`, and for the same reason: a genre is a
    /// value on a track rather than a row filed under the library, so `/Items`
    /// has nothing to return. What comes back is a list of names — filtering by
    /// one means passing the name to `items(genres:)`, not an id.
    func musicGenres(
        parentId: String, startIndex: Int = 0, limit: Int = 500
    ) async throws -> ItemsResponse {
        try await send(
            ItemsResponse.self,
            path: "MusicGenres",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "ParentId", value: parentId),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
            ]
        )
    }
}

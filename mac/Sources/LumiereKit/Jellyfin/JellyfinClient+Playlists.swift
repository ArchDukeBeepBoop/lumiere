import Foundation

private struct PlaylistCreationResult: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

/// Playlists, server-side.
///
/// Separate from collections despite the surface similarity, because they answer
/// different questions: a collection is "these things belong together", a playlist
/// is "play these, in this order". Jellyfin models them as different endpoints with
/// different semantics — a playlist has a media type and preserves order — so they
/// stay apart here rather than being forced through one abstraction.
public extension JellyfinClient {

    /// Creates a playlist and returns its id.
    ///
    /// `mediaType` matters: a playlist created without one accepts anything, which
    /// makes it invisible to the Music section it was created from.
    func createPlaylist(
        name: String,
        itemIds: [String] = [],
        mediaType: String = "Audio"
    ) async throws -> String {
        var query = [
            URLQueryItem(name: "Name", value: name),
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "mediaType", value: mediaType),
        ]
        if !itemIds.isEmpty {
            query.append(URLQueryItem(name: "Ids", value: itemIds.joined(separator: ",")))
        }
        let result = try await send(
            PlaylistCreationResult.self, path: "Playlists", method: "POST", query: query
        )
        return result.id
    }

    func addToPlaylist(playlistId: String, itemIds: [String]) async throws {
        guard !itemIds.isEmpty else { return }
        try await sendVoid(
            path: "Playlists/\(playlistId)/Items",
            method: "POST",
            query: [
                URLQueryItem(name: "Ids", value: itemIds.joined(separator: ",")),
                URLQueryItem(name: "userId", value: session.userId),
            ]
        )
    }

    /// Removes by *entry* id, not item id.
    ///
    /// A playlist can hold the same track twice, so Jellyfin identifies each row by
    /// its own PlaylistItemId. Passing the track's id would be ambiguous, and the
    /// server would remove whichever copy it found first.
    func removeFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        guard !entryIds.isEmpty else { return }
        try await sendVoid(
            path: "Playlists/\(playlistId)/Items",
            method: "DELETE",
            query: [URLQueryItem(name: "EntryIds", value: entryIds.joined(separator: ","))]
        )
    }

    /// A playlist's rows, in playlist order, each carrying its own `PlaylistItemId`.
    ///
    /// `/Playlists/{id}/Items` rather than the generic `/Items?ParentId=`: only this
    /// endpoint returns the entry ids, and without one a row cannot be removed —
    /// which is the whole reason an edit mode needs a fetch of its own.
    func playlistItems(
        playlistId: String, startIndex: Int = 0, limit: Int = 500
    ) async throws -> ItemsResponse {
        try await send(
            ItemsResponse.self,
            path: "Playlists/\(playlistId)/Items",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
            ]
        )
    }

    /// Every playlist the user has, for pickers.
    func playlists(mediaType: String? = nil) async throws -> [JellyfinItem] {
        var query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "Fields", value: FieldSet.list.value),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
        ]
        if let mediaType {
            query.append(URLQueryItem(name: "MediaTypes", value: mediaType))
        }
        let response = try await send(ItemsResponse.self, path: "Items", query: query)
        return response.items
    }
}

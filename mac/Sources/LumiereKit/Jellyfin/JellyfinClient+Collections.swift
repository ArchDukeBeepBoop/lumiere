import Foundation

private struct CollectionCreationResult: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

/// Collections (Jellyfin calls them BoxSets) live on the server, not in this app.
/// Lumiere never invents its own grouping mechanism for the same reason metadata
/// stays server-side: a collection built here has to show up identically in every
/// other Jellyfin client, and only the server's own BoxSet objects do that. A
/// BoxSet's members can already span any library or type — movies, series,
/// episodes, mixed freely — which is exactly what lets one collection hold both
/// an anime's TV run and its movies.
public extension JellyfinClient {

    /// Creates a collection with an initial set of members and returns its id.
    /// `itemIds` may be empty — an empty collection is a valid starting point for
    /// one built up afterward through `addToCollection`.
    func createCollection(
        name: String, itemIds: [String] = [], tmdbCollectionId: String? = nil
    ) async throws -> String {
        var query = [URLQueryItem(name: "Name", value: name)]
        // Lumiere's server remembers the film series; Jellyfin ignores it.
        if let tmdbCollectionId {
            query.append(URLQueryItem(name: "TmdbCollectionId", value: tmdbCollectionId))
        }
        if !itemIds.isEmpty {
            query.append(URLQueryItem(name: "Ids", value: itemIds.joined(separator: ",")))
        }
        let result = try await send(
            CollectionCreationResult.self, path: "Collections", method: "POST", query: query
        )
        Diagnostics.log("[collections] created \"\(name)\" \(result.id) with \(itemIds.count) members")
        return result.id
    }

    func addToCollection(collectionId: String, itemIds: [String]) async throws {
        guard !itemIds.isEmpty else { return }
        try await sendVoid(
            path: "Collections/\(collectionId)/Items",
            method: "POST",
            query: [URLQueryItem(name: "Ids", value: itemIds.joined(separator: ","))]
        )
        Diagnostics.log("[collections] added \(itemIds.count) to \(collectionId)")
    }

    /// Deletes a grouping — a collection or a playlist — outright.
    ///
    /// One endpoint, because Jellyfin models both as items and neither owns its
    /// members. A BoxSet and a Playlist are grouping objects, not folders: their
    /// contents are ordinary items living in their own libraries, and removing the
    /// grouping leaves every film, episode and track exactly where it was. Worth
    /// being certain about, because "delete" next to a list of titles reads as
    /// though it deletes the titles.
    ///
    /// Needs an account with deletion rights, which Jellyfin gates separately from
    /// editing — an admin who cannot delete is a real configuration.
    func deleteItem(id: String) async throws {
        try await sendVoid(
            // `DELETE /Items?ids=` rather than `DELETE /Items/{id}`. Both exist;
            // the plural is the one Jellyfin's own web client uses and the one that
            // is not deprecated, and the singular is the shape most likely to be
            // quietly dropped by a reverse proxy that strips DELETE bodies.
            path: "Items",
            method: "DELETE",
            query: [URLQueryItem(name: "ids", value: id)]
        )
        Diagnostics.log("[collections] deleted \(id)")
    }

    /// Whether the server still has an item.
    ///
    /// A delete that the server accepts and does not act on is indistinguishable
    /// from one that worked, right up until the next sync brings the item back —
    /// which is how deleted collections kept reappearing on restart.
    func itemExists(id: String) async -> Bool {
        (try? await sendData(
            path: "Users/\(session.userId)/Items/\(id)",
            query: [URLQueryItem(name: "Fields", value: "Id")]
        )) != nil
    }

    func removeFromCollection(collectionId: String, itemIds: [String]) async throws {
        guard !itemIds.isEmpty else { return }
        try await sendVoid(
            path: "Collections/\(collectionId)/Items",
            method: "DELETE",
            query: [URLQueryItem(name: "Ids", value: itemIds.joined(separator: ","))]
        )
        Diagnostics.log("[collections] removed \(itemIds.count) from \(collectionId)")
    }

    /// Artists in a music library.
    ///
    /// Its own endpoint, and it has to be: `/Items?IncludeItemTypes=MusicArtist`
    /// returns nothing on a normal Jellyfin install. Artists are not stored as
    /// ordinary children of the library the way albums are — they are derived from
    /// the tags on the tracks — so only `/Artists` knows about them. Asking `/Items`
    /// for them is why the Artists tab came back empty.
    /// An artist's albums.
    ///
    /// Also not a parent/child lookup: an artist has no children, so browsing into
    /// one means asking for albums *credited* to them. `ArtistIds` is how that is
    /// expressed.
    func artistAlbums(artistId: String, limit: Int = 200) async throws -> [JellyfinItem] {
        let response = try await send(
            ItemsResponse.self,
            path: "Items",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "ArtistIds", value: artistId),
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "PremiereDate,SortName"),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
            ]
        )
        return response.items
    }

    /// Returns the response rather than the items, so a caller can page: the total
    /// is the only thing that says whether there is more, and a bare array cannot
    /// carry it.
    func artists(
        parentId: String, startIndex: Int = 0, limit: Int = 500
    ) async throws -> ItemsResponse {
        try await send(
            ItemsResponse.self,
            path: "Artists",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "ParentId", value: parentId),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
            ]
        )
    }
}

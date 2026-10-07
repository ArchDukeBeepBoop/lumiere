import Foundation

/// One window onto a live server listing, and how much there is in total.
///
/// Music and playlists are never synced — recursing a music library pulls every
/// track — so every screen of them is a request rather than a query, and there is no
/// cached count to fall back on. The total has to come back with the page or the
/// browser cannot know whether it has reached the end.
///
/// Before this, each of these calls took a `limit` and returned a bare array: an
/// album wall stopped at 500 rows with nothing on screen saying so, and the A–Z rail
/// beside it implied the whole library was there.
public struct MusicPage: Sendable {
    public var entries: [LibraryEntry]
    /// How many the server says exist, not how many came back.
    public var total: Int

    public init(entries: [LibraryEntry], total: Int) {
        self.entries = entries
        self.total = total
    }

    public static let empty = MusicPage(entries: [], total: 0)
}

public extension LibraryRepository {

    /// A page of a parent's immediate children.
    func serverChildrenPage(
        parentId: String, offset: Int = 0, limit: Int = 200
    ) async throws -> MusicPage {
        let response = try await client.items(
            parentId: parentId, recursive: false, startIndex: offset, limit: limit
        )
        return try await page(from: response)
    }

    /// A page of everything of a given type under `parentId`.
    func serverItemsPage(
        parentId: String,
        types: [JellyfinItem.ItemType],
        sortBy: [String] = ["SortName"],
        sortOrder: JellyfinClient.SortOrder = .ascending,
        offset: Int = 0,
        limit: Int = 200
    ) async throws -> MusicPage {
        // Artists stay the exception: they are derived from track tags rather than
        // stored as children, so only `/Artists` returns them and `/Items` answers
        // with nothing at all.
        // Genres, like artists, are values rather than rows: `/MusicGenres` is
        // the only thing that lists them.
        if types == [.musicGenre] {
            let response = try await client.musicGenres(
                parentId: parentId, startIndex: offset, limit: limit
            )
            return try await page(from: response)
        }
        if types == [.musicArtist] {
            let response = try await client.artists(
                parentId: parentId, startIndex: offset, limit: limit
            )
            return try await page(from: response)
        }

        let response = try await client.items(
            parentId: parentId, types: types, recursive: true,
            sortBy: sortBy, sortOrder: sortOrder, startIndex: offset, limit: limit
        )
        return try await page(from: response)
    }

    /// A page of starred audio.
    func favouriteAudioPage(offset: Int = 0, limit: Int = 200) async throws -> MusicPage {
        let response = try await client.items(
            types: [.audio, .musicAlbum],
            recursive: true,
            sortBy: ["SortName"],
            startIndex: offset,
            limit: limit,
            filters: ["IsFavorite"]
        )
        return try await page(from: response)
    }

    /// A page of a playlist's rows, with each row's own entry id.
    ///
    /// The entry ids are what removal has to name — a track listed twice has two of
    /// them — so they are carried alongside rather than derived from the items.
    func playlistChildrenPage(
        playlistId: String, offset: Int = 0, limit: Int = 200
    ) async throws -> (page: MusicPage, entryIds: [String: String]) {
        let response = try await client.playlistItems(
            playlistId: playlistId, startIndex: offset, limit: limit
        )
        var ids: [String: String] = [:]
        for item in response.items {
            if let entryId = item.playlistItemId { ids[item.id] = entryId }
        }
        return (try await page(from: response), ids)
    }

    /// Caches a response's items and turns it into a page.
    ///
    /// A server that reports zero while handing back rows would stop the browser
    /// after one window, so the count is floored at what actually arrived — the
    /// total is a claim about the listing, and it cannot be smaller than the part
    /// of it in hand.
    ///
    /// Not private: LibraryRepository+People.swift pages a live `/Items` listing
    /// for exactly the same reason music does — an actor's filmography is a
    /// server-side question — and a second copy of this would be a second place
    /// for the floor above to be forgotten.
    func page(from response: ItemsResponse) async throws -> MusicPage {
        try await cache(items: response.items)
        let entries = try await entriesById(response.items.map(\.id))
        // Every server-derived page goes through here — a performer's filmography
        // included — so this is the one place the privacy filter has to be applied
        // for all of them. The total is left as the server reported it: correcting
        // it would announce how much was removed.
        return MusicPage(
            entries: await visible(entries),
            total: max(response.totalRecordCount, entries.count)
        )
    }

    /// A page of the music filed under one genre.
    ///
    /// The genre's *name* is what filters, because that is what the server stores
    /// — there is no genre row to hold an id, so the name is the id. Albums and
    /// tracks together: a genre is a way into a library, and an album you can
    /// open is a better answer than the forty songs inside it.
    func musicGenrePage(
        genre: String, parentId: String, offset: Int = 0, limit: Int = 200
    ) async throws -> MusicPage {
        let response = try await client.items(
            parentId: parentId, types: [.musicAlbum, .audio], recursive: true,
            sortBy: ["SortName"], startIndex: offset, limit: limit,
            genres: [genre]
        )
        return try await page(from: response)
    }
}

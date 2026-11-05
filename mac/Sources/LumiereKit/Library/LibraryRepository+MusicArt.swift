import Foundation

public extension LibraryRepository {

    /// A few albums and artists from a music library, in random order, for its
    /// card on Home.
    ///
    /// Asked of the server because music is never synced into the cache — the
    /// same reason the card used to fall back to a drawn glyph. Only titles
    /// with a cover come back, so the first one always has a picture. Not
    /// written to the cache: these are only ever looked at.
    func randomMusicArtwork(libraryId: String, limit: Int = 6) async -> [LibraryEntry] {
        guard let response = try? await client.items(
            parentId: libraryId, types: [.musicAlbum, .musicArtist],
            sortBy: ["Random"], limit: limit * 2
        ) else { return [] }
        return response.items
            .filter { $0.imageTags?["Primary"] != nil }
            .prefix(limit)
            .map { LibraryEntry(item: ItemRecord(from: $0, serverId: serverId, syncedAt: Date()), userData: nil) }
    }
}

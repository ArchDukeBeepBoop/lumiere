import Foundation
import GRDB

public extension LibraryRepository {

    /// Playlists, for a picker. Audio-only by default, since the music side is
    /// where adding to one is offered.
    func audioPlaylists() async throws -> [LibraryEntry] {
        let fetched = try await client.playlists(mediaType: "Audio")
        try await cache(items: fetched)
        return try await entriesById(fetched.map(\.id))
    }

    @discardableResult
    func createPlaylist(name: String, itemIds: [String] = []) async throws -> String {
        try await client.createPlaylist(name: name, itemIds: itemIds)
    }

    func addToPlaylist(playlistId: String, itemIds: [String]) async throws {
        try await client.addToPlaylist(playlistId: playlistId, itemIds: itemIds)
    }

    /// Deletes a playlist, leaving every track in it alone.
    ///
    /// The cached row goes with it. Music is never synced, so the playlist list is
    /// read live and would correct itself — but a playlist that was opened once is
    /// in the cache, and leaving it there means it reappears in pickers offering to
    /// add tracks to something that no longer exists.
    func deletePlaylist(id: String) async throws {
        try await client.deleteItem(id: id)
        try await database.writer.write { db in
            _ = try ItemRecord.deleteOne(db, key: id)
            _ = try UserDataRecord.deleteOne(db, key: id)
        }
    }

    func removeFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        try await client.removeFromPlaylist(playlistId: playlistId, entryIds: entryIds)
    }

    /// A playlist's contents, alongside the entry id of each row.
    ///
    /// The two come back together rather than the entry id being folded into
    /// `LibraryEntry`, because it belongs to this playlist's membership and not to
    /// the track: the same track in two playlists has two different ones, and a
    /// cached row can only hold one truth.
    func playlistChildren(
        playlistId: String
    ) async throws -> (entries: [LibraryEntry], entryIds: [String: String]) {
        let result = try await playlistChildrenPage(playlistId: playlistId, limit: 2_000)
        return (result.page.entries, result.entryIds)
    }

    /// Favourite tracks, albums and artists.
    ///
    /// Read live rather than from the cache: music is never synced — recursing a
    /// music library pulls every track — so there are no local rows to filter. The
    /// server already knows which items are starred, which makes this one query
    /// rather than a walk.
    func favouriteAudio(limit: Int = 500) async throws -> [LibraryEntry] {
        try await favouriteAudioPage(limit: limit).entries
    }
}

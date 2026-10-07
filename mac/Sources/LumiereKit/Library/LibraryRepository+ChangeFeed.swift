import Foundation
import GRDB

/// Applying the server's change feed to the cache.
///
/// Lumiere's server numbers every item added, changed or removed, and answers
/// "what happened since change N?" — see `JellyfinClient.changes(since:)`. That
/// replaces reading the newest 400 rows of every library and walking each one
/// in full once a week, which could not see a deletion, a rename or an edit
/// until the week was up. A real Jellyfin has no feed; the old passes still
/// serve it.
extension LibraryRepository {

    /// What one batch of the feed did, for the sync panel's line.
    public struct FeedResult: Sendable {
        public var changed = 0
        public var removed = 0
    }

    /// Item types the cache holds. Music is read live, never cached — the
    /// library sync skips music libraries for the same reason.
    private static let feedSkipsTypes: Set<String> = ["Audio", "MusicAlbum", "MusicArtist", "Playlist"]

    /// Fetches the changed items, writes them, and removes the removed ones.
    /// Only into `libraryIds` — the libraries the sync reads.
    public func applyChanges(
        changed: [String], removed: [String], libraryIds known: Set<String>
    ) async throws -> FeedResult {
        var result = FeedResult()

        for chunk in stride(from: 0, to: changed.count, by: 150).map({ Array(changed[$0..<min($0 + 150, changed.count)]) }) {
            try Task.checkCancellation()
            let response = try await client.items(
                recursive: true, limit: chunk.count, ids: chunk, fields: .listWithVersions
            )
            let existing: [String: String] = try await database.writer.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT id, libraryId FROM item WHERE id IN (\(chunk.map { _ in "?" }.joined(separator: ",")))",
                                            arguments: StatementArguments(chunk))
                return Dictionary(rows.compactMap { row -> (String, String)? in
                    guard let id: String = row["id"], let lib: String = row["libraryId"] else { return nil }
                    return (id, lib)
                }, uniquingKeysWith: { a, _ in a })
            }
            let now = Date()
            let byLibrary = Dictionary(grouping: response.items.filter { item in
                !Self.feedSkipsTypes.contains(item.type.rawValue)
            }) { item in item.topParentId ?? existing[item.id] ?? "" }
            result.changed += try await database.writer.write { [serverId] db -> Int in
                var written = 0
                for (libraryId, items) in byLibrary where known.contains(libraryId) {
                    try Self.writeItems(items, libraryId: libraryId, serverId: serverId, now: now, db: db)
                    written += items.count
                }
                // A page that showed the old version is stale the moment this lands.
                for id in chunk {
                    try db.execute(sql: "DELETE FROM itemDetail WHERE itemId = ?", arguments: [id])
                }
                return written
            }
        }

        if !removed.isEmpty {
            result.removed = try await database.writer.write { db -> Int in
                var count = 0
                for id in removed {
                    if try ItemRecord.deleteOne(db, key: id) { count += 1 }
                    try UserDataRecord.deleteOne(db, key: id)
                    try ItemVersionRecord.filter(Column("itemId") == id).deleteAll(db)
                    try db.execute(sql: "DELETE FROM itemDetail WHERE itemId = ?", arguments: [id])
                }
                return count
            }
        }
        return result
    }

    /// Writes a page of items as a sync does: the row, its versions, and its
    /// watch state. Shared by the library pass and the change feed, so the two
    /// can never store an item differently.
    static func writeItems(
        _ items: [JellyfinItem], libraryId: String, serverId: String, now: Date, db: Database
    ) throws {
        for item in items {
            var record = ItemRecord(from: item, serverId: serverId, syncedAt: now)
            // The owning library, stamped by the caller rather than read from
            // the item. Jellyfin only returns ParentId when Fields asks for it,
            // and `.list` does not — so this was NULL on all 40,000 rows, every
            // library grid came back empty, and the stale-item sweep, which
            // matches on this column, never removed anything.
            record.libraryId = libraryId
            try record.save(db)
            // The files this item swallowed, if any. Replaced wholesale so a
            // file removed on disk does not linger as a phantom row.
            try ItemVersionRecord.filter(Column("itemId") == item.id).deleteAll(db)
            if let sources = item.mediaSources, sources.count > 1 {
                for source in sources {
                    try ItemVersionRecord(
                        itemId: item.id, sourceId: source.id, path: source.path, name: source.name
                    ).insert(db)
                }
            }
            if let userData = item.userData {
                // Unless this Mac holds a position the server has not been told
                // about yet: the outbox row is the newer truth until it is
                // delivered. See `PlaybackOutbox`.
                let pending = try PlaybackOutboxRecord
                    .filter(Column("itemId") == item.id)
                    .fetchOne(db) != nil
                    || WriteOutboxRecord.filter(Column("itemId") == item.id).fetchCount(db) > 0
                if !pending {
                    try UserDataRecord(itemId: item.id, from: userData, updatedAt: now).save(db)
                }
            }
        }
    }
}

import Foundation
import GRDB

/// Manual shelf placement inside one collection — overrides the automatic
/// grouping by source library for whichever member the Director moved by hand.
struct CollectionShelfLabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collectionShelfLabel"

    var collectionId: String
    var itemId: String
    var label: String
    var updatedAt: Date
}

public extension LibraryRepository {

    /// A collection's members, in the server's own order.
    ///
    /// Fetched live rather than from the local cache: a BoxSet's membership is not
    /// a parent/child folder relationship, so nothing during the ordinary library
    /// sync ever records which items belong to which collection. This mirrors
    /// `extras`/`similarEntries` — ask the server, cache what comes back, hand back
    /// entries — rather than trying to infer membership from data that was never
    /// there.
    func collectionItems(collectionId: String) async throws -> [LibraryEntry] {
        try await serverChildren(parentId: collectionId)
    }

    /// The immediate children of anything, fetched live and cached on the way through.
    ///
    /// The counterpart to `folderChildren`, which reads only what a sync already
    /// wrote. This is for the things no sync covers: a collection's membership, and
    /// music and playlist libraries — those are skipped by `syncLibrary` on purpose,
    /// since recursing a music library pulls every track and is unbounded work for a
    /// cache that would then hold tens of thousands of rows nothing browses. Fetching
    /// one level at a time as someone actually navigates costs one request per screen.
    /// The first page only. Callers that browse use `serverChildrenPage`; this is
    /// for the places where the whole set is small by construction — a collection's
    /// membership, an album's tracks.
    func serverChildren(parentId: String, limit: Int = 2_000) async throws -> [LibraryEntry] {
        try await serverChildrenPage(parentId: parentId, limit: limit).entries
    }

    /// What sits inside a music row when it is opened: an album's tracks, or an
    /// artist's albums.
    ///
    /// Artists need their own call because they are not parents of anything — an
    /// artist is derived from track tags, so "their" albums are the ones credited to
    /// them rather than filed under them.
    func musicChildren(of entry: LibraryEntry) async throws -> [LibraryEntry] {
        guard entry.item.itemType == .musicArtist else {
            return try await serverChildren(parentId: entry.id)
        }
        let fetched = try await client.artistAlbums(artistId: entry.id)
        try await cache(items: fetched)
        return try await entriesById(fetched.map(\.id))
    }

    /// Everything of a given type anywhere under `parentId`, fetched live.
    ///
    /// What lets a music library be read by album or by artist rather than only as
    /// the folder tree it happens to sit in: a recursive typed query returns every
    /// album across every artist in one call, which is the view someone actually
    /// wants when they think "my albums".
    func serverItems(
        parentId: String,
        types: [JellyfinItem.ItemType],
        sortBy: [String] = ["SortName"],
        limit: Int = 2_000
    ) async throws -> [LibraryEntry] {
        // Artists are the exception: they are derived from track tags rather than
        // stored as children, so only `/Artists` returns them and `/Items` answers
        // with nothing at all.
        try await serverItemsPage(
            parentId: parentId, types: types, sortBy: sortBy, limit: limit
        ).entries
    }

    /// Every collection in the library, for pickers that need to list them all
    /// rather than show one. Local: collections themselves sync like any other
    /// top-level item, only their membership does not.
    func allCollections() async throws -> [LibraryEntry] {
        try await entries(types: [.boxSet], sort: .title, limit: 500)
    }

    /// Creates a collection on the server and caches the result so it appears in
    /// the Collections library without waiting for the next sync.
    ///
    /// `refreshItem` alone is not enough here: `libraryId` is stamped from the
    /// *request* during an ordinary sync, never read off the item itself, so a
    /// brand new collection would cache with no library and stay invisible in the
    /// Collections grid until the next full sync happened to reach it.
    @discardableResult
    func createCollection(
        name: String, itemIds: [String] = [], tmdbCollectionId: String? = nil
    ) async throws -> LibraryEntry? {
        let id = try await client.createCollection(
            name: name, itemIds: itemIds, tmdbCollectionId: tmdbCollectionId
        )
        let item = try await client.item(id: id)
        let boxsetsLibraryId = try await libraries().first { $0.collectionType == "boxsets" }?.id

        var mutableRecord = ItemRecord(from: item, serverId: serverId, syncedAt: Date())
        mutableRecord.libraryId = boxsetsLibraryId
        let record = mutableRecord
        try await database.writer.write { db in try record.save(db) }
        LibraryChangeFeed.shared.note("collection made", itemId: id)

        return try await entry(id: id)
    }

    /// Deletes a collection on the server and drops its cached row.
    ///
    /// The local delete is not an optimisation: without it the collection stays in
    /// every grid until the next *full* scan, since an incremental sync only ever
    /// reads the newest rows and would never notice the absence.
    /// `announce: false` is for an Undo's own delete, which must not offer an
    /// Undo of its own.
    func deleteCollection(id: String, announce: Bool = true) async throws {
        // Kept for Undo: the name and the members are what a collection is.
        let name = (try? await entry(id: id))?.item.name
        let members = ((try? await collectionItems(collectionId: id)) ?? []).map(\.id)
        try await client.deleteItem(id: id)
        if let name { await DeletedCollections.shared.keep(.init(name: name, itemIds: members)) }

        // Confirmed before the local row goes.
        //
        // Deleting a BoxSet needs the account's "allow media deletion" permission,
        // and without it Jellyfin can accept the request and simply not act on it.
        // Dropping the cached row on that basis made the collection vanish from the
        // app and come back at the next sync — the server had never stopped
        // returning it. Saying so is the only way that is not a lie.
        if await client.itemExists(id: id) {
            throw JellyfinError.httpError(
                status: 0,
                body: "The server still has this collection. Deleting one needs an "
                    + "account with media-deletion permission — on the server, "
                    + "Dashboard → Users → your user → Allow media deletion."
            )
        }

        try await database.writer.write { db in
            _ = try ItemRecord.deleteOne(db, key: id)
            _ = try UserDataRecord.deleteOne(db, key: id)
            // The personal order and the shelf labels were scoped to this
            // collection; nothing else will ever read them again.
            try CollectionShelfLabelRecord
                .filter(Column("collectionId") == id).deleteAll(db)
            try CollectionRankRecord
                .filter(Column("collectionId") == id).deleteAll(db)
        }
        LibraryChangeFeed.shared.note(announce ? DeletedCollections.reason : "collection deleted", itemId: id)
    }

    /// Drops a collection the server has already deleted — merged away — from
    /// the cache, so no grid shows it until the next full sync.
    func forgetCollection(id: String) async throws {
        try await database.writer.write { db in _ = try ItemRecord.deleteOne(db, key: id) }
        LibraryChangeFeed.shared.note("collection deleted", itemId: id)
    }

    func addToCollection(collectionId: String, itemIds: [String]) async throws {
        try await client.addToCollection(collectionId: collectionId, itemIds: itemIds)
        // Every page showing the collection, and Home, follow at once.
        LibraryChangeFeed.shared.note("collection changed", itemId: collectionId)
    }

    func removeFromCollection(collectionId: String, itemId: String) async throws {
        try await client.removeFromCollection(collectionId: collectionId, itemIds: [itemId])
        // The label was scoped to this membership; leaving it behind would silently
        // reappear and misfile whatever the id is reused for next, however unlikely.
        try await setShelfLabel(collectionId: collectionId, itemId: itemId, label: nil)
        LibraryChangeFeed.shared.note("collection changed", itemId: collectionId)
    }

    // MARK: - Shelf labels

    /// Every manual shelf override in this collection, keyed by item.
    func shelfLabels(collectionId: String) async throws -> [String: String] {
        let rows: [CollectionShelfLabelRecord] = try await database.writer.read { db in
            try CollectionShelfLabelRecord
                .filter(Column("collectionId") == collectionId)
                .fetchAll(db)
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.itemId, $0.label) })
    }

    /// `label: nil` clears the override, returning that member to whichever shelf
    /// its source library groups it under automatically.
    func setShelfLabel(collectionId: String, itemId: String, label: String?) async throws {
        try await database.writer.write { db in
            if let label, !label.isEmpty {
                try CollectionShelfLabelRecord(
                    collectionId: collectionId, itemId: itemId, label: label, updatedAt: Date()
                ).save(db)
            } else {
                try CollectionShelfLabelRecord
                    .filter(Column("collectionId") == collectionId)
                    .filter(Column("itemId") == itemId)
                    .deleteAll(db)
            }
        }
    }
}

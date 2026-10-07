import Foundation
import GRDB

/// Reads and writes about *watching*, as opposed to about the library.
///
/// Split from LibraryRepository.swift for the project's 300-line rule. Continue
/// Watching, a single item with its state joined on, and the local write that keeps
/// the two honest while a file is playing all answer the same question — where you
/// are in something — which the queries above them deliberately do not.
public extension LibraryRepository {

    /// Partly-watched items, newest first. Backs the hero and the continue row.
    func resumeEntries(limit: Int = 20) async throws -> [LibraryEntry] {
        // Continue Watching is the single most exposed list in the app: it is the
        // first thing on the home screen and it says what you were doing last.
        let privacy = privacyFilter()
        return try await database.writer.read { [serverId] db in
            // Ordered by when it was last *watched*, not by when the file arrived.
            //
            // This ordered by `item.dateCreated`, so the shelf was sorted by how old
            // the file was in the library. On this library that is not a subtle
            // difference: something watched minutes ago sat outside the first
            // fourteen rows, behind imports from months earlier, and with the shelf
            // showing twelve it was simply absent. "Continue Watching does not show
            // everything I have not finished" is that, exactly.
            //
            // `lastPlayedDate` is the server's own field. Rows synced before it
            // existed have none, so `updatedAt` is the fallback and `dateCreated`
            // the last resort — which keeps the old behaviour for a cache that has
            // not yet been re-synced rather than dropping those rows to the bottom.
            let watched = TableAlias()
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .including(required: ItemRecord.userDataAssociation.aliased(watched))
                .joining(required: ItemRecord.userDataAssociation
                    .filter(Column("playbackPositionTicks") > 0)
                    .filter(Column("played") == false))
                .order(
                    watched[Column("lastPlayedDate")].desc,
                    watched[Column("updatedAt")].desc,
                    Column("dateCreated").desc
                )
                // Over-fetched, then filtered: the 90% cut needs the runtime and
                // the position together, which is a comparison between two
                // columns on two tables. Reading a few extra rows and dropping
                // them in Swift keeps one copy of the rule — see
                // `LibraryEntry.isFinishedForResume` — instead of a second one
                // written in SQL that can drift from it.
                .limit(limit * 2)
            if let privacy { request = request.filter(sql: privacy) }
            return try LibraryEntry.fetchAll(db, request)
                .filter { !$0.isFinishedForResume }
                .prefix(limit)
                .map { $0 }
        }
    }

    func entry(id: String) async throws -> LibraryEntry? {
        try await database.writer.read { db in
            let request = ItemRecord
                .filter(Column("id") == id)
                .including(optional: ItemRecord.userDataAssociation)
            return try LibraryEntry.fetchOne(db, request)
        }
    }

    /// Records locally what the server was just told, so the UI updates without
    /// waiting for a re-sync.
    ///
    /// - Parameter announce: whether to tell `LibraryChangeFeed`, which every open
    ///   screen listens to. True for the end of a session — that is when a page
    ///   showing this item is wrong and needs redrawing. False for the ten-second
    ///   heartbeat during playback: nothing on screen is stale while the player is
    ///   over it, and refreshing every shelf in the app six times a minute for the
    ///   whole of a film is work nobody asked for and nobody would see.
    func applyLocalProgress(
        itemId: String, positionSeconds: Double, played: Bool? = nil, announce: Bool = true
    ) async throws {
        try await database.writer.write { db in
            var record = try UserDataRecord.fetchOne(db, key: itemId)
                ?? UserDataRecord(itemId: itemId, from: nil, updatedAt: Date())
            record.playbackPositionTicks = Int64(positionSeconds * 10_000_000)
            if let played { record.played = played }
            record.updatedAt = Date()
            // So Continue Watching reorders the moment you stop, rather than at the
            // next sync. The server sets its own `LastPlayedDate` from the progress
            // report; this is the local half of the same fact.
            record.lastPlayedDate = Date()
            try record.save(db)
        }
        if announce {
            LibraryChangeFeed.shared.note("playback progress", itemId: itemId)
        }
    }
}

public extension LibraryRepository {
    /// One playable thing, chosen at random from what you have not finished.
    ///
    /// Films and episodes only: a series row has no file behind it, so "shuffle"
    /// landing on one would open a page rather than start something.
    ///
    /// `ORDER BY RANDOM()` over the filtered set rather than a fetch-and-pick in
    /// Swift, because the filtered set here is tens of thousands of episodes and
    /// pulling them into memory to discard all but one is the expensive way to do
    /// arithmetic SQLite already does.
    ///
    /// Private libraries are excluded through the same filter as every other
    /// cross-library read: a shuffle button is the definition of a request that did
    /// not name a library, and having it open something from a hidden one would
    /// undo the whole point of hiding it.
    func randomPlayable() async throws -> LibraryEntry? {
        let privacy = privacyFilter()
        return try await database.writer.read { [visibleServerIds] db in
            var request = ItemRecord
                .filter(visibleServerIds.contains(Column("serverId")))
                .filter(Column("extraType") == nil)
                .filter(["Movie", "Episode", "Video"].contains(Column("type")))
                .filter(Column("isFolder") == false)
                .including(optional: ItemRecord.userDataAssociation)
                .filter(sql: "NOT EXISTS (SELECT 1 FROM userData "
                           + "WHERE userData.itemId = item.id AND userData.played = 1)")
                .order(sql: "RANDOM()")
                .limit(1)
            if let privacy { request = request.filter(sql: privacy) }
            return try LibraryEntry.fetchOne(db, request)
        }
    }
}

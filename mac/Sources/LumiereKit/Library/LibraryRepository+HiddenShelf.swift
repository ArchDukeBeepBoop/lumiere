import Foundation
import GRDB

// MARK: - Hidden shelf items

public extension LibraryRepository {
    /// Removes an item from Continue Watching and Next Up.
    ///
    /// Local only. Jellyfin has no equivalent, and the tempting shortcut — marking it
    /// watched so it falls out of the server's Next Up — would corrupt real watch
    /// history on every other client.
    func hideFromShelves(itemId: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO hiddenShelfItem (itemId, hiddenAt) VALUES (?, ?)",
                arguments: [itemId, Date()]
            )
        }
        LibraryChangeFeed.shared.note("hidden from shelves", itemId: itemId)
    }

    func unhideFromShelves(itemId: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM hiddenShelfItem WHERE itemId = ?", arguments: [itemId])
        }
        LibraryChangeFeed.shared.note("unhidden", itemId: itemId)
    }

    /// Empties the hidden list in one go.
    ///
    /// Only this local list is dropped — no item, file or watch state is touched,
    /// exactly as with unhiding one at a time. Worth having as its own call rather
    /// than looping the single-item version, because a list built up over months is
    /// otherwise a click per row to clear.
    func clearHiddenShelfItems() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM hiddenShelfItem")
        }
        LibraryChangeFeed.shared.note("hidden list cleared")
    }

    /// Forgets that an item was ever watched — resume position and played state,
    /// on the server and in the cache.
    ///
    /// Distinct from hiding, and the difference matters. Hiding keeps the history
    /// and merely refuses to show it on two shelves; this erases the history itself,
    /// so the item drops out of Continue Watching and Next Up because there is
    /// genuinely nothing to continue. Nothing on disk is touched — the file is
    /// exactly where it was, and stays playable from the start.
    ///
    /// `markPlayed(false)` is what Jellyfin resets the position with: marking an item
    /// unplayed zeroes `PlaybackPositionTicks` along with the played flag, which is
    /// the whole reset in one call.
    func clearWatchHistory(itemId: String) async {
        try? await client.markPlayed(itemId: itemId, played: false)
        try? await database.writer.write { db in
            try db.execute(sql: "DELETE FROM userData WHERE itemId = ?", arguments: [itemId])
            try db.execute(sql: "DELETE FROM hiddenShelfItem WHERE itemId = ?", arguments: [itemId])
        }
        LibraryChangeFeed.shared.note("watch history cleared", itemId: itemId)
    }

    /// Clears the history of everything currently on the hidden list, then empties
    /// the list itself.
    ///
    /// The two together are what "remove this from my history" actually means:
    /// unhiding alone would put every one of them straight back on the shelves it
    /// was hidden from, which is the opposite of the intent.
    func clearWatchHistoryForHiddenItems() async throws {
        let ids = try await hiddenShelfIds()
        for id in ids {
            await clearWatchHistory(itemId: id)
        }
        try await clearHiddenShelfItems()
    }

    func hiddenShelfIds() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT itemId FROM hiddenShelfItem"))
        }
    }

    func hiddenShelfEntries() async throws -> [LibraryEntry] {
        let ids = try await hiddenShelfIds()
        guard !ids.isEmpty else { return [] }
        return try await database.writer.read { db in
            let request = ItemRecord
                .filter(ids.contains(Column("id")))
                .including(optional: ItemRecord.userDataAssociation)
                .order(Column("sortName"))
            return try LibraryEntry.fetchAll(db, request)
        }
    }
}

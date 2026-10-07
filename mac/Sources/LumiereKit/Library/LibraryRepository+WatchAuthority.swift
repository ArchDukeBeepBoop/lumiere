import Foundation
import GRDB

/// Watch state has one author: the server.
///
/// The app writes a tick locally first so it shows the instant you click, and
/// works out a season's unwatched count itself for the same reason. That local
/// arithmetic is a second copy of the server's rules — which episodes count,
/// whether extras do, what a season's own flag means — and every watch-state
/// bug so far was the two copies disagreeing. So the local answer is only ever
/// a preview: once the server has taken the write, its own counts for the item,
/// the containers under it and the containers above it are read back and
/// replace whatever the app guessed.
extension LibraryRepository {

    /// Reads the server's watch state for everything a tick on `itemId` can
    /// have changed, and stores it. Best effort: offline, the preview stands
    /// until the next sync.
    func adoptServerWatchState(around itemId: String) async {
        guard let ids = try? await database.writer.read({ db -> [String] in
            var ids = [itemId]
            ids += try Self.ancestors(of: itemId, in: db)
            // Containers under it — a series' seasons. Episodes are left to the
            // local cascade, which cannot disagree with the server about a flag
            // it set on every one of them.
            ids += try String.fetchAll(db, sql: """
                SELECT id FROM item
                WHERE (seriesId = ?1 OR parentId = ?1) AND isFolder = 1
                """, arguments: [itemId])
            return ids
        }), let items = try? await client.userData(ids: ids) else { return }

        try? await database.writer.write { db in
            for item in items {
                guard let data = item.userData else { continue }
                var record = try UserDataRecord.fetchOne(db, key: item.id)
                    ?? UserDataRecord(itemId: item.id, from: nil, updatedAt: Date())
                record.played = data.played ?? record.played
                record.unplayedItemCount = data.unplayedItemCount ?? record.unplayedItemCount
                record.updatedAt = Date()
                try record.save(db)
            }
        }
        LibraryChangeFeed.shared.note("watch state confirmed", itemId: itemId)
    }
}

public extension LibraryRepository {

    /// Fires whenever watch state anywhere under `rootId` changes in the cache —
    /// the item itself, its seasons, its episodes.
    ///
    /// Observed from the database rather than announced by whoever wrote it.
    /// A page that re-reads only when a command remembers to tell it is a page
    /// that goes stale the first time a new command forgets; this cannot. The
    /// first value is the current state, so a listener can skip it.
    func watchStateChanges(under rootId: String) -> AsyncStream<Void> {
        let values = ValueObservation.tracking { db in
            // One string rather than rows: `Row` cannot cross the actor
            // boundary, and all a listener needs is "did anything differ".
            try String.fetchOne(db, sql: """
                SELECT group_concat(u.itemId || ':' || u.played || ':'
                    || u.playbackPositionTicks || ':' || ifnull(u.unplayedItemCount, '-')
                    || ':' || u.isFavorite, ',')
                FROM userData u JOIN item i ON i.id = u.itemId
                WHERE i.id = ?1 OR i.seriesId = ?1 OR i.parentId = ?1
                """, arguments: [rootId]) ?? ""
        }
        .removeDuplicates()
        .values(in: database.writer)

        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await _ in values { continuation.yield() }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public extension LibraryRepository {

    /// Announces every change to watch state, whoever wrote it.
    ///
    /// Commands announce their own writes; the background sync, a page of
    /// server results cached on the way past and the server's read-back did
    /// not, so a screen open during a sync kept the ticks it was drawn with.
    /// Watching the table itself closes that for every screen at once — they
    /// all already listen to `LibraryChangeFeed`.
    ///
    /// A digest of the values, not a timestamp: a sync rewrites thousands of
    /// rows with a fresh `updatedAt` and the same state, and that must not
    /// redraw anything. Resume positions are left out on purpose: the player
    /// saves one every few seconds, and stopping announces itself.
    func announceWatchStateChanges() {
        guard watchStateAnnouncer == nil else { return }
        let values = ValueObservation.tracking { db in
            try String.fetchOne(db, sql: """
                SELECT count(*) || ':' || total(played) || ':' || total(isFavorite) || ':' || total(ifnull(unplayedItemCount, 0))
                FROM userData
                """) ?? ""
        }
        .removeDuplicates()
        .values(in: database.writer)
        watchStateAnnouncer = Task {
            var isFirst = true
            do {
                for try await _ in values {
                    if isFirst { isFirst = false; continue }
                    await LibraryChangeFeed.shared.post(
                        LibraryChange(reason: "watch state in the cache", itemId: nil))
                }
            } catch {}
        }
    }
}

public extension LibraryRepository {

    /// An item with the server's latest watch state, for the moment playback
    /// starts.
    ///
    /// The cache learns a position from another device only when a sync
    /// comes round, so resuming an episode finished elsewhere started it
    /// from wherever this Mac last saw it. Asked here with a short deadline:
    /// a slow server must not hold the picture back, and the cached answer
    /// is what plays if it does not reply in time.
    func entryWithServerPosition(id: String) async -> LibraryEntry? {
        let client = self.client
        let fetched = await withTaskGroup(of: JellyfinItem?.self) { group in
            group.addTask { try? await client.userData(ids: [id]).first }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let data = fetched?.userData {
            try? await database.writer.write { db in
                var record = try UserDataRecord.fetchOne(db, key: id)
                    ?? UserDataRecord(itemId: id, from: nil, updatedAt: Date())
                // Only a later watch. This Mac offline keeps a newer position
                // than the server has, and taking the server's would rewind it.
                guard let theirs = data.lastPlayedDate,
                      theirs > (record.lastPlayedDate ?? .distantPast) else { return }
                record.played = data.played ?? record.played
                record.playbackPositionTicks = data.playbackPositionTicks ?? record.playbackPositionTicks
                record.lastPlayedDate = theirs
                record.updatedAt = Date()
                try record.save(db)
            }
        }
        return try? await entry(id: id)
    }
}

import Foundation
import GRDB

extension LibraryRepository {

    /// Marks an item watched or unwatched.
    ///
    /// Writes locally first, then tells the server. The local write is what makes
    /// the tick appear the instant you click rather than after a round trip; if
    /// the server rejects it, the value is put back rather than left lying.
    @discardableResult
    public func setPlayed(itemId: String, played: Bool) async -> Bool {
        let previous = try? await entry(id: itemId)
        await applyLocalWatchState(itemId: itemId, played: played)

        do {
            try await client.markPlayed(itemId: itemId, played: played)
            await adoptServerWatchState(around: itemId)
            return true
        } catch {
            // The server away is not the server saying no: the tick stays,
            // and goes when it is back. See `WriteOutboxRecord`.
            if ConnectionState.isUnreachable(error) {
                await enqueueWrite(itemId: itemId, kind: .played, value: played)
                return true
            }
            // Roll back. A tick that stays on after the server refused is a lie
            // that survives until the next full sync. `isPlayed`, not the raw
            // flag: a season's own flag is rarely set, and restoring it would
            // untick every episode of a season that was fully watched.
            await applyLocalWatchState(itemId: itemId, played: previous?.isPlayed ?? false)
            return false
        }
    }

    /// Forgets an item was ever started: no tick, and no resume position.
    ///
    /// Separate from `setPlayed(itemId:played:false)` because that one cannot do
    /// this job, and the difference only shows on the items people actually want
    /// to clear. `applyLocalWatchState` zeroes the position *only* when marking
    /// something watched — a part-watched episode already has `played == false`,
    /// so flipping it to false again writes nothing, and the tile sits on
    /// Continue Watching at the same timestamp it had before. The menu command
    /// added for exactly that case was inert.
    ///
    /// The server needs telling twice for the same reason: `UserPlayedItems`
    /// carries the tick, and the resume position is only ever written by a
    /// playback report — so clearing it means reporting a stop at zero.
    @discardableResult
    public func clearWatchState(itemId: String) async -> Bool {
        let previous = try? await entry(id: itemId)
        // A season, a show, a folder: everything under it, and the counts the
        // posters draw from. Writing the container's own row alone was what
        // made "Mark Unwatched" on a season do nothing at all — its episodes
        // stayed ticked and its corner stayed off.
        if let previous, UnplayedCount.isContainer(previous.item.itemType) {
            await applyLocalWatchState(itemId: itemId, played: false, clearsPosition: true)
            do {
                try await client.markPlayed(itemId: itemId, played: false)
                await adoptServerWatchState(around: itemId)
                return true
            } catch {
                if ConnectionState.isUnreachable(error) {
                    await enqueueWrite(itemId: itemId, kind: .played, value: false)
                    return true
                }
                await applyLocalWatchState(itemId: itemId, played: previous.isPlayed)
                return false
            }
        }
        try? await applyLocalProgress(itemId: itemId, positionSeconds: 0, played: false)

        do {
            try await client.markPlayed(itemId: itemId, played: false)
            // Best effort, and deliberately not rolled back: the tick above is
            // the fact the UI reads, and a server that took it but refused a
            // stop report at zero will correct its own position on next play.
            // Media source id defaults to the item id on a single-file item,
            // which is every item that can carry a resume position here.
            try? await client.reportPlaybackStopped(
                itemId: itemId,
                mediaSourceId: itemId,
                playSessionId: nil,
                positionSeconds: 0
            )
            return true
        } catch {
            if ConnectionState.isUnreachable(error) {
                await enqueueWrite(itemId: itemId, kind: .played, value: false)
                return true
            }
            if let previous {
                try? await applyLocalProgress(
                    itemId: itemId,
                    positionSeconds: previous.userData?.resumeSeconds ?? 0,
                    played: previous.userData?.played ?? false
                )
            }
            return false
        }
    }

    /// - Parameter clearsPosition: zero resume positions on the way to unwatched
    ///   too — "Mark Unwatched" on a season means from the start.
    func applyLocalWatchState(
        itemId: String, played: Bool, clearsPosition: Bool = false
    ) async {
        try? await database.writer.write { db in
            // The item, and everything playable under it: marking a season
            // marks its episodes, which is what the server does and what the
            // strip has to show before the server's answer comes back. Extras
            // are left alone, as on the server.
            var ids = [itemId]
            var frontier = [itemId]
            var containers: [String] = []
            while let parent = frontier.popLast() {
                let children = try ItemRecord
                    .filter(Column("parentId") == parent
                        || Column("seasonId") == parent
                        || Column("seriesId") == parent)
                    .filter(Column("extraType") == nil)
                    .fetchAll(db)
                    .filter { !ids.contains($0.id) }
                for child in children where UnplayedCount.isContainer(child.itemType) {
                    containers.append(child.id)
                }
                ids.append(contentsOf: children.map(\.id))
                frontier.append(contentsOf: children.map(\.id))
            }
            for id in ids {
                var record = try UserDataRecord.fetchOne(db, key: id)
                    ?? UserDataRecord(itemId: id, from: nil, updatedAt: Date())
                record.played = played
                // Marking something watched clears the resume position, or it
                // would reappear in Continue Watching having just been ticked off.
                if played || clearsPosition { record.playbackPositionTicks = 0 }
                record.updatedAt = Date()
                try record.save(db)
            }

            // The counts the cards actually draw from. A season's corner is not
            // its own `played` flag — it is how many episodes under it are
            // still unwatched — so a cascade that writes the flag and leaves
            // the count is a season that stays marked unwatched while every
            // episode under it ticks over. That was the bug.
            //
            // Recomputed rather than adjusted: the item itself, every container
            // under it, and every container above it, each counted from what is
            // now in the cache. Above matters as much as below — marking one
            // season watched finishes part of the show, and the series tile on
            // the home screen is drawn from the same number.
            if let record = try ItemRecord.fetchOne(db, key: itemId),
               UnplayedCount.isContainer(record.itemType) {
                containers.append(itemId)
            }
            containers.append(contentsOf: try Self.ancestors(of: itemId, in: db))
            for container in Set(containers) {
                try Self.recountUnplayed(container, in: db)
            }
        }
        // Every surface in the app writes watch state through here, so this one
        // line is what keeps Continue Watching honest everywhere. See
        // `LibraryChangeFeed`.
        LibraryChangeFeed.shared.note("watch state", itemId: itemId)
    }

    func applyLocalFavorite(itemId: String, favorite: Bool) async {
        try? await database.writer.write { db in
            var record = try UserDataRecord.fetchOne(db, key: itemId)
                ?? UserDataRecord(itemId: itemId, from: nil, updatedAt: Date())
            record.isFavorite = favorite
            record.updatedAt = Date()
            try record.save(db)
        }
        LibraryChangeFeed.shared.note("favourite", itemId: itemId)
    }

    // MARK: - Favourites and collections

    /// Favourites is a top-level destination reached from the sidebar, so it is
    /// exactly the "read nobody named a library for" that privacy exists to cover.
    /// Both this and the count below leaked until an audit found them.
    public func favouriteEntries(
        limit: Int = 60, offset: Int = 0
    ) async throws -> [LibraryEntry] {
        let privacy = privacyFilter()
        return try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .including(required: ItemRecord.userDataAssociation)
                .joining(required: ItemRecord.userDataAssociation
                    .filter(Column("isFavorite") == true))
                .order(Column("sortName"))
                .limit(limit, offset: offset)
            if let privacy { request = request.filter(sql: privacy) }
            return try LibraryEntry.fetchAll(db, request)
        }
    }

    /// How many favourites there are, for the pager and the count.
    public func favouriteCount() async throws -> Int {
        let privacy = privacyFilter()
        return try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .joining(required: ItemRecord.userDataAssociation
                    .filter(Column("isFavorite") == true))
            // The count leaks as surely as the grid: it says how many private
            // items are starred even when none of them is drawn.
            if let privacy { request = request.filter(sql: privacy) }
            return try request.fetchCount(db)
        }
    }


    /// The years present, newest first, for the library filter.
    ///
    /// Carries the same exclusions as the grid it filters. Without them the list
    /// offered years that belonged to nothing you could see — a private library's
    /// only 1974 title put 1974 in the menu of a grid with no 1974 in it, which
    /// both dead-ends the filter and says the year is in the collection somewhere.
    public func years(libraryId: String? = nil) async throws -> [Int] {
        // Read before the block: `privacyFilter` is actor state and the read
        // closure is not on the actor. Skipped when a library is named, as
        // everywhere else — naming one is a deliberate visit.
        let privacy = libraryId == nil ? privacyFilter() : nil

        return try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("productionYear") != nil)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
            if let privacy { request = request.filter(sql: privacy) }
            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            // DISTINCT in SQL rather than a Set in Swift: this pulled all 40,829
            // year values across to produce the 73 that differ.
            return try Int.fetchAll(
                db, request.select(Column("productionYear")).distinct()
            ).sorted(by: >)
        }
    }
}

// MARK: - Unwatched counts

extension LibraryRepository {

    /// The containers above an item: its season, then its series, and any
    /// folder chain above that.
    public static func ancestors(of itemId: String, in db: Database) throws -> [String] {
        var found: [String] = []
        var next = itemId
        // Bounded rather than `while true`: a cache with a cycle in it — a
        // folder that is somehow its own parent — would otherwise hang the
        // write, and no real tree is twenty deep.
        for _ in 0..<20 {
            guard let record = try ItemRecord.fetchOne(db, key: next) else { return found }
            let parent = record.seasonId ?? record.parentId ?? record.seriesId
            guard let parent, parent != next, !found.contains(parent) else { return found }
            if let above = try ItemRecord.fetchOne(db, key: parent),
               UnplayedCount.isContainer(above.itemType) {
                found.append(parent)
            }
            next = parent
        }
        return found
    }

    /// Counts what is unwatched under one container and writes it down.
    public static func recountUnplayed(_ containerId: String, in db: Database) throws {
        var unplayed = 0
        var frontier = [containerId]
        var seen: Set<String> = [containerId]
        while let parent = frontier.popLast() {
            let children = try ItemRecord
                .filter(Column("parentId") == parent
                    || Column("seasonId") == parent
                    || Column("seriesId") == parent)
                .fetchAll(db)
                .filter { seen.insert($0.id).inserted }
            for child in children {
                if UnplayedCount.counts(type: child.itemType, extraType: child.extraType) {
                    let data = try UserDataRecord.fetchOne(db, key: child.id)
                    if data?.played != true { unplayed += 1 }
                }
                frontier.append(child.id)
            }
        }
        var record = try UserDataRecord.fetchOne(db, key: containerId)
            ?? UserDataRecord(itemId: containerId, from: nil, updatedAt: Date())
        record.unplayedItemCount = unplayed
        record.updatedAt = Date()
        try record.save(db)
    }
}

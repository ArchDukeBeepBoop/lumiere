import Foundation
import GRDB

/// Reconciling the local cache with the server.
///
/// Split out of LibraryRepository.swift, which was well past the project's
/// 300-line limit. Sync is its own concern: it is the only part that writes
/// whole libraries, and the only part that has to survive a server that times
/// out halfway through.
extension LibraryRepository {
    // MARK: - Sync

    /// How many consecutive pages of nothing-new before an incremental pass stops.
    ///
    /// One page is enough in principle. Two guards the case where a handful of items
    /// were added with older creation dates than the batch above them — a re-import
    /// keeps its original timestamps and lands mid-list.
    private static let quietPagesToStop = 2


    func performLibrarySync(
        id libraryId: String,
        mode: SyncMode,
        pageSize: Int,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> SyncReport {
        // Asked once for the library, not once per page.
        let carriesVersions = await wantsVersions(libraryId: libraryId)
        var startIndex = 0
        var total = Int.max
        var seenIds: Set<String> = []
        /// Whether any page failed every retry. It gates the deletion sweep below,
        /// and that gate is the important part of this function.
        var missedAPage = false
        /// Consecutive pages in which every id was already cached.
        var quietPages = 0
        /// Whether any page carried rows the cache did not have. See `SyncReport`.
        var wroteSomething = false
        /// Consecutive pages that failed every retry.
        ///
        /// `total` starts at `Int.max` and is only learned from a successful
        /// response, so a server that goes away before the first page left the loop
        /// running against `Int.max` — ten million iterations, each of four retried
        /// requests with backoff, never terminating and never reporting itself as
        /// offline. Three failures in a row is a server that is gone, not a slow
        /// page.
        var consecutiveFailures = 0

        while startIndex < total {
            try Task.checkCancellation()

            // Retried rather than fatal. A single page of a large library can exceed
            // the request timeout — on a 22,000-episode library it did, and because
            // one throw aborted the whole sync, every page already written was
            // thrown away and no library after it was touched. A page timing out is
            // a transient fact about one request, not a reason to abandon a library.
            let page = startIndex
            let response: ItemsResponse
            do {
                // Each retry asks for less.
                //
                // `My Videos` reported an incomplete scan on every pass while every
                // other library finished: one page timed out, and all four attempts
                // asked the server for the same 200 items. Four identical requests to
                // a server that could not answer the first in time is four ways of
                // failing the same way — retrying is only worth doing if something
                // about the attempt changes.
                //
                // A timeout on a page is the server taking too long to assemble *that
                // many* rows, and this is the largest folder library here. 200, 100,
                // 50, 25 gives it four genuinely different questions, and a smaller
                // page that succeeds is a page that is not missed. The extra round
                // trips are why it is a retry rather than the opening offer.
                response = try await Self.retrying(attempts: 4) { [mode] attempt in
                    let attemptSize = max(25, pageSize >> (attempt - 1))
                    return try await client.items(
                        parentId: libraryId,
                        recursive: true,
                        // Newest first for an incremental pass, so anything added
                        // since the last sync is on the first page or two. Name
                        // order for a full one, which has to walk everything anyway
                        // and is easier to reason about in order.
                        sortBy: mode == .full ? ["SortName"] : ["DateCreated"],
                        sortOrder: mode == .full ? .ascending : .descending,
                        startIndex: page,
                        limit: attemptSize,
                        fields: carriesVersions ? .listWithVersions : .list
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A page that will not load after four tries is skipped, not fatal.
                // Abandoning the library here is what put "Can't reach the server"
                // on screen mid-sync and dropped everything back to the cache: one
                // slow page out of a hundred failed the whole library, and every
                // library queued behind it went untouched.
                Diagnostics.log("[sync] page \(page) of \(libraryId) skipped: \(error)")
                missedAPage = true
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    Diagnostics.log("[sync] \(libraryId) abandoned after 3 failed pages")
                    break
                }
                startIndex += pageSize
                onProgress?(min(startIndex, total), total)
                continue
            }
            consecutiveFailures = 0
            total = response.totalRecordCount
            if response.items.isEmpty { break }

            let now = Date()
            let items = response.items
            seenIds.formUnion(items.map(\.id))

            // Whether this page held anything the cache had not already seen. Read
            // before the write below, or every row would look familiar.
            var pageWasKnown = false
            if mode == .incremental {
                pageWasKnown = try await isAllCached(items.map(\.id))
                if !pageWasKnown { wroteSomething = true }
            } else {
                // A full pass writes the library by definition; whether any one
                // row differed is not worth a query per page to find out.
                wroteSomething = true
            }

            try await database.writer.write { [serverId] db in
                try Self.writeItems(items, libraryId: libraryId, serverId: serverId, now: now, db: db)
            }

            startIndex += items.count
            onProgress?(min(startIndex, total), total)
            if mode == .preview {
                return SyncReport(outcome: .upToDate, seen: seenIds.count, wroteSomething: true)
            }

            if pageWasKnown {
                quietPages += 1
                if quietPages >= Self.quietPagesToStop {
                    Diagnostics.log(
                        "[sync] \(libraryId) incremental stopped after \(startIndex) items"
                    )
                    // Returns before the sweep, and must: this pass saw only the
                    // newest slice of the library, so deleting everything it did
                    // not see would empty the cache.
                    //
                    // `missedAPage` is checked here as well as at the sweep below,
                    // and the omission was visible in a real log: "My Videos" timed
                    // out four times, skipped page 0, then met enough already-known
                    // pages to trip the quiet counter and reported `upToDate` — a
                    // library claiming its cache matched the server when a whole
                    // page of it had never been read. Nothing downstream could tell:
                    // the panel's "incomplete last time" marker reads this outcome,
                    // so the one library worth re-running was the one that looked
                    // fine.
                    return SyncReport(
                        outcome: missedAPage ? .partial : .upToDate,
                        seen: seenIds.count,
                        wroteSomething: wroteSomething
                    )
                }
            } else {
                quietPages = 0
            }
        }

        await adoptOrphanedRows(seenIds: seenIds, libraryId: libraryId)

        // Anything under this library that the server no longer returns has been
        // deleted or moved. Removing it here is what keeps the cache honest.
        //
        // Skipped entirely when a page was missed, and that is not a nicety: the
        // sweep deletes every row this pass did not see, so running it after a
        // partial read would delete 200 real items — and their watch history with
        // them — because one request timed out. A stale row is a much smaller
        // problem than a deleted one, and the next complete sync clears it.
        guard !missedAPage else {
            Diagnostics.log("[sync] \(libraryId) partial — deletion sweep skipped")
            // Not thrown. The server was reachable and most of the library is now
            // cached; calling that an outage is what produced a "Can't reach the
            // server" banner over a library that had just synced 19 pages out of 20.
            return SyncReport(
                outcome: .partial, seen: seenIds.count, wroteSomething: wroteSomething
            )
        }
        // An empty read never sweeps, and this guard is the difference between a
        // stale cache and a destroyed one.
        //
        // `!liveIds.contains(Column("id"))` is rendered by GRDB as `NOT 0` when the
        // set is empty — a predicate true of every row — so a single response of
        // `{"Items": []}` for a library deleted every item in it *and every watch
        // record keyed to them*. Measured on this schema: three rows in, three rows
        // swept. On the owner's Anime library that is 24,788 items and their
        // history, from one server hiccup mid-scan, with `missedAPage` false and the
        // guard above it therefore silent.
        //
        // A library the server has genuinely emptied is indistinguishable from a
        // failed read at this layer, so it keeps its rows until a pass returns
        // something. That is the trade the comment above already states: a stale row
        // is a much smaller problem than a deleted one. `adoptOrphanedRows` guards
        // the same way one file over; the delete path simply never got it.
        let liveIds = seenIds
        guard !liveIds.isEmpty else {
            Diagnostics.log("[sync] \(libraryId) returned nothing — sweep skipped")
            return SyncReport(outcome: .partial, seen: 0)
        }
        // Counted and returned, so the panel can say what the pass actually did.
        // "Removed 7 titles that are no longer on the server" is the only evidence
        // the owner has that a full scan did the thing a quick one cannot.
        let removed = try await database.writer.write { db -> Int in
            let stale = try ItemRecord
                .filter(Column("libraryId") == libraryId)
                .filter(!liveIds.contains(Column("id")))
                .fetchAll(db)
            for record in stale {
                try record.delete(db)
                try UserDataRecord.deleteOne(db, key: record.id)
            }
            return stale.count
        }
        if removed > 0 {
            Diagnostics.log("[sync] \(libraryId) swept \(removed) rows the server no longer has")
        }

        try await recordPassCompleted(libraryId: libraryId, carriedVersions: carriesVersions)
        return SyncReport(
            outcome: .complete, seen: seenIds.count, removed: removed,
            wroteSomething: wroteSomething || removed > 0
        )
    }
}

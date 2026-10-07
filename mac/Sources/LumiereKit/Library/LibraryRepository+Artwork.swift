import Foundation
import GRDB

/// Artwork targets, offline copies, and single-item refresh.
///
/// Split out of LibraryRepository.swift to bring it under the project's
/// 300-line limit.
public extension LibraryRepository {
    /// Every item worth having artwork for, as prefetch targets.
    ///
    /// Series and movies only. Episodes fall back to their series' poster in the UI,
    /// so fetching per-episode artwork would multiply the work by twenty for images
    /// nothing displays.
    /// Everything the library is made of looking at, in the order it is worth
    /// having offline.
    ///
    /// It used to be posters alone, for series, films and box sets. That is why
    /// browsing offline looked broken rather than merely stale: the home hero had no
    /// backdrop, every detail header was an empty slab, and every episode in
    /// Continue Watching, Next Up and a season list was a blank card — 37,646 of
    /// them on this library against 5,017 posters.
    ///
    /// Ordered by kind, then by id, and both parts matter. The order is what the
    /// byte budget spends itself along, so the ranking is a statement about value:
    /// posters first because they are how you find anything; logos next because a
    /// missing one changes a page's typography rather than leaving a gap; backdrops
    /// after that, few in number and the largest thing on any page; episode stills
    /// last because they are the bulk and degrade most gracefully — a missing one
    /// draws `GeneratedThumb`, which is a real card rather than a hole. Ordering
    /// within a kind is by id because the resume cursor is a position in this list,
    /// and a list that reorders between runs would skip or repeat arbitrary items.
    func artworkTargets() async throws -> [ArtworkPrefetcher.Target] {
        try await database.writer.read { db in
            let posters = try ItemRecord
                .filter(["Series", "Movie", "BoxSet"].contains(Column("type")))
                .filter(Column("primaryTag") != nil)
                .order(Column("id"))
                .fetchAll(db)
                .map {
                    ArtworkPrefetcher.Target(itemId: $0.id, tag: $0.primaryTag, kind: .primary)
                }

            // The show's title set as artwork, drawn over the backdrop in place of
            // type. Second only to posters because it is on every detail page and on
            // the home hero, and its absence does not degrade to nothing — it
            // degrades to a different, plainer design, which reads as the page having
            // lost its typography rather than as artwork still loading.
            let logos = try ItemRecord
                .filter(["Series", "Movie", "BoxSet"].contains(Column("type")))
                .filter(Column("logoTag") != nil)
                .order(Column("id"))
                .fetchAll(db)
                .map {
                    ArtworkPrefetcher.Target(
                        itemId: $0.id, tag: $0.logoTag, kind: .logo,
                        widths: ArtworkPrefetcher.logoWidths
                    )
                }

            let backdrops = try ItemRecord
                .filter(["Series", "Movie"].contains(Column("type")))
                .filter(Column("backdropTag") != nil)
                .order(Column("id"))
                .fetchAll(db)
                .map {
                    ArtworkPrefetcher.Target(
                        itemId: $0.id, tag: $0.backdropTag, kind: .backdrop,
                        widths: ArtworkPrefetcher.backdropWidths
                    )
                }

            // An episode's *Primary* is its still — Jellyfin puts the frame grab
            // there, not under Backdrop, which is why `ImageRequest.backdrop` falls
            // through to it for wide cards. Warming it at the wide widths is what
            // makes a season list look like a season list with the server off.
            let stills = try ItemRecord
                .filter(Column("type") == "Episode")
                .filter(Column("primaryTag") != nil)
                .filter(Column("extraType") == nil)
                .order(Column("id"))
                .fetchAll(db)
                .map {
                    ArtworkPrefetcher.Target(
                        itemId: $0.id, tag: $0.primaryTag, kind: .primary,
                        widths: ArtworkPrefetcher.wideWidths
                    )
                }

            return posters + logos + backdrops + stills
        }
    }

    /// Titles for the automatic artwork pass.
    ///
    /// `missingOnly` is the difference between filling gaps and re-doing everything:
    /// the first is the cheap common case, the second is for when the artwork that is
    /// there is simply wrong. Stable id ordering either way, so a run that is
    /// cancelled and restarted covers the same ground in the same order. Extras are
    /// always excluded — bonus material has no poster and does not want one.
    func artworkFetchTargets(
        missingOnly: Bool = true,
        limit: Int = 5000
    ) async throws -> [(id: String, name: String)] {
        try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(["Series", "Movie", "BoxSet"].contains(Column("type")))
                .filter(Column("extraType") == nil)
            if missingOnly {
                request = request.filter(Column("primaryTag") == nil)
            }
            return try request
                .order(Column("id"))
                .limit(limit)
                .fetchAll(db)
                .map { (id: $0.id, name: $0.name) }
        }
    }
}

public extension LibraryRepository {
    /// The offline copy of an item, if one finished and the file is still there.
    ///
    /// Read through the repository rather than by handing the player a
    /// `DownloadManager`: the player needs one fact about one item, and the record
    /// lives in the same database everything else is read from.
    func completedDownload(for itemId: String) async throws -> DownloadRecord? {
        let record = try await database.writer.read { db in
            try DownloadRecord.fetchOne(db, key: itemId)
        }
        // `isPlayableOffline` checks the file, not just the row — a record can
        // outlive its file, and falling back to the network beats failing.
        return record?.isPlayableOffline == true ? record : nil
    }
}

public extension LibraryRepository {
    /// Re-reads one item from the server and updates its cached row.
    ///
    /// Used after a metadata refresh. A full library sync would also pick the change
    /// up, but on a 24,000-item library that is minutes of work to see one poster.
    func refreshItem(itemId: String) async throws {
        let item = try await client.item(id: itemId)
        let existing = try await database.writer.read { db in
            try ItemRecord.fetchOne(db, key: itemId)
        }
        var updated = ItemRecord(from: item, serverId: serverId, syncedAt: Date())
        // The owning library is not in the item payload — it is stamped during sync —
        // so it has to be carried across or the item would vanish from its grid.
        updated.parentId = existing?.parentId
        updated.libraryId = existing?.libraryId
        updated.carryContentDate(from: existing)
        // Carried across for the same reason, and each one was a real regression
        // every time this ran — which is after every edit, every repaired episode,
        // and once per item in the automatic artwork pass over thousands of rows.
        //
        // extraType: the server reports it only on a SpecialFeatures fetch, so a
        // rebuilt row lost it and four featurettes rejoined the film grid.
        // originalTitle now arrives (the detail fields ask for it), but keep the
        // cached value where the server sends nothing rather than blanking a title
        // the search index depends on — and recompute the key from whichever won.
        updated.extraType = updated.extraType ?? existing?.extraType
        updated.originalTitle = updated.originalTitle ?? existing?.originalTitle
        updated.searchKey = SearchKey.key(
            name: updated.name,
            seriesName: updated.seriesName,
            alternative: updated.originalTitle
        )
        let record = updated
        try await database.writer.write { db in try record.save(db) }
    }
}

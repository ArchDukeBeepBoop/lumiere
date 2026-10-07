import Foundation
import GRDB

/// The two shelves no existing query produces.
///
/// Continue Watching says what you were doing last; Next Up says what comes
/// after everything. Neither answers the two questions a large library actually
/// raises: *what can I finish tonight*, and *what did I abandon and forget*.
public extension LibraryRepository {

    /// Series with only a few episodes left.
    ///
    /// Different from Next Up, which offers the next episode of every show you
    /// have ever touched — thirty rows deep on this library, sorted by when you
    /// last watched, with no sense of which is nearly over. This is the shelf you
    /// browse when you have ninety minutes and would rather finish something
    /// than start it.
    ///
    /// The series, not the episode: what is being offered is *closing a show*, so
    /// the card should be the show. Sorted by fewest remaining, so the ones you
    /// can actually finish come first.
    ///
    /// The count is read from the *season*, not the series, and that is the
    /// difference between the shelf's title and a different shelf entirely. A
    /// series-wide `unplayedItemCount <= 3` means "three episodes left in the
    /// whole show" — which on a library of mid-run anime surfaces completed
    /// long-runners and never once surfaces the case the shelf is named for:
    /// three left in the season you are actually watching.
    ///
    /// Seasons are matched, then shown as their series, because the card is
    /// still the show — nobody browses for "Season 3".
    func nearlyFinishedSeries(limit: Int = 12) async throws -> [LibraryEntry] {
        let seasons = try await nearlyFinishedSeasons(limit: limit * 3)
        let seriesIds = seasons.compactMap { $0.item.seriesId ?? $0.item.parentId }
        // Deduplicated in order: two qualifying seasons of one show are one card,
        // and the nearer-finished season decides where the show sits.
        var seen = Set<String>()
        let ordered = seriesIds.filter { seen.insert($0).inserted }
        guard !ordered.isEmpty else { return [] }
        let byId = try await entriesById(ordered)
        let lookup = Dictionary(uniqueKeysWithValues: byId.map { ($0.item.id, $0) })
        return ordered.compactMap { lookup[$0] }.prefix(limit).map { $0 }
    }

    /// The seasons themselves. Separate so the rule is testable on its own.
    func nearlyFinishedSeasons(limit: Int) async throws -> [LibraryEntry] {
        let privacy = privacyFilter()
        return try await database.writer.read { [serverId] db in
            let watched = TableAlias()
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("type") == JellyfinItem.ItemType.season.rawValue)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .including(required: ItemRecord.userDataAssociation.aliased(watched))
                .joining(required: ItemRecord.userDataAssociation
                    // Something left, but not many. Zero is a finished show and
                    // belongs nowhere near a shelf about finishing.
                    .filter(Column("unplayedItemCount") > 0)
                    .filter(Column("unplayedItemCount") <= SeriesProgress.nearlyDoneRemaining)
                    // And actually started. A three-episode show nobody has
                    // opened has three remaining and is not "nearly finished".
                    .filter(Column("lastPlayedDate") != nil))
                .order(
                    watched[Column("unplayedItemCount")].asc,
                    watched[Column("lastPlayedDate")].desc
                )
                .limit(limit)
            if let privacy { request = request.filter(sql: privacy) }
            return try LibraryEntry.fetchAll(db, request)
        }
    }

    /// Things started long enough ago to have been forgotten.
    ///
    /// The most useful shelf a large library can have, and the one nobody builds.
    /// Continue Watching is ordered by recency, so anything you left more than a
    /// fortnight ago is below the fold for ever — it is not that the app forgot,
    /// it is that the shelf is sorted against you.
    ///
    /// Deliberately the *opposite* order: oldest first. The point is the thing
    /// you have not thought about, and putting the freshest at the front would
    /// rebuild Continue Watching.
    func forgottenEntries(limit: Int = 12, now: Date = Date()) async throws -> [LibraryEntry] {
        let privacy = privacyFilter()
        let cutoff = now.addingTimeInterval(-SeriesProgress.forgottenAfter)
        return try await database.writer.read { [serverId] db in
            let watched = TableAlias()
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .including(required: ItemRecord.userDataAssociation.aliased(watched))
                .joining(required: ItemRecord.userDataAssociation
                    .filter(Column("playbackPositionTicks") > 0)
                    .filter(Column("played") == false)
                    .filter(Column("lastPlayedDate") != nil)
                    .filter(Column("lastPlayedDate") < cutoff))
                .order(watched[Column("lastPlayedDate")].asc)
                .limit(limit * 2)
            if let privacy { request = request.filter(sql: privacy) }
            // The same finished-for-resume rule Continue Watching applies, in
            // the same one place: a film abandoned in its credits is not
            // forgotten, it is over. See `LibraryEntry.isFinishedForResume`.
            return try LibraryEntry.fetchAll(db, request)
                .filter { !$0.isFinishedForResume }
                .prefix(limit)
                .map { $0 }
        }
    }
}

/// The thresholds both shelves are defined by.
///
/// Named and shared rather than written twice: "nearly finished" and "forgotten"
/// appear in a shelf, in the spotlight's reasoning and in the copy under each,
/// and three numbers that are meant to be the same number will not stay that way.
public enum SeriesProgress {
    /// The most episodes that can remain and still read as nearly done.
    public static let nearlyDoneRemaining = SpotlightReason.nearlyDoneRemaining
    /// How long before something started counts as forgotten.
    public static let forgottenAfter = SpotlightReason.forgottenAfter
}

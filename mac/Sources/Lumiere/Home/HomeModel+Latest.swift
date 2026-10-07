import Foundation
import LumiereKit

/// Filling a Latest shelf, rather than hoping one query is enough.
///
/// Split from HomeModel.swift for the project's 300-line rule.
extension HomeModel {

    /// What a Latest shelf is allowed to contain.
    ///
    /// Not private: `HomeModel.load` in HomeModel.swift reads it, and Swift's
    /// `private` is file-scoped.
    ///
    /// Episodes are in it because on a TV library the newest thing added is an
    /// episode — a shelf of series ranks a show by when the *show* first appeared,
    /// so one airing weekly never moves and the shelf stops changing between whole
    /// new shows. That was a preference defaulting on, and its only effect when off
    /// was a shelf that lied about what was new.
    ///
    /// Everything else is excluded because it is structure rather than content:
    /// unfiltered, `Season` and `Folder` shells made up twenty-three of the newest
    /// sixty rows here, and the real episodes they outranked never reached the shelf.
    ///
    /// And loose videos, by preference. The scanner files every file in a
    /// folder library as a `Video`, so a row without them showed only what
    /// Jellyfin had imported as films and nothing added since. Extras are
    /// already kept out by the query itself.
    static var shelfTypes: [JellyfinItem.ItemType] {
        var types = LibraryRepository.topLevelTypes + [.episode]
        if Preference.latestIncludesVideos.value { types.append(.video) }
        return types
    }

    /// The tiles for one Latest shelf, or for the whole cache when `libraryId` is nil.
    ///
    /// Collapsing is lossy by design — a season drop of 26 episodes is one tile — so
    /// a single fixed query cannot fill a shelf, and it did not: TV Shows came back
    /// with **6** tiles of a wanted 20 and Anime with **7**. Every other shelf on
    /// screen had twenty, so the two libraries with the most in them looked the
    /// emptiest, which is exactly backwards.
    ///
    /// Escalating the limit rather than paging by offset. Hundreds of rows here share
    /// a `contentDate` to the second — a rescan writes them in one pass — and SQLite
    /// gives no stable order among ties, so `OFFSET` paging can hand back a row twice
    /// and miss another. Asking for more of the same ordered query cannot.
    func latestTiles(
        libraryId: String?, hidden: Set<String>, excludingLibraries: Set<String> = []
    ) async -> [LibraryEntry] {
        await Self.latestTiles(
            repository: repository, libraryId: libraryId,
            hidden: hidden, target: Self.shelfLength,
            excludingLibraries: excludingLibraries
        )
    }

    /// Which libraries the whole-library Recently Added row leaves out. The
    /// rule lives in `RecentlyAddedPolicy`; this only reads the choice.
    static func recentlyAddedExclusions(
        libraries: [LibraryRecord], privateIds: Set<String>
    ) -> Set<String> {
        RecentlyAddedPolicy.excluded(
            libraries: libraries,
            privateIds: privateIds,
            stored: UserDefaults.standard.string(forKey: RecentlyAddedPolicy.storageKey)
        )
    }

    /// The same fill, for a caller that wants a different number of tiles.
    ///
    /// `static` and repository-in so the "See All" screen can ask for fifty through
    /// exactly this code rather than growing a second idea of what "latest" means —
    /// same types, same ranking, same folding of a season into one tile. A shelf and
    /// its own expansion disagreeing about their order would be worse than either.
    static func latestTiles(
        repository: LibraryRepository,
        libraryId: String?,
        hidden: Set<String>,
        target: Int,
        excludingLibraries: Set<String> = []
    ) async -> [LibraryEntry] {
        var slots: [LatestShelf.Slot] = []

        for limit in LatestShelf.fillSteps {
            let raw = (try? await repository.entries(
                types: shelfTypes,
                sort: .latestContent, descending: true,
                libraryId: libraryId, limit: limit
            )) ?? []

            // A failed step keeps what the last one found rather than replacing it.
            // Assigning unconditionally meant a transient error on the *second*
            // query — the database busy behind a sync's write, most plausibly —
            // threw away a perfectly good sixty-row shelf and returned nothing,
            // because the empty result then also read as "library exhausted" and
            // stopped the loop. A shelf that is short is a worse shelf; a shelf that
            // is empty looks like an empty library.
            guard !raw.isEmpty else { break }

            // Before collapsing, not after. An item you dismissed still occupies the
            // slot it would have taken otherwise, so hiding the top three of a shelf
            // used to shorten it by three rather than pulling three more up.
            //
            // And by *series* as well as by row, because filtering the rows alone
            // did not survive the substitution below. Hiding a series tile removes
            // the one `Series` row, but its episodes are still in `shelfTypes` and
            // still carry its id, so `collapse` rebuilds a slot pointing at it and
            // `resolveSeries` fetches the very show that was just dismissed —
            // `entriesById` applies no filters. The tile came straight back, and on
            // a TV library it always would.
            // Excluded libraries are dropped here, before collapsing, for the
            // same reason hidden items are: a slot they would have taken is
            // pulled up from below rather than left short.
            // The library's own rules last, after hiding and exclusion, for the
            // same reason: a slot they refuse is pulled up from below.
            let rules = ShelfRules.all(from: UserDefaults.standard.string(forKey: ShelfRules.storageKey))
            slots = LatestShelf.collapse(raw.filter {
                !hidden.contains($0.id)
                    && !($0.item.libraryId.map(excludingLibraries.contains) ?? false)
                    && ShelfRules.rules(for: $0.item.libraryId, in: rules).qualifies($0)
            })
                .filter { slot in
                    guard let seriesId = slot.seriesId else { return true }
                    return !hidden.contains(seriesId)
                }

            guard LatestShelf.needsMoreRows(
                filled: slots.count, fetched: raw.count,
                asked: limit, target: target
            ) else { break }
        }

        return await resolveSeries(
            repository: repository, slots: Array(slots.prefix(target))
        )
    }
}

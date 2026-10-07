import Foundation
import GRDB

/// Reuniting creditless openings and endings with the episodes they shipped with.
///
/// Jellyfin files these inconsistently, and on a real library both failure modes are
/// present at once: 85 sit inside a season with no episode number, and 38 more —
/// across 17 series — have a series but no season at all. The second group is
/// invisible in Lumiere, because every episode list reads a season's children and
/// these are children of nothing.
public extension LibraryRepository {

    /// Creditless files belonging to a series but filed under no season.
    ///
    /// Read from the cache rather than the server: they were synced like any other
    /// episode, and the only thing wrong with them is where they were filed.
    func creditlessOrphans(seriesId: String) async throws -> [LibraryEntry] {
        try await seasonlessEpisodes(seriesId: seriesId)
    }

    /// Every episode of a series the server filed under no season.
    ///
    /// Two quite different things land here and both were invisible. Creditless
    /// openings and endings, which is what this started as — and ordinary episodes
    /// the scanner failed to place. `Sky Wizards Academy - 1x01 - Fireteam E601.mkv`
    /// was read as episode 601 of no season, so the first episode of the show was
    /// missing from its own list while the file sat beside the others. Whatever the
    /// reason, an episode with a series and no season is unreachable, because every
    /// list in the app reads a season's children.
    func seasonlessEpisodes(seriesId: String) async throws -> [LibraryEntry] {
        try await database.writer.read { db in
            let request = ItemRecord
                .filter(Column("type") == JellyfinItem.ItemType.episode.rawValue)
                .filter(Column("seriesId") == seriesId)
                .filter(Column("seasonId") == nil)
                .including(optional: ItemRecord.userDataAssociation)
            return try LibraryEntry.fetchAll(db, request)
        }
    }

    /// The season that adopts a series' unfiled creditless material.
    ///
    /// The first one, by the same ordering the season picker uses. A file at the
    /// series root belongs to the show rather than to any one season, and appending
    /// it to every season would play the same opening at the end of each — so it
    /// joins where the show starts. One that genuinely sits in `Season 2/` already
    /// has a parent and never comes through here.
    func adoptingSeasonId(seriesId: String) async throws -> String? {
        try await database.writer.read { db in
            let request = ItemRecord
                .filter(Column("type") == JellyfinItem.ItemType.season.rawValue)
                .filter(Column("parentId") == seriesId)
                .order(Column("sortName").asc)
            return try ItemRecord.fetchOne(db, request)?.id
        }
    }

    /// Adds the orphans to a season's list where that season is the adopting one,
    /// then puts every creditless file at the end of the run.
    ///
    /// Called by `episodes(seriesId:seasonId:)`, so the season view and the player's
    /// previous/next chain get the same answer — the two must agree or "next" walks
    /// a different list than the one on screen.
    func withCreditless(
        _ episodes: [LibraryEntry], seriesId: String, seasonId: String?
    ) async -> [LibraryEntry] {
        let orphans = (try? await creditlessOrphans(seriesId: seriesId)) ?? []
        guard !orphans.isEmpty else { return CreditlessClassifier.ordered(episodes) }

        // The all-episodes path has no season to be wrong about, so it takes them.
        guard let seasonId else {
            // Guarded against doubles here too: on a show with no seasons every
            // episode sits under the show, so each one is also an "orphan", and
            // the strip listed the whole show twice.
            let known = Set(episodes.map(\.id))
            return CreditlessClassifier.ordered(episodes + orphans.filter { !known.contains($0.id) })
        }
        guard let adopting = try? await adoptingSeasonId(seriesId: seriesId),
              adopting == seasonId
        else {
            return CreditlessClassifier.ordered(episodes)
        }

        // Guarded against double-adding: an orphan already present would otherwise
        // appear twice on a series whose files are filed both ways.
        let known = Set(episodes.map(\.id))
        let adopted = episodes + orphans.filter { !known.contains($0.id) }

        // Re-sorted, because an adopted episode arrives at the end of the list and
        // an episode 1 tacked after episode 12 is barely better than a missing one.
        // Creditless material is exempt — `ordered` puts it last on purpose, and its
        // sort key is the null pair that started all of this.
        let (creditless, real) = adopted.reduce(into: ([LibraryEntry](), [LibraryEntry]())) {
            if CreditlessClassifier.isCreditless(name: $1.item.name, path: $1.item.path) {
                $0.0.append($1)
            } else {
                $0.1.append($1)
            }
        }
        let ordered = real.sorted { $0.item.sortName < $1.item.sortName }
        return CreditlessClassifier.ordered(ordered + creditless)
    }
}

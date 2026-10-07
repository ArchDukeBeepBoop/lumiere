import Foundation

/// Decides how a run of newly added episodes is represented on a shelf.
///
/// The problem it solves: a library sorted by date added is dominated by whatever
/// was imported last. Drop a 26-episode season in and the entire "Latest" shelf is
/// that one show — twenty-six tiles of the same poster, and nothing else you own
/// gets a place. What you want to know is *that the show got new episodes*, which
/// takes one tile.
///
/// So every series collapses to a single tile. Which tile depends on why the
/// episodes are new:
///
/// - **A recent airing.** The newest episode premiered days ago — this is a show you
///   are following, and the useful tile is the episode itself, because "S2E7 is out"
///   is the actual news and you can play it from there.
/// - **Anything else.** A back catalogue import, a re-scan, a season added years
///   after it aired. Nobody is waiting on episode 4 of a 2016 season, so the tile is
///   the series: it says the show is there without pretending one arbitrary episode
///   of it is an event.
///
/// Pure and testable — no repository, no clock of its own. The caller supplies
/// `now`, which is also how the tests pin the boundary.
public enum LatestShelf {

    /// How recently an episode must have premiered to be treated as a new airing.
    ///
    /// Three weeks rather than one: a weekly show you catch up on fortnightly should
    /// still read as current, and a simulcast that arrives a few days late should not
    /// fall off a cliff. Far short of the months that separate this from a
    /// back-catalogue import, which is the distinction that matters.
    public static let releaseWindow: TimeInterval = 21 * 24 * 60 * 60

    /// How many rows to ask for, in order, until the shelf is full.
    ///
    /// Three steps rather than one number, because the right number differs by two
    /// orders of magnitude between libraries, and asking every library for the worst
    /// case would read a thousand rows to build a shelf that was finished after
    /// twenty.
    ///
    /// Measured against a real 45,000-item library, rows needed to fill a twenty-tile
    /// shelf: Movies 20, Anime Movies 20, 3D 20, My Videos 20, Collections 20,
    /// Adult 45, **TV Shows 408, Anime 415**. The first step finishes six libraries
    /// of nine, the second finishes Adult, and only the two big episode libraries
    /// pay for the third.
    public static let fillSteps = [60, 240, 1_000]

    /// Whether to ask for a bigger page, having collapsed what came back.
    ///
    /// Pure so the stop conditions can be tested without a database, because getting
    /// one wrong is either a short shelf or a loop that reads an entire library every
    /// time the home screen loads.
    ///
    /// - Parameters:
    ///   - filled: how many tiles the collapse produced.
    ///   - fetched: how many rows came back.
    ///   - asked: how many rows were requested.
    ///   - target: how many tiles the shelf wants.
    public static func needsMoreRows(
        filled: Int, fetched: Int, asked: Int, target: Int
    ) -> Bool {
        // `fetched < asked` is the library running out, and it is not a rare case:
        // Hobby TV holds thirteen shows in total, so it can never reach twenty
        // however deep this reads. Without it, every home load would scan that
        // library to the end to come back with the same thirteen tiles.
        guard fetched >= asked else { return false }
        return filled < target
    }

    /// One tile.
    public struct Slot: Sendable, Hashable, Identifiable {
        /// The item to draw when no series record is available — always a real
        /// entry, so a slot can always be rendered.
        public var representative: LibraryEntry
        /// Set when this slot stands for a series rather than for the episode in
        /// `representative`. The caller looks the series up and substitutes it,
        /// falling back to the representative when the series is not cached.
        public var seriesId: String?
        /// How many episodes of this series were folded in. 1 for everything else.
        public var episodeCount: Int

        public var id: String { seriesId ?? representative.id }

        public init(representative: LibraryEntry, seriesId: String?, episodeCount: Int) {
            self.representative = representative
            self.seriesId = seriesId
            self.episodeCount = episodeCount
        }
    }

    /// Folds `entries` — assumed newest-first, as every shelf query returns them —
    /// into at most one slot per series.
    ///
    /// Films, series and anything else pass through untouched: they are already one
    /// tile per title. Episodes with no series id also pass through, because there is
    /// nothing to group them by and dropping them would silently lose content.
    public static func collapse(
        _ entries: [LibraryEntry],
        now: Date = Date(),
        releaseWindow: TimeInterval = releaseWindow
    ) -> [Slot] {
        var slots: [Slot] = []
        /// series id → index in `slots`, so a later episode of a show already seen
        /// only bumps its count rather than adding a tile.
        var indexBySeries: [String: Int] = [:]

        for entry in entries {
            // A series row is the same show as its episodes, and it was not being
            // treated as one: it fell through to the catch-all below without ever
            // being registered, so a show whose series row *and* whose new episodes
            // both landed in the window produced two slots that resolved to the same
            // tile. On a home screen that is the show twice, taking the place of
            // something else you own.
            if entry.item.itemType == .series {
                guard indexBySeries[entry.id] == nil else { continue }
                indexBySeries[entry.id] = slots.count
                slots.append(Slot(representative: entry, seriesId: nil, episodeCount: 1))
                continue
            }

            guard entry.item.itemType == .episode,
                  let seriesId = entry.item.seriesId else {
                slots.append(Slot(representative: entry, seriesId: nil, episodeCount: 1))
                continue
            }

            if let existing = indexBySeries[seriesId] {
                slots[existing].episodeCount += 1
                continue
            }

            // First — and therefore newest — episode of this show in the shelf.
            let isRecentAiring = isRecentAiring(entry, now: now, window: releaseWindow)
            indexBySeries[seriesId] = slots.count
            slots.append(Slot(
                representative: entry,
                seriesId: isRecentAiring ? nil : seriesId,
                episodeCount: 1
            ))
        }

        return slots
    }

    /// Whether an episode counts as newly aired.
    ///
    /// A missing premiere date reads as "no", not "maybe": an item the server never
    /// dated is far more likely to be an unmatched back-catalogue file than this
    /// week's broadcast, and the series tile is the safer thing to show for it. A
    /// date in the future counts — servers pre-populate upcoming episodes, and one
    /// that has arrived early is still current.
    private static func isRecentAiring(
        _ entry: LibraryEntry, now: Date, window: TimeInterval
    ) -> Bool {
        guard let premiere = entry.item.premiereDate else { return false }
        return premiere > now.addingTimeInterval(-window)
    }
}

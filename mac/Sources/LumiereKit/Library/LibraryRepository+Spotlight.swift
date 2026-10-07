import Foundation
import GRDB

/// How the home screen's hero picks what to show.
///
/// The rule, stated once so it can be argued with: **the highest community-rated
/// unwatched title in each video library, taken one library at a time until the
/// spotlight is full.** Three decisions are packed into that sentence.
///
/// *Community rating* rather than play count, because a play count is a fact about
/// this household — the things you have played most are precisely the things you
/// have already seen, and a spotlight of them is a spotlight of reruns. Jellyfin
/// caches the provider's rating on every row (`ItemRecord.communityRating`), so
/// "popular" here means "popular with everyone", which is what the word usually
/// means when a streaming service says it.
///
/// *Unwatched*, because the hero's job is to start something. Continue Watching is
/// still a row of its own and it is better at the other job.
///
/// *One library at a time*, because that is what makes anime, films and TV all
/// appear. Lumiere has no notion of "anime" beyond the library the user filed it
/// in — there is no genre or provider flag that reliably marks it — so the
/// library *is* the axis of variety, and round-robin across libraries is the
/// cheapest honest way to get one of each. A flat "top ten by rating" would be
/// ten anime on this server, because anime is rated generously and there are
/// 24,000 of them.
public enum Spotlight {

    /// How many titles the hero cycles through.
    ///
    /// Small on purpose. Each one is a full-window backdrop — the largest bitmap
    /// the app ever decodes — and while only the visible one is held decoded (see
    /// `HeroSpotlight`), every one you page to is a download and a decode. Six is
    /// enough to feel like a rotation and short enough that the pipeline's memory
    /// cache is not full of 16:9s at window width.
    public static let length = 6

    /// How deep into each library's ranking the rotation may reach.
    ///
    /// The pool an offset picks from, not the number shown. Six titles out of six
    /// candidates would be the same six every time; out of thirty it is five turns
    /// before a title can come round again, per library. Cheap to fetch — thirty
    /// rows of an indexed query — and nothing is downloaded until a backdrop is
    /// actually shown, so a deeper pool costs a query and no bytes.
    public static let poolDepth = 30

    /// Which session this is, as a number that changes every time the app opens.
    ///
    /// It used to be the calendar day, which meant opening Lumiere five times in an
    /// evening showed the same six titles five times, and the only way to see the
    /// rest of the pool was to wait until tomorrow. A session is the unit that
    /// actually corresponds to "I am looking at this again".
    ///
    /// Persisted and incremented rather than random, for the property that matters
    /// more than novelty: within one session the hero must not move. It is read
    /// once at launch, so a refresh, a sync or a library change during the session
    /// cannot reshuffle a spotlight somebody is halfway through reading.
    ///
    /// Taken as a parameter by `mix` rather than read inside it, so the mixing rule
    /// stays a pure function with tests that do not depend on when they run.
    public static func beginSession(
        in defaults: UserDefaults = .standard, key: String = "spotlightSession"
    ) -> Int {
        let next = defaults.integer(forKey: key) &+ 1
        defaults.set(next, forKey: key)
        session = next
        return next
    }

    /// The number this session is using, held so every reload within it agrees.
    ///
    /// `nonisolated(unsafe)` because it is written from the main actor only — once
    /// at launch, and again whenever someone presses the hero's refresh — and read
    /// everywhere else. The alternative is threading a number through four layers
    /// that have no other use for it.
    public nonisolated(unsafe) private(set) static var session = 0

    /// Moves to the next set of titles without restarting the app.
    ///
    /// The rotation was tied to launch, which meant the only way to see the rest of
    /// the pool was to quit and reopen — a strange thing to ask of someone who just
    /// wants a different backdrop. Same mechanism, reachable.
    @discardableResult
    public static func advanceSession(
        in defaults: UserDefaults = .standard, key: String = "spotlightSession"
    ) -> Int {
        beginSession(in: defaults, key: key)
    }

    /// Interleaves per-library candidates, best-rated first within each library.
    ///
    /// Round-robin by rank rather than by score: taking each library's number one,
    /// then each library's number two, guarantees that a library with a single
    /// eligible title still gets a slot, which a global sort by rating does not.
    ///
    /// Pure, so the mixing rule is testable without a database — the query above it
    /// is the only part that needs one.
    /// - Parameter day: the session number, from `beginSession`. Each library's
    ///   ranking is rotated by it before the round-robin, so a different slice of
    ///   the pool is featured each time the app opens and the whole pool comes
    ///   round over several sessions. Deterministic rather than random on purpose:
    ///   within one session the hero must be the same after a refresh or a sync —
    ///   a spotlight that reshuffles while you are looking at it is one you cannot
    ///   come back to. Zero keeps the plain best-first order, which is what the
    ///   tests assert.
    public static func mix(
        _ groups: [[LibraryEntry]], limit: Int = length, day: Int = 0
    ) -> [LibraryEntry] {
        guard limit > 0 else { return [] }
        let depth = groups.map(\.count).max() ?? 0
        var picked: [LibraryEntry] = []
        var seen: Set<String> = []

        for rank in 0..<depth {
            for group in groups where rank < group.count {
                // Rotated per library rather than by one global offset: the
                // libraries have wildly different pool sizes on a real server —
                // 24,000 anime against 400 films — and one offset would run off the
                // end of the short ones and feature the same films all week.
                let shift = day.quotientAndRemainder(dividingBy: group.count).remainder
                let entry = group[(rank + shift + group.count) % group.count]
                // A title can sit in two libraries — "Movies" and "Anime Movies"
                // both hold the Ghibli films on plenty of servers — and the same
                // backdrop twice in a six-slot rotation is the one outcome this
                // whole mechanism should avoid.
                guard seen.insert(entry.id).inserted else { continue }
                picked.append(entry)
                if picked.count == limit { return picked }
            }
        }
        return picked
    }
}

public extension LibraryRepository {

    /// One library's best unwatched titles, highest community rating first.
    ///
    /// Carries the same exclusions as `entries` — no extras, no hidden collections —
    /// plus three of its own:
    ///
    /// * a community rating must exist, because the sort is meaningless without one
    ///   and SQLite would otherwise hand back the unrated tail on a thin library;
    /// * nothing already played, which is the "exclude things already watched" half
    ///   of the rule, done in SQL before LIMIT for the reason `entries` documents;
    /// * *wide* artwork must exist. A hero with no backdrop is a grey slab with a
    ///   title on it, and no amount of good rating makes that worth the top third of
    ///   the home screen. This is the filter that does the most work in practice.
    func spotlightCandidates(
        libraryId: String,
        limit: Int = Spotlight.length
    ) async throws -> [LibraryEntry] {
        try await database.writer.read { [serverId] db in
            let request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("libraryId") == libraryId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                // Titles, not episodes: a hero is about the show. Box sets are out
                // too — a collection has no runtime, no rating worth trusting and
                // nothing for the Play button to promise.
                .filter([JellyfinItem.ItemType.movie, .series].map(\.rawValue)
                    .contains(Column("type")))
                .filter(Column("communityRating") != nil)
                .filter(sql: "(item.backdropTag IS NOT NULL OR item.thumbTag IS NOT NULL)")
                .filter(sql: "NOT EXISTS (SELECT 1 FROM userData "
                           + "WHERE userData.itemId = item.id AND userData.played = 1)")
                .including(optional: ItemRecord.userDataAssociation)
                // Rating first, then newest: without the tiebreak a shelf of 8.0s
                // comes back in whatever order the table happens to hold them, and
                // the hero would reshuffle between launches for no visible reason.
                .order(Column("communityRating").desc, Column("dateCreated").desc)
                .limit(limit)
            return try LibraryEntry.fetchAll(db, request)
        }
    }
}

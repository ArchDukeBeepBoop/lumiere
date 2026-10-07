import Foundation
import LumiereKit

/// One genre card on the home screen.
///
/// Carries its own artwork rather than a name the card would have to go and
/// resolve: a card that fetched on appearance would fire a query per tile every
/// time the row scrolled back into view, and the whole point of building these
/// with the shelves is that the home screen makes its database calls once.
struct GenreCardItem: Identifiable, Hashable {
    let name: String
    /// How many films and shows carry this genre. Shown on the card, and the
    /// reason a genre with two items never earns a slot.
    let count: Int
    /// The titles whose artwork the card is drawn from, newest first.
    let artwork: [LibraryEntry]

    var id: String { name }
}

extension HomeModel {

    /// Genres worth a card, in an order a person would expect.
    ///
    /// Alphabetical would open the row with Action, Adventure, Animation, Anime —
    /// four near-identical words before anything else — so the well-known genres
    /// lead in a fixed order and the rest follow alphabetically behind them. This
    /// is a presentation choice about a row that shows ten of maybe sixty genres,
    /// not a claim that these matter more.
    static let preferredGenres = [
        "Action", "Comedy", "Drama", "Anime", "Animation", "Science Fiction",
        "Thriller", "Adventure", "Horror", "Documentary", "Fantasy", "Romance",
        "Family", "Crime", "Mystery",
    ]

    /// How many cards the row holds.
    ///
    /// Was ten, which is most of where "incomplete" came from: `preferredGenres`
    /// alone is fifteen names long, so on an ordinary library the row filled up
    /// with well-known categories before a single one of the library's *own*
    /// genres could reach it. Eighteen is enough that the preferred list can be
    /// satisfied and still leave room behind it.
    ///
    /// Affordable because the card got cheaper rather than because the budget
    /// grew: a mosaic of three third-width posters decodes slightly fewer pixels
    /// than the one full-width backdrop it replaced, so eighteen cards cost under
    /// twice what ten of the old ones did.
    static let genreCardLimit = 18

    /// The fewest titles a genre needs before it earns a card.
    ///
    /// A genre with one title behind it is usually a metadata artefact — a single
    /// film tagged "Talk Show" — and a card promising a section that turns out to
    /// hold one poster is worse than no card. Was four, which was set while the
    /// counts were inflated by substring matching; against the exact counts
    /// `genreTallies` returns, four was quietly discarding real categories.
    static let minimumGenreCount = 2

    /// Builds the genre row.
    ///
    /// One catalogue query plus one artwork query per card drawn, against the
    /// local cache and never the server — genres are a cached column, so this
    /// stays correct offline, which the sidebar-driven browse it replaces did not.
    /// The catalogue used to be a scan followed by a `COUNT(*)` per genre, so
    /// showing more cards meant more queries; now it does not.
    /// How deep the artwork window reaches.
    ///
    /// 1500 rows covers every genre this library shows a card for; the ones it
    /// misses are one- and two-title artefacts far outside the top eighteen, and
    /// they fall back to their own query below.
    static let genreWindow = 1_500

    func loadGenres(generation: Int) async {
        let tallies = (try? await repository.genreTallies(
            types: LibraryRepository.topLevelTypes
        )) ?? []
        let eligible = tallies.filter { $0.count >= Self.minimumGenreCount }
        guard !eligible.isEmpty else {
            guard isCurrent(generation) else { return }
            genreCards = []
            return
        }

        // One windowed read, then bucketed in Swift — not one query per card.
        //
        // The per-card query could use no index: `extraType IS NULL` matches
        // essentially every row, the genre predicate is a `LIKE` over a newline-
        // joined column, and the `dateCreated` sort is a temp b-tree over whatever
        // survives. Measured on the real library that is 18 of those for 1.02s,
        // against 0.058s for the single query below — and it was the largest item on
        // the whole home load. Same shape `genreTallies` already uses to avoid a
        // `COUNT` per genre.
        //
        // The window is the newest rows carrying any genre at all; a card only needs
        // three, and the newest three in a genre are almost always inside it.
        let window = (try? await repository.entries(
            types: LibraryRepository.topLevelTypes,
            sort: .dateAdded, descending: true, limit: Self.genreWindow
        )) ?? []
        guard isCurrent(generation) else { return }

        var byGenre: [String: [LibraryEntry]] = [:]
        for entry in window {
            guard let genres = entry.item.genres else { continue }
            for genre in Set(genres.components(separatedBy: "\n")) where !genre.isEmpty {
                // Three is what the mosaic draws. Stopping at three keeps this a
                // bucketing pass rather than a second copy of the whole window.
                if byGenre[genre, default: []].count < 3 {
                    byGenre[genre, default: []].append(entry)
                }
            }
        }

        var cards: [GenreCardItem] = []
        for tally in Self.ordered(eligible).prefix(Self.genreCardLimit) {
            // Per iteration, so a superseded pass abandons after one query rather
            // than eighteen. The repository is an actor, so a stale loop is not
            // merely wasted work — it holds the actor and the newer load queues
            // behind it.
            guard isCurrent(generation) else { return }
            var artwork = byGenre[tally.name] ?? []
            // The window missed this genre entirely, which happens when every title
            // in it is old. One query for that card rather than eighteen for all of
            // them — a card with no artwork draws blank, and that is the thing the
            // three-item fetch existed to prevent.
            if artwork.isEmpty {
                artwork = (try? await repository.entries(
                    types: LibraryRepository.topLevelTypes,
                    sort: .dateAdded, descending: true, limit: 3, genre: tally.name
                )) ?? []
                guard isCurrent(generation) else { return }
            }
            cards.append(
                GenreCardItem(name: tally.name, count: tally.count, artwork: artwork)
            )
        }
        guard isCurrent(generation) else { return }
        genreCards = cards
    }

    /// Well-known genres in their fixed order, then everything else biggest
    /// first.
    ///
    /// The remainder used to be alphabetical, which let the letter A decide the
    /// tail of the row rather than what the library holds — "Adult Animation"
    /// ahead of a 900-title category. `genreTallies` already returns count order,
    /// so this only has to lift the preferred names out and leave the rest.
    static func ordered(_ tallies: [GenreTally]) -> [GenreTally] {
        let byName = Dictionary(
            tallies.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let preferred = preferredGenres.compactMap { byName[$0] }
        let preferredNames = Set(preferred.map(\.name))
        return preferred + tallies.filter { !preferredNames.contains($0.name) }
    }
}

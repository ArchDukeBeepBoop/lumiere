import Foundation
import LumiereKit

/// The Top 10 rows: films, television, and anime.
///
/// Ranked by the community rating Jellyfin scrapes, which on this server is TMDB's
/// — so it is TMDB metadata, arriving through the library rather than through an
/// API call, and it needs no key and no network.
///
/// **What that ranking cannot do is weight by how many people voted.** Jellyfin's
/// item payload carries `CommunityRating` and no vote count — checked, it is the
/// only rating-shaped field there is — so a title rated 10.0 by three people
/// outranks one rated 8.7 by forty thousand.
///
/// `settlingPeriod` is the one correction the local data supports. Measured on this
/// library, the unfiltered series row read *Aeronautica Imperialis 10.0, Teach You a
/// Lesson 9.4* — both released within the last six months, both a few dozen votes
/// deep. Excluding them gives Breaking Bad, Frieren, Skyline and Chernobyl, which is
/// what a Top 10 is supposed to look like. It costs the row genuinely good new
/// releases, and that is the trade: Recently Added is two shelves up, and this row
/// is the one that claims to be a ranking.
///
/// The real fix is TMDB's own API, which returns vote counts and its own popularity
/// ranking. Until a key is there, this is the best the local data supports, and the
/// rows say what they are ranked by.
extension HomeModel {

    /// How many titles a Top 10 row shows.
    static let topCount = 10

    /// How deep the pool is that `refreshTop` rotates through.
    ///
    /// Five rows' worth. Deep enough that pressing refresh keeps finding titles you
    /// had not seen, shallow enough that it never wanders into the unrated middle of
    /// the library where the ordering stops meaning anything.
    static let topPool = 50

    /// How long a rating is given to settle before the row will trust it.
    ///
    /// Six months. Long enough that the votes stop being only the people who were
    /// waiting for it, short enough that a year-old title is eligible.
    static let settlingPeriod: TimeInterval = 180 * 24 * 60 * 60

    /// The item types each row ranks.
    ///
    /// Anime takes both at once — an anime film belongs beside an anime series far
    /// more than beside live-action cinema.
    static func types(for kind: LibraryKinds.Kind) -> [JellyfinItem.ItemType] {
        switch kind {
        case .films: return [.movie]
        case .series: return [.series]
        case .anime: return [.movie, .series]
        }
    }

    func loadTop(generation: Int, libraries: [LibraryRecord]) async {
        // Sequential rather than `async let`: the repository is an actor, so three
        // concurrent calls serialise on it anyway and only cost three suspensions
        // to arrive at the same place.
        var loaded: [LibraryKinds.Kind: [LibraryEntry]] = [:]
        for kind in LibraryKinds.Kind.allCases {
            loaded[kind] = await topEntries(kind: kind, libraries: libraries)
        }
        guard isCurrent(generation) else { return }
        topFilms = loaded[.films] ?? []
        topSeries = loaded[.series] ?? []
        topAnime = loaded[.anime] ?? []
    }

    /// Moves one row to the next slice of its pool.
    ///
    /// One row, not all three. The offset used to be shared, so pressing Refresh on
    /// Top 10 Films moved the anime and television rows underneath it as well —
    /// three lists changing at a press aimed at one, which reads as the button
    /// having done something wrong rather than something extra.
    ///
    /// The same idea as the hero's refresh: rather than re-querying for the same ten
    /// titles, the offset moves and wraps, so the button always changes what is on
    /// screen rather than sometimes doing nothing.
    func refreshTop(_ kind: LibraryKinds.Kind) async {
        let offset = ((topOffsets[kind] ?? 0) + Self.topCount) % Self.topPool
        topOffsets[kind] = offset
        let entries = await topEntries(kind: kind, libraries: lastLibraries)
        switch kind {
        case .films: topFilms = entries
        case .series: topSeries = entries
        case .anime: topAnime = entries
        }
    }

    private func topEntries(
        kind: LibraryKinds.Kind,
        libraries: [LibraryRecord]
    ) async -> [LibraryEntry] {
        let types = Self.types(for: kind)
        // The owner's choice where one has been made, the guess otherwise. See
        // `TopShelfSelection` for why the guess alone was not enough.
        let ids = TopShelfSelection.libraryIds(
            for: kind, in: libraries, excluding: privateLibraryIds
        )
        // No matching library means no row, rather than a row silently drawn from
        // everything — which is what an empty `libraryIds` would mean to the query.
        guard !ids.isEmpty else { return [] }

        let pool = (try? await repository.entries(
            types: types, sort: .rating, descending: true,
            libraryIds: ids,
            limit: Self.topPool,
            releasedBefore: Date().addingTimeInterval(-Self.settlingPeriod),
            projection: .tile
        )) ?? []
        guard !pool.isEmpty else { return [] }

        // Wraps rather than running off the end, so the last slice is a full row
        // made of the pool's start rather than three titles and a gap.
        let start = min(topOffsets[kind] ?? 0, max(0, pool.count - 1))
        let wrapped = Array(pool[start...] + pool[..<start])
        return Array(wrapped.prefix(Self.topCount))
    }
}

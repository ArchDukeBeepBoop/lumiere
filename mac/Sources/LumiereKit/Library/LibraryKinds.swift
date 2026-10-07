import Foundation

/// Sorting a server's libraries into the three the Top 10 rows are about.
///
/// Pure, and a separate type, because it is a judgement call with no right answer
/// in the data. Jellyfin has one collection type for television and does not
/// distinguish an anime library from any other — the distinction is the owner's,
/// expressed in what they named the folder, and this is the only place that guess
/// is made. A test can then pin it.
public enum LibraryKinds {

    /// What the row is ranking.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// Films, excluding anime films.
        case films
        /// Television, excluding anime.
        case series
        /// Both at once. Anime films belong with anime series far more than they
        /// belong with live-action cinema, which is why this is the one kind that
        /// does not split by item type.
        case anime
    }

    /// Whether a library's *name* marks it as anime.
    ///
    /// The name, because nothing else can. `collectionType` is `tvshows` for an
    /// anime library exactly as it is for a live-action one, and reading it off the
    /// items would mean deciding per title what an anime is — a much larger and much
    /// worse guess than reading the label the owner already wrote.
    ///
    /// Substring rather than equality so "Anime", "Anime Movies", "Anime (Dubbed)"
    /// and "Old Anime" all match, and case-insensitive because folder names are not
    /// consistent about it.
    public static func isAnime(_ name: String) -> Bool {
        name.range(of: "anime", options: .caseInsensitive) != nil
    }

    /// The libraries a kind draws from.
    ///
    /// Only libraries Jellyfin has classified. A folder library — no
    /// `collectionType`, so nothing scraped it — has no community ratings to rank by,
    /// and including one would put unrated home video in a chart of the best films.
    ///
    /// `excluded` is for the private ones, and it is passed even when they are
    /// currently on screen. That is the correction rather than a nicety: the shelf
    /// used to lean on the ordinary privacy filter, which is a statement about *right
    /// now*, so revealing a private library moved it into the charts. On this server
    /// that library is `tvshows` with a name that says nothing about anime, so the
    /// Top 10 Series row filled with twelve titles rated a clean 10.0 by a handful of
    /// people and television vanished from its own chart. Revealing a library means
    /// "let me browse it", never "rank it on my home screen".
    public static func libraryIds(
        for kind: Kind,
        in libraries: [(id: String, name: String, collectionType: String?)],
        excluding excluded: Set<String> = []
    ) -> [String] {
        libraries.compactMap { library in
            guard !excluded.contains(library.id) else { return nil }
            let anime = isAnime(library.name)
            switch kind {
            case .films:
                guard !anime, library.collectionType == "movies" else { return nil }
            case .series:
                guard !anime, library.collectionType == "tvshows" else { return nil }
            case .anime:
                guard anime, library.collectionType == "movies"
                        || library.collectionType == "tvshows" else { return nil }
            }
            return library.id
        }
    }
}

public extension LibraryKinds {
    /// The same, from the records the app actually holds.
    static func libraryIds(
        for kind: Kind,
        in libraries: [LibraryRecord],
        excluding excluded: Set<String> = []
    ) -> [String] {
        libraryIds(
            for: kind,
            in: libraries.map { ($0.id, $0.name, $0.collectionType) },
            excluding: excluded
        )
    }
}

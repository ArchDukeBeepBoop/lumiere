import Foundation

/// One block of the home screen, in the order it is drawn.
///
/// The home screen used to be a fixed sequence written into each layout's body:
/// spotlight, quick links, libraries, Continue Watching, genres, Next Up, the three
/// Top 10 rows, then one Latest row per library in whatever order the server
/// happened to return them. That is a reasonable default and a bad rule — which row
/// you want first depends on what you use the app for, and someone who never
/// watches films wants the anime shelf above Top 10 Films rather than four screens
/// below it.
///
/// The per-library Latest rows are cases here too, not one lumped "Latest" block.
/// They are the majority of the shelves on screen and the ones most worth moving;
/// treating them as a single unit would leave the actual request unanswered.
public enum HomeSection: Hashable, Sendable, Identifiable {
    case spotlight
    case quickLinks
    case libraries
    case continueWatching
    case genres
    case nextUp
    /// Series with only a few episodes to go. See
    /// `LibraryRepository.nearlyFinishedSeries` for why this is not Next Up.
    case finishSeason
    /// Started long ago, never resumed. See `forgottenEntries`.
    case forgotten
    /// The next film in each film series under way. See `seriesNextUp`.
    case continueSeries
    /// Related titles, keyed to the last thing watched.
    case becauseYouWatched
    /// Everything newly added, across every library. Drawn by the Hero layout;
    /// Classic says the same thing one library at a time with its Latest rows.
    case recentlyAdded
    case topFilms
    case topSeries
    case topAnime
    /// The "Latest <library>" row for one library.
    case latest(libraryId: String)

    /// Whether this is a *shelf* — a row of titles — as opposed to the furniture
    /// around them.
    ///
    /// The seven-shelf cap counts these and nothing else. The spotlight is the
    /// hero, Quick Links is a row of buttons and Libraries is how you leave the
    /// home screen; capping those would shorten the page by removing the parts
    /// that are not the problem. See `HomeShelfCap`.
    public var isShelf: Bool {
        switch self {
        case .spotlight, .quickLinks, .libraries: return false
        default: return true
        }
    }

    /// Stable across launches, because it is what gets written to preferences.
    ///
    /// Spelled out rather than derived from the case name: `String(describing:)`
    /// would tie a stored preference to Swift's reflection format, and renaming a
    /// case would silently reset everyone's home screen.
    public var id: String {
        switch self {
        case .spotlight: return "spotlight"
        case .quickLinks: return "quickLinks"
        case .libraries: return "libraries"
        case .continueWatching: return "continueWatching"
        case .genres: return "genres"
        case .nextUp: return "nextUp"
        case .finishSeason: return "finishSeason"
        case .forgotten: return "forgotten"
        case .continueSeries: return "continueSeries"
        case .becauseYouWatched: return "becauseYouWatched"
        case .recentlyAdded: return "recentlyAdded"
        case .topFilms: return "topFilms"
        case .topSeries: return "topSeries"
        case .topAnime: return "topAnime"
        case .latest(let libraryId): return "latest:\(libraryId)"
        }
    }

    public init?(id: String) {
        if id.hasPrefix("latest:") {
            let libraryId = String(id.dropFirst("latest:".count))
            guard !libraryId.isEmpty else { return nil }
            self = .latest(libraryId: libraryId)
            return
        }
        switch id {
        case "spotlight": self = .spotlight
        case "quickLinks": self = .quickLinks
        case "libraries": self = .libraries
        case "continueWatching": self = .continueWatching
        case "genres": self = .genres
        case "nextUp": self = .nextUp
        case "finishSeason": self = .finishSeason
        case "forgotten": self = .forgotten
        case "continueSeries": self = .continueSeries
        case "becauseYouWatched": self = .becauseYouWatched
        case "recentlyAdded": self = .recentlyAdded
        case "topFilms": self = .topFilms
        case "topSeries": self = .topSeries
        case "topAnime": self = .topAnime
        default: return nil
        }
    }

    /// What the settings list calls it. A Latest row is named by its library, which
    /// the caller supplies — this type holds an id, not a library.
    public func title(libraryName: (String) -> String?) -> String {
        switch self {
        case .spotlight: return "Spotlight"
        case .quickLinks: return "Quick Links"
        case .libraries: return "Your Libraries"
        case .continueWatching: return "Continue Watching"
        case .genres: return "Genres"
        case .nextUp: return "Next Up"
        case .finishSeason: return "Finish the Season"
        case .forgotten: return "Forgotten"
        case .continueSeries: return "Continue the Series"
        case .becauseYouWatched: return "Because You Watched"
        case .recentlyAdded: return "Recently Added"
        case .topFilms: return "Top 10 Films"
        case .topSeries: return "Top 10 Series"
        case .topAnime: return "Top 10 Anime"
        case .latest(let libraryId):
            return "Latest \(libraryName(libraryId) ?? "Library")"
        }
    }

    /// Whether this row exists independently of the library list.
    public var isFixed: Bool {
        if case .latest = self { return false }
        return true
    }
}

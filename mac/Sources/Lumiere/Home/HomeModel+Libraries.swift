import Foundation
import LumiereKit

/// One library card on the home screen.
///
/// The sibling of `GenreCardItem`, and built the same way for the same reason:
/// the card carries the artwork it will draw rather than a library id it would
/// have to resolve on appearance. A card that fetched when it appeared would fire
/// a query per tile every time the row scrolled back, and the whole point of
/// building these alongside the shelves is that the home screen queries once.
struct LibraryCardItem: Identifiable, Hashable {
    /// Kept whole rather than reduced to an id and a name: opening a library needs
    /// the record — the shell decides between the grid, the folder browser and the
    /// live server browser from `collectionType` — and it is the same value the
    /// sidebar row hands over, which is what keeps the two routes identical.
    let library: LibraryRecord
    /// How many titles the local cache holds for this library. Zero is a real
    /// answer for music and playlists, which are never synced; see `subtitle`.
    let count: Int
    /// The titles the card's artwork is drawn from, newest first.
    let artwork: [LibraryEntry]

    var id: String { library.id }
    var name: String { library.name }

    /// The card's second line.
    ///
    /// Music and playlist libraries are deliberately never synced — recursing one
    /// pulls every track — so their cached count is zero for a library that may
    /// hold ten thousand songs. Printing "0 titles" there would be a lie the user
    /// can see through, so those cards say what they are instead.
    var subtitle: String {
        if count > 0 { return "\(count) titles" }
        return library.holdsPlayableVideo
            ? "Browse"
            : LibraryGlyph.label(for: library.collectionType)
    }
}

/// What a library looks and reads like, by what Jellyfin says it holds.
///
/// One switch rather than two. The sidebar had this mapping inline; the library
/// cards need the same glyph for the same library, and two copies of a lookup
/// like this is how the sidebar and the home screen end up disagreeing about
/// what a collection is.
enum LibraryGlyph {

    static func name(for collectionType: String?) -> String {
        switch collectionType {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        case "musicvideos": return "music.note.tv"
        case "playlists": return "music.note.list"
        case "boxsets": return "square.stack"
        case "homevideos": return "video"
        case "books": return "book"
        case "photos": return "photo"
        default: return "folder"
        }
    }

    /// A human name for the kind, used where a count would be misleading.
    static func label(for collectionType: String?) -> String {
        switch collectionType {
        case "music": return "Music"
        case "musicvideos": return "Music videos"
        case "playlists": return "Playlists"
        case "boxsets": return "Collections"
        case "photos": return "Photos"
        case "books": return "Books"
        default: return "Browse"
        }
    }
}

extension HomeModel {

    /// How many candidate titles a card keeps for its artwork.
    ///
    /// The card draws one image. The extras exist because a title often has no
    /// poster of its own — common on anime and on the loose folders Jellyfin
    /// never identified — and a blank card is worse than a card showing the next
    /// candidate down. Eight rather than four, because the best-rated title in a
    /// library is more likely than the newest to be an old one whose artwork
    /// nobody ever scraped.
    static let libraryCardArtworkDepth = 8

    /// Builds the library row.
    ///
    /// Every library gets a card, including the ones with no shelf below them.
    /// That is the difference between this and `libraryShelves`, which drops empty
    /// libraries because a titled row over nothing reads as a failed load: this
    /// row is *navigation*, and a library missing from it is a library you can no
    /// longer reach now that the sidebar starts hidden.
    ///
    /// Two queries per library: how much is in it, and what best represents it.
    func loadLibraryCards(libraries: [LibraryRecord], generation: Int) async {
        var cards: [LibraryCardItem] = []
        for library in libraries {
            // See the same guard in HomeModel+Genres: the actor is serial, so a
            // stale pass delays the live one rather than just wasting itself.
            guard isCurrent(generation) else { return }
            let count = (try? await repository.count(
                types: LibraryRepository.topLevelTypes, libraryId: library.id
            )) ?? 0

            // The best-rated titles, not the newest.
            //
            // The card used to take whatever the library's own shelf had at the
            // front, which is the most recently added thing — so the picture for
            // "Anime" changed every time anything was added, and what it changed
            // to was as likely to be a one-episode oddity as anything worth
            // representing a library by. Rating is both a better answer and a
            // stable one: it is a statement about the library rather than about
            // last week.
            //
            // Descending community rating, which the grid's own "Rating" sort
            // uses, so the card shows what that page would put first.
            var artwork = (try? await repository.entries(
                types: LibraryRepository.topLevelTypes,
                sort: .rating, descending: true, libraryId: library.id,
                limit: Self.libraryCardArtworkDepth,
                // The Top 10 row's own correction, for the same reason and with
                // the same trade — see `HomeModel.settlingPeriod`. Jellyfin
                // carries no vote count, so a title rated 10.0 by three people
                // outranks one rated 8.7 by forty thousand. Unfiltered, this
                // picked "Gigantic Formula" to stand for a library holding
                // Frieren, and "Lessons Learned" to stand for one holding
                // Breaking Bad.
                releasedBefore: Date().addingTimeInterval(-Self.settlingPeriod)
            )) ?? []
            if artwork.isEmpty {
                // A folder library — loose video files rather than films or
                // series — has nothing the type filter above matches, and nothing
                // carries a rating either. Newest is the only order left.
                artwork = (try? await repository.entries(
                    sort: .dateAdded, descending: true, libraryId: library.id,
                    limit: Self.libraryCardArtworkDepth
                )) ?? []
            }

            cards.append(LibraryCardItem(
                library: library,
                count: count,
                artwork: Array(artwork.prefix(Self.libraryCardArtworkDepth))
            ))
        }
        // After the awaits above, so a superseded load cannot repaint the row.
        guard isCurrent(generation) else { return }
        libraryCards = cards
    }
}

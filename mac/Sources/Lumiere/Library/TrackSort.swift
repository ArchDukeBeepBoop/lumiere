import Foundation
import LumiereKit

/// How a track list is ordered.
///
/// Sorted by the *server*, not by what happens to be loaded. A music library is
/// paged as you scroll — none of it is cached, by design — so sorting the rows in
/// hand would order the first two hundred tracks and leave the rest arriving in the
/// old order behind them. Jellyfin takes a sort field, so asking it is both correct
/// across the whole library and free.
///
/// The set is Apple Music's: the four columns the list already draws, plus the two
/// it does not have room for but everyone sorts by anyway.
enum TrackSort: String, CaseIterable, Identifiable {
    case title, artist, album, duration, dateAdded, plays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .duration: return "Time"
        case .dateAdded: return "Date Added"
        case .plays: return "Plays"
        }
    }

    /// Jellyfin's own field names.
    ///
    /// The compound ones matter: sorting by artist alone interleaves every album
    /// that artist made, so it carries album and track number behind it, which is
    /// what "sort by artist" means to anyone who has used a music app.
    var sortBy: [String] {
        switch self {
        case .title: return ["SortName"]
        case .artist: return ["AlbumArtist", "Album", "ParentIndexNumber", "IndexNumber"]
        case .album: return ["Album", "ParentIndexNumber", "IndexNumber"]
        case .duration: return ["Runtime"]
        case .dateAdded: return ["DateCreated"]
        case .plays: return ["PlayCount"]
        }
    }

    /// Which direction reads as "first" for this field.
    ///
    /// Names ascend; everything else is more useful newest- or largest-first, which
    /// is what every music app does with Date Added and Plays.
    var defaultAscending: Bool {
        switch self {
        case .title, .artist, .album: return true
        case .duration, .dateAdded, .plays: return false
        }
    }

    /// Whether the A–Z rail can point into a list in this order.
    ///
    /// Only name order is monotonic by first letter. In album order "Africa" comes
    /// after "Zombie" and back again, so a rail would jump to a letter and land
    /// somewhere arbitrary — worse than having no rail, because it looks like it
    /// worked.
    var supportsAlphabetRail: Bool { self == .title }
}

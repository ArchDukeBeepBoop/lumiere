import Foundation

public extension LibraryEntry {
    /// Whether Identify… can match this to a listing: a show, a season, a
    /// film or a loose video. An episode is identified through its show, and
    /// a collection has its own film-series Identify.
    var isIdentifiable: Bool {
        switch item.itemType {
        case .series, .season, .movie, .video: return true
        default: return false
        }
    }
}

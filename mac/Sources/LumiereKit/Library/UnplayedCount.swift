import Foundation

/// How many things under a season or a show are still unwatched.
///
/// The number a card draws its corner from. It arrives from the server, and
/// until now only from the server: marking a season watched wrote `played`
/// on the season and on every episode under it, and left the count saying
/// what it said before — so the episodes ticked over and the season poster
/// above them did not. The local write has everything it needs to keep the
/// count honest; it simply never did.
public enum UnplayedCount {

    /// Whether an item's watched state is its own, or a summary of what is
    /// under it. A film is watched or not; a season is a count.
    public static func isContainer(_ type: JellyfinItem.ItemType?) -> Bool {
        switch type {
        case .series, .season, .boxSet, .folder, .collectionFolder:
            return true
        default:
            return false
        }
    }

    /// Whether an item counts towards a container's unwatched total. Extras
    /// do not: a creditless opening left unwatched should not keep a season
    /// marked unfinished.
    public static func counts(type: JellyfinItem.ItemType?, extraType: String?) -> Bool {
        guard extraType == nil else { return false }
        switch type {
        case .movie, .episode, .video:
            return true
        default:
            return false
        }
    }
}

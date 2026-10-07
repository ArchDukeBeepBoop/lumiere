import Foundation
import GRDB

/// One of the files Jellyfin folded into a single item.
///
/// Jellyfin's scanner treats several video files in one folder as alternate versions
/// of one movie, so `/Items` returns a single row and the rest of the files exist
/// only as extra `MediaSources` hanging off it. In a scraped library that is usually
/// right — two rips of the same film *are* one film. In a folder library it is
/// exactly wrong: the folder is what the owner organised and each file in it is a
/// separate thing they put there.
///
/// Measured on the `3D` library: every `Clips/Compilations/…` folder came back with
/// one item, while `Clips/Lantern Road` came back with seven, because Lantern Road's
/// filenames differed enough that the server left them alone.
public struct ItemVersionRecord: Codable, Sendable, Hashable,
                                FetchableRecord, PersistableRecord {

    public static let databaseTableName = "itemVersion"

    public var itemId: String
    /// Jellyfin's id for this particular file, which is what playback needs to pick
    /// it out of the item it was merged into.
    public var sourceId: String
    public var path: String?
    public var name: String?

    public init(itemId: String, sourceId: String, path: String?, name: String?) {
        self.itemId = itemId
        self.sourceId = sourceId
        self.path = path
        self.name = name
    }
}

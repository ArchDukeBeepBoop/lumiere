import Foundation

/// Matroska segment links, as the server resolved them.
///
/// A fansub release ships the opening and ending once, as their own files,
/// and each episode's ordered chapters borrow those ranges by segment UID.
/// The server reads the headers and resolves the UIDs to items; this is the
/// answer, which mpv turns into one timeline. See `PlaybackRequest.linkedFiles`.
public struct LinkedChapters: Decodable, Sendable {
    public struct Range: Decodable, Sendable {
        public let itemId: String?
        public let title: String?
        public let start: Double
        public let end: Double
        public let linkUid: String?
        public let resolved: Bool
        /// The borrowed file on disk, for playing from disk. See `DiskPlayback`.
        public let path: String?
        enum CodingKeys: String, CodingKey {
            case itemId = "ItemId", title = "Title", start = "Start", end = "End"
            case linkUid = "LinkUid", resolved = "Resolved", path = "Path"
        }
    }
    public let ordered: Bool
    public let ranges: [Range]
    public let unresolved: Int
    enum CodingKeys: String, CodingKey {
        case ordered = "Ordered", ranges = "Ranges", unresolved = "Unresolved"
    }

    /// The other items this one borrows from, each once, in first-use order.
    public var borrowedItemIds: [String] {
        borrowed.map(\.id)
    }

    /// The same, with each item's path on disk where the server gave one.
    public var borrowed: [(id: String, path: String?)] {
        var seen = Set<String>()
        return ranges.compactMap { range in
            guard let id = range.itemId, range.linkUid != nil, seen.insert(id).inserted
            else { return nil }
            return (id, range.path)
        }
    }
}

public extension JellyfinClient {
    func linkedChapters(itemId: String) async throws -> LinkedChapters {
        try await send(LinkedChapters.self, path: "Items/\(itemId)/LinkedChapters")
    }
}

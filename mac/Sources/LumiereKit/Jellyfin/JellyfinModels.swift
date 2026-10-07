import Foundation

/// Jellyfin's `BaseItemDto` is enormous — well over a hundred fields. Lumiere
/// decodes only what it displays or decides with. Adding a field here is cheap;
/// decoding the whole DTO is not, and it is the kind of thing that quietly costs
/// tens of megabytes across a large library sync.
public struct JellyfinItem: Codable, Sendable, Identifiable, Hashable {

    public let id: String
    public let name: String
    public let type: ItemType
    public let serverId: String?

    // Hierarchy
    public let parentId: String?
    /// The library it is in, as UserViews names it. Only Lumiere's server
    /// sends it; the change feed files an item by it. See LibraryRepository+ChangeFeed.
    public var topParentId: String? = nil
    public let seriesId: String?
    public let seriesName: String?
    public let seasonId: String?
    public let seasonName: String?
    public let indexNumber: Int?
    /// "Trailer", "BehindTheScenes", "Featurette", "DeletedScene", … Present
    /// only on extras, so nil means this is real content.
    public let extraType: String?
    public let parentIndexNumber: Int?

    // Presentation
    /// The title as originally released, which Jellyfin keeps apart from `name`.
    /// Only populated on a detail fetch, and only read by the metadata editor —
    /// where showing a blank field that is not actually blank would be a trap.
    public let originalTitle: String?
    /// What the server files this under. Requested with `Fields=SortName`.
    public let sortName: String?
    public let overview: String?
    public let productionYear: Int?
    public let premiereDate: Date?
    public let dateCreated: Date?
    public let officialRating: String?
    public let communityRating: Double?
    public let criticRating: Double?
    public let genres: [String]?
    /// Keyword tags. Asked for only by the franchise grouper — a franchise keyword
    /// is the one piece of metadata that names a franchise directly, where a genre
    /// names a whole shelf.
    public let tags: [String]?
    public let taglines: [String]?
    public let studios: [NamedIdentity]?
    public let people: [Person]?

    /// 100-nanosecond ticks. Divide by 10_000_000 for seconds.
    public let runTimeTicks: Int64?

    // Artwork
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let parentBackdropImageTags: [String]?
    public let parentBackdropItemId: String?
    public let seriesPrimaryImageTag: String?

    // Music. Present on Audio and MusicAlbum items and returned by default — no
    // `Fields` entry gates them — which is why the track list can show an artist
    // and an album without a second request per row.
    public let album: String?
    public let albumArtist: String?
    /// Every credited performer, in the server's order. `albumArtist` is the one
    /// the album is filed under; these are who is actually on the track, and on a
    /// collaboration the two differ.
    public let artists: [String]?
    public let albumId: String?

    // Media
    public let mediaSources: [MediaSource]?
    public let mediaStreams: [MediaStream]?
    public let container: String?
    public let path: String?
    public let chapters: [Chapter]?

    // State
    public let userData: UserItemData?
    public let childCount: Int?
    public let recursiveItemCount: Int?
    public let isFolder: Bool?
    public let collectionType: String?
    /// This row's identity *within a playlist*, present only on items that came back
    /// from a playlist query. Not interchangeable with `id`: a playlist may hold the
    /// same track twice, so removing one of them means naming the row rather than the
    /// track. Deliberately absent from `ItemRecord` — it describes a membership, not
    /// an item, and caching it would leave it stale the moment the playlist is edited
    /// from another client.
    public let playlistItemId: String?
    /// Who this item is, according to whom — `["Tmdb": "12345"]`. Written by
    /// identify and read back by the episode-name backfill, which needs the id
    /// without the user having just identified the series in the same session.
    public let providerIds: [String: String]?

    public enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", serverId = "ServerId"
        case parentId = "ParentId", topParentId = "TopParentId", seriesId = "SeriesId", seriesName = "SeriesName"
        case seasonId = "SeasonId", seasonName = "SeasonName"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
        case extraType = "ExtraType"
        case originalTitle = "OriginalTitle", sortName = "SortName"
        case overview = "Overview", productionYear = "ProductionYear"
        case premiereDate = "PremiereDate", dateCreated = "DateCreated"
        case officialRating = "OfficialRating", communityRating = "CommunityRating"
        case criticRating = "CriticRating", genres = "Genres", taglines = "Taglines"
        case tags = "Tags"
        case studios = "Studios", people = "People", runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case mediaSources = "MediaSources", mediaStreams = "MediaStreams"
        case album = "Album", albumArtist = "AlbumArtist"
        case artists = "Artists", albumId = "AlbumId"
        case container = "Container", path = "Path", chapters = "Chapters"
        case userData = "UserData", childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount", isFolder = "IsFolder"
        case collectionType = "CollectionType"
        case playlistItemId = "PlaylistItemId"
        case providerIds = "ProviderIds"
    }

    /// Runtime in seconds, or nil when the server has not probed the file.
    public var runtimeSeconds: Double? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000_000
    }

    /// Unknown types decode as `.unknown` rather than failing the whole page —
    /// a single unrecognised item must never break a library sync.
    public enum ItemType: String, Codable, Sendable {
        case movie = "Movie"
        case series = "Series"
        case season = "Season"
        case episode = "Episode"
        case boxSet = "BoxSet"
        case collectionFolder = "CollectionFolder"
        case folder = "Folder"
        case userView = "UserView"
        case video = "Video"
        case audio = "Audio"
        case musicAlbum = "MusicAlbum"
        case musicArtist = "MusicArtist"
        case musicGenre = "MusicGenre"
        case person = "Person"
        case trailer = "Trailer"
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = ItemType(rawValue: raw) ?? .unknown
        }
    }
}

public struct NamedIdentity: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let name: String?
    public enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
}

public struct Person: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let name: String?
    public let role: String?
    public let type: String?
    public let primaryImageTag: String?
    public enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", role = "Role", type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

public struct Chapter: Codable, Sendable, Hashable {
    public let startPositionTicks: Int64?
    public let name: String?
    public let imageTag: String?
    public enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks", name = "Name", imageTag = "ImageTag"
    }

    public var startSeconds: Double {
        Double(startPositionTicks ?? 0) / 10_000_000
    }
}

/// Per-user watch state. The single most important thing to keep in sync — it is
/// the one piece of data a media client can lose that the user actually cares about.
public struct UserItemData: Codable, Sendable, Hashable {
    public let playbackPositionTicks: Int64?
    public let playCount: Int?
    public let isFavorite: Bool?
    public let played: Bool?
    public let unplayedItemCount: Int?
    public let playedPercentage: Double?
    /// When this was last watched, according to the server.
    ///
    /// The field Continue Watching should have been ordered by all along. It was
    /// simply not decoded, so the shelf fell back to when the *file* was added.
    public let lastPlayedDate: Date?

    public enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks", playCount = "PlayCount"
        case isFavorite = "IsFavorite", played = "Played"
        case unplayedItemCount = "UnplayedItemCount", playedPercentage = "PlayedPercentage"
        case lastPlayedDate = "LastPlayedDate"
    }

    public var resumeSeconds: Double {
        Double(playbackPositionTicks ?? 0) / 10_000_000
    }

    public var isInProgress: Bool {
        resumeSeconds > 0 && played != true
    }
}

/// A paged `/Items` response.
public struct ItemsResponse: Codable, Sendable {
    public let items: [JellyfinItem]
    public let totalRecordCount: Int
    public let startIndex: Int?

    public enum CodingKeys: String, CodingKey {
        case items = "Items", totalRecordCount = "TotalRecordCount", startIndex = "StartIndex"
    }
}

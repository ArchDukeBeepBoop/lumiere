import Foundation
import GRDB

/// The cached form of a `JellyfinItem`.
///
/// Deliberately flat and narrow: only what a grid, shelf or detail header needs.
/// Heavy fields — media streams, cast, chapters — are fetched live from the
/// server when you open an item, because caching them for 5,000 items would cost
/// hundreds of megabytes to save a request you make once.
public struct ItemRecord: Codable, Sendable, Identifiable, Hashable,
                          FetchableRecord, PersistableRecord {

    public static let databaseTableName = "item"

    public var id: String
    public var serverId: String
    public var type: String
    public var name: String
    public var sortName: String
    /// The searchable form: this item's name and the show it belongs to, lowercased
    /// with punctuation flattened to spaces. Stored rather than computed because
    /// searching means matching it in SQL across 44,000 rows.
    public var searchKey: String
    /// The title as originally released — the Japanese or romaji name a show is
    /// often better known by. Stored for searching, not for display.
    public var originalTitle: String?

    public var parentId: String?
    /// The library this item belongs to. Stamped during sync from the request, since
    /// Jellyfin does not report it — and kept separate from `parentId`, which is the
    /// immediate parent that season and episode lookups rely on.
    public var libraryId: String?
    public var seriesId: String?
    public var seriesName: String?
    public var seasonId: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    /// Set on extras only — trailers, featurettes, behind-the-scenes. nil is real
    /// content, which is what every library query filters on.
    public var extraType: String?

    public var overview: String?
    public var productionYear: Int?
    public var premiereDate: Date?
    public var dateCreated: Date?
    /// When the newest watchable thing under this row arrived. See the
    /// `v18_content_date` migration for why it is stored rather than computed.
    ///
    /// Written as the row's own date here and refined for series rows at the end of
    /// each library's sync, so a row inserted mid-sync never sorts as NULL.
    public var contentDate: Date?
    public var officialRating: String?
    public var communityRating: Double?
    public var runTimeTicks: Int64?
    /// Newline-joined rather than JSON: it is only ever displayed or matched with
    /// LIKE, and JSON here would mean parsing on every row of every grid.
    public var genres: String?

    public var primaryTag: String?
    public var backdropTag: String?
    public var thumbTag: String?
    public var logoTag: String?
    public var parentBackdropItemId: String?
    public var parentBackdropTag: String?
    public var seriesPrimaryImageTag: String?

    /// The file on disk, when the server reports one. Drives the
    /// "original filename" title style.
    public var path: String?

    /// The album a track belongs to, and who it is filed under.
    ///
    /// Stored rather than looked up through `parentId`, because a track's parent is
    /// only the album when you happen to be browsing inside one — a playlist, a
    /// search result or the favourites list has tracks from everywhere, and those
    /// are exactly the places a list needs to say which album a song came from.
    public var album: String?
    public var albumArtist: String?
    /// Newline-joined, like `genres`, and for the same reason: only ever displayed.
    public var artists: String?
    /// Newline-joined studio names, for the library grid's studio filter.
    public var studios: String?

    public var isFolder: Bool
    public var collectionType: String?
    public var childCount: Int?
    public var syncedAt: Date

    public init(from item: JellyfinItem, serverId: String, syncedAt: Date) {
        self.id = item.id
        self.serverId = serverId
        self.type = item.type.rawValue
        self.name = item.name
        self.sortName = Self.sortKey(for: item)
        self.originalTitle = item.originalTitle
        self.searchKey = SearchKey.key(
            name: item.name, seriesName: item.seriesName, alternative: item.originalTitle
        )
        self.parentId = item.parentId
        self.seriesId = item.seriesId
        self.seriesName = item.seriesName
        self.seasonId = item.seasonId
        self.indexNumber = item.indexNumber
        self.parentIndexNumber = item.parentIndexNumber
        self.extraType = item.extraType
        self.overview = item.overview
        self.productionYear = item.productionYear
        self.premiereDate = item.premiereDate
        self.dateCreated = item.dateCreated
        self.contentDate = item.dateCreated
        self.officialRating = item.officialRating
        self.communityRating = item.communityRating
        self.runTimeTicks = item.runTimeTicks
        self.genres = item.genres?.isEmpty == false ? item.genres?.joined(separator: "\n") : nil
        let studioNames = (item.studios ?? []).compactMap(\.name).filter { !$0.isEmpty }
        self.studios = studioNames.isEmpty ? nil : studioNames.joined(separator: "\n")
        self.primaryTag = item.imageTags?["Primary"]
        self.backdropTag = item.backdropImageTags?.first
        self.thumbTag = item.imageTags?["Thumb"]
        self.logoTag = item.imageTags?["Logo"]
        self.parentBackdropItemId = item.parentBackdropItemId
        self.parentBackdropTag = item.parentBackdropImageTags?.first
        self.seriesPrimaryImageTag = item.seriesPrimaryImageTag
        self.path = item.path ?? item.mediaSources?.first?.path
        self.album = item.album
        self.albumArtist = item.albumArtist
        self.artists = item.artists?.isEmpty == false
            ? item.artists?.joined(separator: "\n") : nil
        self.isFolder = item.isFolder ?? false
        self.collectionType = item.collectionType
        self.childCount = item.childCount
        self.syncedAt = syncedAt

        // The server's own ExtraType wins where it set one. Where it did not — which
        // on a real library is nearly always, since every row of a 44,000-item cache
        // came back null — fall back to the folder the file sits in. Without this,
        // four featurettes in a `Bonus/` folder arrive as ordinary Movie items and
        // stand in the grid next to the films they belong to.
        //
        // Episodes are exempt on purpose. They belong to a season and series the
        // server already models, and their folder names are not a reliable signal:
        // anime specials and OVAs live in `Specials/` and are content someone means
        // to watch. Classifying by path there would have hidden 519 of them from
        // their own episode lists.
        // Recovers the numbering the server misread.
        //
        // Jellyfin scans a whole filename for a number and can take the wrong one:
        // `Sky Wizards Academy - 1x01 - Fireteam E601.mkv` came back as episode 601
        // with no season at all, so it was not a child of Season 1 and the first
        // episode of the show never appeared in its own episode list. The `1x01` was
        // right there in the name the whole time.
        //
        // Only ever fills a gap. A season the server did state is left alone —
        // it has the .nfo files and the folder structure, and this has a string.
        // A missing season on an episode is the shape that actually breaks a
        // listing, so that is the only case worth stepping into.
        if self.itemType == .episode,
           self.parentIndexNumber == nil,
           let recovered = EpisodeNumbering.parse(path: self.path) {
            self.parentIndexNumber = recovered.season
            self.indexNumber = recovered.episode
            self.sortName = String(format: "%04d%04d", recovered.season, recovered.episode)
        }

        if self.extraType == nil,
           self.itemType != .episode,
           ExtrasClassifier.isExtra(path: self.path) {
            self.extraType = "Extra"
        }
    }
}


/// Watch state, kept in its own table so a progress report rewrites 8 columns
/// rather than 30.
public struct UserDataRecord: Codable, Sendable, Hashable,
                              FetchableRecord, PersistableRecord {

    public static let databaseTableName = "userData"

    public var itemId: String
    public var played: Bool
    public var playbackPositionTicks: Int64
    public var playCount: Int
    public var isFavorite: Bool
    public var playedPercentage: Double?
    public var unplayedItemCount: Int?
    public var updatedAt: Date
    /// When the server says this was last played. Nil until a sync has seen it.
    public var lastPlayedDate: Date?

    public var resumeSeconds: Double {
        Double(playbackPositionTicks) / 10_000_000
    }

    public var isInProgress: Bool {
        playbackPositionTicks > 0 && !played
    }

    public init(itemId: String, from data: UserItemData?, updatedAt: Date) {
        self.itemId = itemId
        self.played = data?.played ?? false
        self.playbackPositionTicks = data?.playbackPositionTicks ?? 0
        self.playCount = data?.playCount ?? 0
        self.isFavorite = data?.isFavorite ?? false
        self.playedPercentage = data?.playedPercentage
        self.unplayedItemCount = data?.unplayedItemCount
        self.updatedAt = updatedAt
        self.lastPlayedDate = data?.lastPlayedDate
    }
}

public struct LibraryRecord: Codable, Sendable, Identifiable, Hashable,
                             FetchableRecord, PersistableRecord {

    public static let databaseTableName = "library"

    public var id: String
    public var serverId: String
    public var name: String
    public var collectionType: String?
    public var sortIndex: Int
    public var itemCount: Int?
    /// The tag for this library's own poster in Jellyfin. See the v25 migration.
    public var primaryTag: String?

    public init(from item: JellyfinItem, serverId: String, sortIndex: Int) {
        self.id = item.id
        self.serverId = serverId
        self.name = item.name
        self.collectionType = item.collectionType
        self.sortIndex = sortIndex
        self.itemCount = nil
        self.primaryTag = item.imageTags?["Primary"]
    }

    /// Whether this library holds something Lumiere can actually play.
    ///
    /// Music and playlists are excluded: syncing a music library recursively pulls
    /// in every track, which is unbounded work and unbounded cache for a video
    /// player that cannot play one of them. A nil collectionType is a mixed folder,
    /// which usually does hold video, so it stays in.
    /// Whether this library is better browsed as folders than as a metadata grid.
    ///
    /// A nil or mixed collectionType means Jellyfin did not identify the contents as
    /// movies or shows — the "3D" and "My Videos" case — so there is no metadata for a
    /// grid to arrange, and the folders the user made are the only structure there is.
    public var prefersFolderBrowsing: Bool {
        switch collectionType {
        case nil, "", "homevideos", "mixed": return true
        default: return false
        }
    }

    public var holdsPlayableVideo: Bool {
        switch collectionType {
        case "music", "musicvideos", "playlists", "books", "photos": return false
        default: return true
        }
    }
}

/// An item plus its watch state, which is what every view actually wants.
public struct LibraryEntry: Sendable, Identifiable, Hashable, FetchableRecord, Decodable {
    public var item: ItemRecord
    public var userData: UserDataRecord?

    public var id: String { item.id }

    /// Explicit because the synthesised `Decodable` initialiser otherwise
    /// suppresses the memberwise one, which views and tests both need.
    public init(item: ItemRecord, userData: UserDataRecord?) {
        self.item = item
        self.userData = userData
    }

    /// 0…1, or nil when nothing has been watched. Drives the gold progress bar.
    public var progress: Double? {
        guard let userData, userData.isInProgress,
              let runtime = item.runtimeSeconds, runtime > 0 else { return nil }
        return min(1, max(0, userData.resumeSeconds / runtime))
    }

    public var remainingText: String? {
        guard let userData, userData.isInProgress,
              let runtime = item.runtimeSeconds else { return nil }
        let remaining = max(0, runtime - userData.resumeSeconds)
        let minutes = Int(remaining / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m left"
        }
        return "\(minutes)m left"
    }
}

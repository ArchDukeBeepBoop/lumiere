import Foundation

/// Building cache rows from something other than a Jellyfin payload.
///
/// `ItemRecord` and `LibraryRecord` each declare an initialiser that takes a
/// `JellyfinItem`, which suppresses Swift's memberwise one — reasonable when the
/// server was the only source a row could have. A folder on this Mac is now
/// another, so both need a way in that does not involve inventing a fake DTO.
///
/// Everything the server would have filled in is left nil rather than guessed.
/// A loose file has no rating, no overview and no artwork tags, and writing
/// plausible-looking values for them is how a library starts lying.
public extension ItemRecord {

    init(
        id: String,
        serverId: String,
        type: String,
        name: String,
        sortName: String,
        searchKey: String,
        isFolder: Bool,
        syncedAt: Date
    ) {
        self.id = id
        self.serverId = serverId
        self.type = type
        self.name = name
        self.sortName = sortName
        self.searchKey = searchKey
        self.originalTitle = nil
        self.parentId = nil
        self.libraryId = nil
        self.seriesId = nil
        self.seriesName = nil
        self.seasonId = nil
        self.indexNumber = nil
        self.parentIndexNumber = nil
        self.extraType = nil
        self.overview = nil
        self.productionYear = nil
        self.premiereDate = nil
        self.dateCreated = nil
        self.officialRating = nil
        self.communityRating = nil
        self.runTimeTicks = nil
        self.genres = nil
        self.primaryTag = nil
        self.backdropTag = nil
        self.thumbTag = nil
        self.logoTag = nil
        self.parentBackdropItemId = nil
        self.parentBackdropTag = nil
        self.seriesPrimaryImageTag = nil
        self.path = nil
        self.album = nil
        self.albumArtist = nil
        self.artists = nil
        self.isFolder = isFolder
        self.collectionType = nil
        self.childCount = nil
        self.syncedAt = syncedAt
    }
}

public extension LibraryRecord {

    init(
        id: String,
        serverId: String,
        name: String,
        collectionType: String?,
        sortIndex: Int,
        itemCount: Int?
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.collectionType = collectionType
        self.sortIndex = sortIndex
        self.itemCount = itemCount
    }
}

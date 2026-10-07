import Foundation

/// A hand-made correction to an item's metadata, and the rule for making it stick.
///
/// The problem this exists for: a scraper that matched an anime against its Japanese
/// listing names it in katakana, you fix it, and the next refresh — yours, another
/// client's, or the server's own scheduled task — puts the katakana straight back.
/// Editing without locking is not editing; it is a suggestion the next scrape
/// declines.
///
/// Jellyfin's answer is `LockedFields`, a list of things a refresh must leave alone,
/// and `LockData`, which freezes the item entirely. Both live on the item, on the
/// server, so a lock set here holds against every client and every scheduled scan —
/// not just against this app.
public struct ItemEdit: Sendable, Equatable {

    /// Jellyfin's `MetadataField` enum, which is what `LockedFields` accepts.
    ///
    /// Deliberately the whole list, short as it is, because what it *omits* is the
    /// thing worth knowing: there is no lock for sort name, year, or premiere date.
    /// Protecting those means locking the item outright.
    public enum Lockable: String, Sendable, CaseIterable {
        case name = "Name"
        case overview = "Overview"
        case genres = "Genres"
        case studios = "Studios"
        case tags = "Tags"
        case cast = "Cast"
        case runtime = "Runtime"
        case officialRating = "OfficialRating"
        case productionLocations = "ProductionLocations"
    }

    public var name: String?
    /// The title as originally released. Jellyfin keeps it separate from `Name`, so
    /// the katakana can be preserved here while the display name reads in romaji.
    public var originalTitle: String?
    /// What the item files under, independent of what it is called. Changing a name
    /// without this leaves an anime alphabetised under its old first letter.
    public var sortName: String?
    /// Whether the sort name is a deliberate override rather than a value read back
    /// from the server. See `applied(to:)`.
    public var forcesSortName = false
    public var overview: String?
    public var productionYear: Int?

    // Music. A track carries fields a film has no use for, and getting them wrong
    // is what scatters an album across four rows of an artist page: the album name
    // groups the tracks, the album artist groups the albums, and the track number
    // is the only thing that puts them back in order.
    public var album: String?
    public var albumArtist: String?
    /// Performers on this track specifically, which is not the same as the album
    /// artist — a guest vocal belongs here and nowhere else.
    public var artists: [String]?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var genres: [String]?

    // Episodes. Jellyfin stores an episode's number in the same two fields as a
    // track's — IndexNumber and ParentIndexNumber — but calling a season a "disc
    // number" at the call site is how the wrong one gets set. These are aliases,
    // not new fields, and `applied(to:)` treats them as such.
    public var episodeNumber: Int?
    public var seasonNumber: Int?

    /// Fields a refresh must not touch afterwards.
    public var lockedFields: Set<Lockable>
    /// Freezes every field, including the ones with no individual lock.
    public var lockAll: Bool

    public init(
        name: String? = nil,
        originalTitle: String? = nil,
        sortName: String? = nil,
        forcesSortName: Bool = false,
        overview: String? = nil,
        productionYear: Int? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        artists: [String]? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        genres: [String]? = nil,
        episodeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        lockedFields: Set<Lockable> = [],
        lockAll: Bool = false
    ) {
        self.name = name
        self.originalTitle = originalTitle
        self.sortName = sortName
        self.forcesSortName = forcesSortName
        self.overview = overview
        self.productionYear = productionYear
        self.album = album
        self.albumArtist = albumArtist
        self.artists = artists
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genres = genres
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.lockedFields = lockedFields
        self.lockAll = lockAll
    }

    /// Applies this edit to an item's raw JSON, returning the object to post back.
    ///
    /// Everything not named here is carried across untouched. That is the whole
    /// point of working in raw JSON: the update endpoint replaces the entire item,
    /// and a typed round-trip through a partial model would clear provider ids,
    /// people, chapters and every other field this app does not decode.
    ///
    /// Locks are unioned with whatever is already locked, never replaced — someone
    /// who locked Genres last month should not have that undone by editing a name.
    public func applied(to item: [String: Any]) -> [String: Any] {
        var updated = item

        // Empty means "leave it as it is", not "clear it". A cleared name is not a
        // thing anyone wants, and a text field someone tabbed through should not
        // erase what was there.
        if let name = trimmed(name) { updated["Name"] = name }
        if let originalTitle = trimmed(originalTitle) { updated["OriginalTitle"] = originalTitle }
        if let sortName = trimmed(sortName) {
            updated["SortName"] = sortName
            // ForcedSortName only where it was asked for. Jellyfin reads it when
            // ordering an item a user has renamed, so a deliberate sort override
            // needs it — but the metadata editor prefills this field from the
            // server's *computed* SortName, and writing it back unconditionally
            // turned an automatic value into a permanent manual override for every
            // item anyone ever opened the editor on.
            if forcesSortName {
                updated["ForcedSortName"] = sortName
            }
        }
        if let overview = trimmed(overview) { updated["Overview"] = overview }
        if let productionYear { updated["ProductionYear"] = productionYear }

        if let album = trimmed(album) { updated["Album"] = album }
        if let albumArtist = trimmed(albumArtist) {
            updated["AlbumArtist"] = albumArtist
            // Jellyfin reads the plural when re-indexing; setting only the singular
            // leaves the artist page grouped by the old value until a full refresh.
            updated["AlbumArtists"] = [["Name": albumArtist]]
        }
        if let artists, !artists.isEmpty { updated["Artists"] = artists }
        // The episode names win where both are set, since nothing sets both by
        // accident — a caller that passes an episode number meant an episode.
        if let number = episodeNumber ?? trackNumber { updated["IndexNumber"] = number }
        if let number = seasonNumber ?? discNumber { updated["ParentIndexNumber"] = number }
        if let genres { updated["Genres"] = genres }

        let existing = Set((item["LockedFields"] as? [String]) ?? [])
        let combined = existing.union(lockedFields.map(\.rawValue))
        // Sorted so the same edit produces the same payload twice — an unordered
        // set here would make every save look like a change to anything diffing it.
        updated["LockedFields"] = combined.sorted()

        if lockAll { updated["LockData"] = true }
        return updated
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

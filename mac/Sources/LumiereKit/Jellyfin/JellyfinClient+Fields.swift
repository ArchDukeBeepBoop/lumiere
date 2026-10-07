import Foundation

/// What to ask the server for, per request.
///
/// Split from JellyfinClient+Library.swift for the project's 300-line limit, and it
/// reads better alone: every case here is a decision about bytes over the wire, and
/// several were bugs — a column the cache had carried since phase 0 that no request
/// ever populated.
extension JellyfinClient {

    /// How much of each item to ask for.
    ///
    /// This matters more than it looks: `Fields=...` is the difference between a
    /// 400-item page costing 200 KB and costing 12 MB. Grids get `.list`; only the
    /// item you actually opened gets `.detail`.
    public enum FieldSet {
        case list
        /// `list`, plus the alternate files an item carries.
        ///
        /// For folder libraries only, and only because Jellyfin merges them. Several
        /// video files in one folder become a single Movie with the rest hanging off
        /// it as extra `MediaSources`, so a listing built from items shows one tile
        /// where the user put ten files. Measured on `3D`: `Clips/Compilations/…`
        /// returned one item per collection folder while `Clips/Lantern Road` returned
        /// seven, because Lantern Road's filenames were different enough not to merge.
        ///
        /// Not in `.list` itself. MediaSources carries every stream of every file and
        /// is far the heaviest field the API offers — asking for it across 45,000
        /// scraped items to serve two folder libraries would be paying for it
        /// thousands of times over.
        case listWithVersions
        case detail
        /// Just enough to tell what a title is *related* to, for the franchise
        /// grouper. Narrow on purpose: it is asked for a whole library at once, so
        /// every field is paid for a few thousand times over.
        case relations

        /// Public so a test can assert the write-critical fields are present.
        public var value: String {
            switch self {
            case .list, .listWithVersions:
                // Path is here for the "original filename" title style. It is a
                // short string and worth the bytes; the alternative is a request
                // per visible cell.
                // DateCreated is not optional here: every "Latest" shelf sorts on
                // it, and without it the column was NULL on all 1,698 series so the
                // shelves fell back to sync order — which is alphabetical, so
                // "Latest Anime" opened on 3x3 Eyes and 707 Sky Patrol.
                //
                // Overview is the same mistake in a different column: ItemRecord has
                // carried an `overview` field since phase 0 and EpisodeRow has always
                // tried to display it, but nothing ever asked the server for it during
                // a sync — only a single opened item's on-demand `.detail` fetch ever
                // populated it. Every episode's synopsis was silently empty until that
                // one episode had been opened individually once.
                return "PrimaryImageAspectRatio,ParentBackdropItemId,"
                     + "ParentBackdropImageTags,Path,DateCreated,ExtraType,ParentId,Overview"
                     // OriginalTitle is what makes a show findable by the name it
                     // is actually known by — Shingeki no Kyojin for Attack on
                     // Titan. Without it in the sync, no amount of query work can
                     // match a title the cache has never seen.
                     + ",OriginalTitle"
                     // Genres is the same omission again, and it is the whole
                     // reason "Browse by genre" looked incomplete. `ItemRecord`
                     // has carried a `genres` column since phase 0 and every
                     // genre surface reads it, but the only request that ever
                     // asked the server for it was the single-item `.detail`
                     // fetch. So the column was NULL on every row a sync wrote,
                     // the genre catalogue was built from whichever handful of
                     // items somebody had happened to open a detail page for, and
                     // the next sync overwrote even those back to NULL. A short
                     // array of short strings per item — the cheapest field here.
                     + ",Genres"
                     // Studios is the third instance of exactly the paragraph
                     // above, found while building the studio filter: the column
                     // existed, nothing asked for it, so every synced row had a
                     // NULL where the answer should be. Same cost as Genres — a
                     // short array of short strings.
                     + ",Studios"
                     // Only where a merged folder makes it necessary. See the case.
                     + (self == .listWithVersions ? ",MediaSources" : "")
            case .detail:
                return [
                    "Overview", "Genres", "Studios", "People", "Taglines", "Chapters",
                    "MediaSources", "MediaStreams", "ProductionYear", "DateCreated",
                    "OfficialRating", "ParentBackdropItemId", "ParentBackdropImageTags",
                    // SortName is not returned unless asked for, and the metadata
                    // editor needs it: a sort field that shows blank when the server
                    // holds a value reads as "unset" and silently overwrites it.
                    "Path", "SortName",
                    // Everything below is here because this response is not only
                    // read — `updateItem` posts it back as the new item, and
                    // `POST /Items/{id}` replaces the whole DTO rather than
                    // patching it. A field Jellyfin gates behind `Fields` and we
                    // did not ask for comes back absent, and absent is how you
                    // clear it.
                    //
                    // So this list is a safety property, not a convenience. Without
                    // ProviderIds, renaming an anime to its romaji title also cut
                    // its TMDB and TVDB ids, and the next scan re-matched it from
                    // the title — the precise failure the locking was added to
                    // prevent. Settings is the one that reads like nothing: it
                    // carries LockedFields, LockData and ForcedSortName, so without
                    // it every save quietly unlocked whatever was locked before,
                    // including locks set from Jellyfin's own web client.
                    "ProviderIds", "Tags", "OriginalTitle", "Settings",
                    "ProductionLocations", "CustomRating",
                ].joined(separator: ",")
            case .relations:
                // Overview is here for the prose signal: franchises the metadata never
                // labelled are often obvious from their synopses, which name the
                // same people and places.
                return "Tags,Studios,People,Genres,Overview"
            }
        }
    }
}

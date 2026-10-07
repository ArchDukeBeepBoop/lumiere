import Foundation

/// Each room with its own settings.
///
/// The private room had the library's settings — its layout, its shelves,
/// how the player behaves — and changing one inside changed it outside too.
/// Now each room keeps its own copy: entering the private room puts the
/// library's values aside and the room's in their place, and leaving swaps
/// them back. Every screen reads its settings as it always has and simply
/// gets the room's, and Settings opened inside the room edits the room's.
///
/// The first time in, the room starts as a copy of the library's settings.
/// Shared, not swapped: what defines the room itself (its lock, its look,
/// what it blocks), the app's appearance and theme (the room draws its own),
/// and bookkeeping such as volume and skip counts.
@MainActor
public enum RoomPreferences {
    public static let keys: [String] = [
        // Preference.*
        "allowsRemoval", "animeDefaultsToJapanese", "autoSkipsIntros", "changeCheckSeconds",
        "collectionDefaultOrder", "continuesAcrossSeasons", "creditsWindowMinutes",
        "episodesFollowFilename", "explainsSpotlight", "followsLinkedChapters", "framesEpisodes",
        "hidesSingleFilmCollections", "homeFollowsHover", "homeShowsAllShelves", "homeShowsBackdrop",
        "includesSpecialsInOrder", "latestIncludesVideos", "leadsWithProgress", "mergesUpNext",
        "offersRecapSkip", "pausesWhileScrubbing", "playsFromDisk", "playsNextAutomatically",
        "remembersFlip", "roundsRatings", "screensaverMinutes", "scrollSeeks", "seekLanding",
        "seekLongStepSeconds", "seekStepSeconds", "separatesExtras", "showsOriginalTitle",
        "shufflePlaysAtOnce", "stillWatchingAfter", "subtitleSearchLanguage",
        "subtitleSyncMaxShiftSeconds", "subtitleSyncOnDownload", "subtitleSyncTrustPercent",
        "typeAwareCardLines", "watchedAtCredits", "enhancesDialogue", "reducesLoudSounds", "showsUpNextStage",
        // Settings stored under their own names
        "defaultVolumeBoost", "folderModeLibraries", "folderTileShape", "glassBackground",
        "glassOpacity", "gridModeLibraries", "gridTileWidth", "homeLayout", "locksUploadedArtwork",
        "maxBitrateMbps", "preferredSubtitleKind", "showsSidebar", "showsUnwatchedBadges",
        "subtitleFontFamily", "subtitleSize", "subtitleStyle", "titleStyle", "unifiedEpisodeArt",
        "chromeStyle", "discreetArtLibraryChoices", "folderViewMode", "homeSectionOrder",
        "homeHiddenSections", "recentlyAddedLibraryChoices", "shelfRulesByLibrary", "unwatchedMarker",
    ]

    private static let activeKey = "roomPreferencesActive"
    private static let libraryKey = "roomPreferences.library"
    private static let roomKey = "roomPreferences.room"
    private static var defaults: UserDefaults { .standard }

    public static var isActive: Bool { defaults.bool(forKey: activeKey) }

    public static func enter() {
        guard !isActive else { return }
        defaults.set(snapshot(), forKey: libraryKey)
        // A room never entered before starts as a copy: nothing to load.
        if let room = defaults.dictionary(forKey: roomKey) { restore(room) }
        defaults.set(true, forKey: activeKey)
    }

    public static func leave() {
        guard isActive else { return }
        defaults.set(snapshot(), forKey: roomKey)
        restore(defaults.dictionary(forKey: libraryKey) ?? [:])
        defaults.set(false, forKey: activeKey)
    }

    /// Lumiere always starts outside the room. Quit from inside it, the
    /// room's values are still in place — put the library's back.
    public static func recoverAtLaunch() { leave() }

    private static func snapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in keys { if let value = defaults.object(forKey: key) { out[key] = value } }
        return out
    }

    private static func restore(_ values: [String: Any]) {
        for key in keys {
            if let value = values[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}

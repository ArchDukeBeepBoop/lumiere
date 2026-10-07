import Foundation
import LumiereKit

/// Every setting, with the name a person knows it by and how Lumiere comes.
///
/// What Settings › Your Setup reads to list what you have changed: a key is
/// changed when it is stored and differs from its default here.
enum SettingsCatalog {
    struct Entry: Identifiable, Sendable {
        let key: String
        let label: String
        let section: String
        let fallback: any Sendable
        var id: String { key }
    }

    private static func bool(_ k: Preference.Key, _ label: String, _ section: String) -> Entry {
        Entry(key: k.name, label: label, section: section, fallback: k.defaultValue)
    }
    private static func int(_ k: Preference.IntKey, _ label: String, _ section: String) -> Entry {
        Entry(key: k.name, label: label, section: section, fallback: k.defaultValue)
    }
    private static func text(_ k: Preference.StringKey, _ label: String, _ section: String) -> Entry {
        Entry(key: k.name, label: label, section: section, fallback: k.defaultValue)
    }

    static let entries: [Entry] = [
        Entry(key: "appearance", label: "Appearance", section: "Look", fallback: AppearanceSetting.auto.rawValue),
        Entry(key: "glassBackground", label: "Frosted glass window", section: "Look", fallback: true),
        Entry(key: "glassOpacity", label: "Glass opacity", section: "Look", fallback: 0.62),
        Entry(key: PaperTheme.storageKey, label: "Theme", section: "Look", fallback: "standard"),
        Entry(key: "paperGrain", label: "Paper grain", section: "Look", fallback: 0.55),
        Entry(key: "paperRules", label: "Paper rules", section: "Look", fallback: true),
        Entry(key: "titleStyle", label: "Title style", section: "Look", fallback: TitleStyle.metadataTitle.rawValue),
        Entry(key: "unifiedEpisodeArt", label: "One picture for every episode", section: "Look", fallback: false),
        Entry(key: "showsUnwatchedBadges", label: "Unwatched badges", section: "Look", fallback: true),
        Entry(key: "folderTileShape", label: "Folder tile shape", section: "Look", fallback: ""),
        Entry(key: "gridTileWidth", label: "Poster size", section: "Look", fallback: Double(Theme.Art.posterWidth)),
        Entry(key: "showsSidebar", label: "Sidebar kept open", section: "Look", fallback: false),
        bool(Preference.roundsRatings, "Round ratings", "Look"),
        bool(Preference.showsOriginalTitle, "Original title under the name", "Look"),
        bool(Preference.leadsWithProgress, "Lead with where you are in a series", "Look"),
        bool(Preference.typeAwareCardLines, "Studio or runtime under tiles", "Look"),
        bool(Preference.separatesExtras, "Specials kept apart as Extras", "Look"),
        Entry(key: "homeLayout", label: "Home layout", section: "Home", fallback: HomeLayout.classic.rawValue),
        bool(Preference.showsAllShelves, "Every shelf on Home", "Home"),
        bool(Preference.explainsSpotlight, "Why the spotlight chose a title", "Home"),
        bool(Preference.latestIncludesVideos, "Loose videos on Latest rows", "Home"),
        bool(Preference.mergesUpNext, "One Up Next row", "Home"),
        bool(Preference.homeShowsBackdrop, "Spotlight on Home", "Home"),
        bool(Preference.homeFollowsHover, "Home background follows the pointer", "Home"),
        int(Preference.screensaverMinutes, "Screensaver after (minutes)", "Home"),
        bool(Preference.shufflePlaysAtOnce, "Shuffle plays at once", "Home"),
        bool(Preference.hidesSingleFilmCollections, "Hide one-film collections", "Home"),
        text(Preference.collectionDefaultOrder, "Collection order", "Home"),
        Entry(key: "preferredSubtitleKind", label: "Preferred subtitles", section: "Playback", fallback: SubtitleKind.dialogue.rawValue),
        Entry(key: "subtitleStyle", label: "Subtitle style", section: "Playback", fallback: "default"),
        Entry(key: "subtitleSize", label: "Subtitle size", section: "Playback", fallback: SubtitleSize.normal.rawValue),
        Entry(key: "subtitleFontFamily", label: "Subtitle font", section: "Playback", fallback: ""),
        Entry(key: "maxBitrateMbps", label: "Streaming quality cap", section: "Playback", fallback: 0.0),
        Entry(key: "defaultVolumeBoost", label: "Volume boost", section: "Playback", fallback: 100.0),
        bool(Preference.playsNextAutomatically, "Play the next episode automatically", "Playback"),
        bool(Preference.autoSkipsIntros, "Skip intros by themselves", "Playback"),
        bool(Preference.offersRecapSkip, "Offer Skip Recap", "Playback"),
        bool(Preference.showsUpNextStage, "Up Next takes the screen at the credits", "Playback"),
        int(Preference.stillWatchingAfter, "Ask “Still watching?” after (episodes)", "Playback"),
        bool(Preference.watchedAtCredits, "Watched once the credits begin", "Playback"),
        bool(Preference.continuesAcrossSeasons, "Next carries into the next season", "Playback"),
        bool(Preference.includesSpecialsInOrder, "Specials count in the order", "Playback"),
        bool(Preference.enhancesDialogue, "Enhance dialogue", "Playback"),
        bool(Preference.reducesLoudSounds, "Reduce loud sounds", "Playback"),
        bool(Preference.pausesWhileScrubbing, "Pause while scrubbing", "Playback"),
        bool(Preference.scrollSeeks, "Trackpad swipes seek", "Playback"),
        int(Preference.seekStepSeconds, "Arrow-key seek (seconds)", "Playback"),
        int(Preference.seekLongStepSeconds, "Shift-arrow seek (seconds)", "Playback"),
        text(Preference.seekLanding, "Where the scrubber lands", "Playback"),
        bool(Preference.playsFromDisk, "Play from disk when possible", "Playback"),
        bool(Preference.remembersFlip, "Remember a flipped picture", "Playback"),
        bool(Preference.followsLinkedChapters, "Follow linked openings and endings", "Playback"),
        bool(Preference.framesEpisodes, "Creditless openings around a season", "Playback"),
        int(Preference.creditsWindowMinutes, "Credits window (minutes)", "Playback"),
        bool(Preference.animeDefaultsToJapanese, "Anime in Japanese with subtitles", "Playback"),
        text(Preference.subtitleSearchLanguage, "Subtitle search language", "Playback"),
        bool(Preference.subtitleSyncOnDownload, "Sync downloaded subtitles", "Playback"),
        int(Preference.subtitleSyncTrustPercent, "Subtitle sync confidence (%)", "Playback"),
        int(Preference.subtitleSyncMaxShiftSeconds, "Subtitle sync range (seconds)", "Playback"),
        bool(Preference.episodesFollowFilename, "Episodes in filename order", "Library"),
        bool(Preference.allowsRemoval, "Allow removing from the library", "Library"),
        Entry(key: "locksUploadedArtwork", label: "Lock artwork you upload", section: "Library", fallback: true),
        int(Preference.changeCheckSeconds, "Check for changes every (seconds)", "Library"),
        bool(Preference.roomRequiresUnlock, "Private Room asks to unlock", "Privacy"),
        int(Preference.roomLockMinutes, "Private Room locks after (minutes)", "Privacy"),
        bool(Preference.roomUsesOwnTheme, "Private Room’s own theme", "Privacy"),
        bool(Preference.roomBlocksCapture, "Private Room hidden from screenshots", "Privacy"),
        bool(Preference.roomBlursCovers, "Private Room covers blurred", "Privacy"),
        bool(Preference.looksUpPrivateLibraries, "Look up private libraries", "Privacy"),
    ]

    /// Entries whose stored value differs from how Lumiere comes.
    static func changed(in defaults: UserDefaults = .standard) -> [(Entry, Any)] {
        entries.compactMap { entry in
            guard let stored = defaults.object(forKey: entry.key),
                  !(stored as AnyObject).isEqual(entry.fallback) else { return nil }
            return (entry, stored)
        }
    }

    static func describe(_ value: Any) -> String {
        switch value {
        case let flag as Bool: return flag ? "On" : "Off"
        case let number as Double: return number.rounded() == number ? String(Int(number)) : String(format: "%.2f", number)
        case let text as String: return text.isEmpty ? "None" : text
        default: return String(describing: value)
        }
    }
}

import Foundation

/// The choices that started life as requests.
///
/// Most of what was asked for over the last stretch — round the ratings, show
/// the original title, lead the page with where you are, keep the home screen
/// to seven shelves, put the studio under an anime — was shipped as behaviour.
/// Each is a taste, and a taste shipped as behaviour is a decision made for
/// everyone by one person. So they are gathered here as switches, named in one
/// place so the key a view reads and the key Settings writes cannot drift.
///
/// The defaults are the requests: what was asked for is what you get until you
/// say otherwise.
public enum Preference {

    /// "Rated 9" rather than "Rated 8.6". See `Rating`.
    public static let roundsRatings = Key("roundsRatings", default: true)
    /// The romaji or native title under the display name on a detail page.
    public static let showsOriginalTitle = Key("showsOriginalTitle", default: true)
    /// "You are on episode 7 of 24" above the metadata line. See `DominantFact`.
    public static let leadsWithProgress = Key("leadsWithProgress", default: true)
    /// Studio under an anime tile, runtime under a film. See `MetadataLine`.
    public static let typeAwareCardLines = Key("typeAwareCardLines", default: true)
    /// Season 0 under a rule, called Extras, rather than a peer of Season 1.
    public static let separatesExtras = Key("separatesExtras", default: true)
    /// The one-line reason under the hero's title. See `SpotlightReason`.
    public static let explainsSpotlight = Key("explainsSpotlight", default: true)
    /// Loose videos — files the scanner could not place as a film or an
    /// episode — count as content on a Latest row. Everything in a folder
    /// library is one, so without this the 3D and My Videos rows never showed
    /// anything added since the server stopped mirroring Jellyfin.
    public static let latestIncludesVideos = Key("latestIncludesVideos", default: true)
    /// Whether the right-click menus offer to take content out of the library
    /// — remove, and delete to the Trash. Off by default: this app was built
    /// never to touch media, and a menu that can send a file to the Trash is
    /// one to have asked for.
    public static let allowsRemoval = Key("allowsRemoval", default: true)
    /// Episodes in the order their filenames sort, whatever a provider later
    /// named them. See `orderedAsEpisodes`.
    public static let episodesFollowFilename = Key("episodesFollowFilename", default: true)
    /// A season's creditless opening sits before its episodes and its ending
    /// after, so the run plays the way the show did. See
    /// `CreditlessClassifier.ordered(_:framing:)`.
    public static let framesEpisodes = Key("framesEpisodes", default: true)
    /// Follow a release's linked opening and ending — Matroska ordered
    /// chapters that borrow from sibling files — and play the episode as one
    /// timeline, the way VLC does. See `PlaybackRequest.linkedFiles`.
    public static let followsLinkedChapters = Key("followsLinkedChapters", default: true)
    /// Every shelf, ignoring the seven-shelf cap. See `HomeShelfCap`.
    public static let showsAllShelves = Key("homeShowsAllShelves", default: false)

    /// How many minutes before the end a credits segment may begin and still
    /// be believed. See `SegmentTrust`.
    public static let creditsWindowMinutes = IntKey("creditsWindowMinutes", default: SegmentTrust.defaultFloorMinutes)

    /// Pause the sound while the scrubber is held, and resume on release.
    /// Audio that stutters through every keyframe passed over is the noise a
    /// drag makes without this.
    public static let pausesWhileScrubbing = Key("pausesWhileScrubbing", default: true)
    /// Two fingers left or right on the trackpad, or a wheel, seeks — mpv's
    /// gesture. See `ScrollSeek`.
    public static let scrollSeeks = Key("scrollSeeks", default: true)
    /// Seconds for an arrow key or J/L.
    public static let seekStepSeconds = IntKey("seekStepSeconds", default: 10)
    /// Seconds for a shifted arrow key.
    public static let seekLongStepSeconds = IntKey("seekLongStepSeconds", default: 60)
    /// Open a file straight from disk when the server's copy is on a volume
    /// this machine can read, instead of streaming it back over HTTP. See
    /// `DiskPlayback`.
    public static let playsFromDisk = Key("playsFromDisk", default: true)
    /// Where a released scrubber lands. See `SeekLanding`.
    public static let seekLanding = StringKey("seekLanding", default: SeekLanding.auto.rawValue)

    /// When an episode ends, the next one starts. Off by default: it changes
    /// what the end of an episode does, which is the viewer's call.
    /// Next Up, Continue the Series and Finish the Season as one "Up Next"
    /// row, rather than three rows answering the same question.
    public static let mergesUpNext = Key("mergesUpNext", default: true)
    /// The private room asks for Touch ID or the Mac's password to open.
    public static let roomRequiresUnlock = Key("roomRequiresUnlock", default: true)
    /// Minutes in the background before the room closes itself: 0 as soon as
    /// Lumiere is left, -1 never.
    public static let roomLockMinutes = IntKey("roomLockMinutes", default: 0)
    /// The room's own darker, unaccented palette.
    public static let roomUsesOwnTheme = Key("roomUsesOwnTheme", default: true)
    /// The window is kept out of screenshots and screen sharing in the room.
    public static let roomBlocksCapture = Key("roomBlocksCapture", default: true)
    /// Private libraries are looked up on the movie database. Off: named from
    /// their filenames, never matched to anything outside.
    public static let looksUpPrivateLibraries = Key("looksUpPrivateLibraries", default: false)
    /// Covers in private libraries are blurred until pointed at.
    /// The spotlight across the top of Home. Each room has its own copy of
    /// this, as of every setting — see `RoomPreferences`.
    public static let homeShowsBackdrop = Key("homeShowsBackdrop", default: true)
    /// At the credits, the picture steps into a corner and the next episode
    /// takes the screen. Off: the small Next offer only.
    public static let showsUpNextStage = Key("showsUpNextStage", default: true)
    /// Apple TV's audio switches, kept from film to film.
    public static let enhancesDialogue = Key("enhancesDialogue", default: false)
    public static let reducesLoudSounds = Key("reducesLoudSounds", default: false)
    /// Home's background taking the artwork of the title pointed at. Off: Home
    /// keeps its own plain background.
    public static let homeFollowsHover = Key("homeFollowsHover", default: false)
    /// Minutes idle on Home before the backdrops take over. Zero is never.
    public static let screensaverMinutes = IntKey("screensaverMinutes", default: 5)
    public static let roomBlursCovers = Key("roomBlursCovers", default: true)
    /// In a library named for anime, with no choice made, Japanese audio and
    /// English dialogue subtitles.
    public static let animeDefaultsToJapanese = Key("animeDefaultsToJapanese", default: true)
    /// Shuffle starts playing its pick at once, rather than showing it first.
    public static let shufflePlaysAtOnce = Key("shufflePlaysAtOnce", default: false)
    /// How a collection is ordered until it is given an order of its own —
    /// release date, as Jellyfin orders film series. See `CollectionOrder`.
    /// Collections holding a single film are left out of rows and grids.
    public static let hidesSingleFilmCollections = Key("hidesSingleFilmCollections", default: true)
    public static let collectionDefaultOrder = StringKey("collectionDefaultOrder", default: "releaseDate")
    /// Seconds between asking the server whether anything changed; 0 is off.
    /// See `AppModel+ChangeWatch`.
    public static let changeCheckSeconds = IntKey("changeCheckSeconds", default: 30)
    public static let playsNextAutomatically = Key("playsNextAutomatically", default: false)
    /// Episodes played back to back with nobody pressing anything before the
    /// player asks "Still watching?" instead of going on. Zero never asks.
    public static let stillWatchingAfter = IntKey("stillWatchingAfter", default: 3)
    /// A season's intro is skipped automatically after three manual skips.
    public static let autoSkipsIntros = Key("autoSkipsIntros", default: true)
    /// Skip Recap and Skip Preview are offered where a file marks them.
    public static let offersRecapSkip = Key("offersRecapSkip", default: true)
    /// Stopping once the credits have begun counts as watched. See
    /// `WatchedAtCredits`.
    public static let watchedAtCredits = Key("watchedAtCredits", default: true)
    /// Next and Previous carry on into the neighbouring season. See
    /// `SeasonNeighbours`.
    public static let continuesAcrossSeasons = Key("continuesAcrossSeasons", default: true)
    /// …and count the specials season as one of them.
    public static let includesSpecialsInOrder = Key("includesSpecialsInOrder", default: false)
    /// A flipped picture stays flipped for the rest of the show. See `FlipMemory`.
    public static let remembersFlip = Key("remembersFlip", default: true)
    /// The language a subtitle search asks the provider for.
    public static let subtitleSearchLanguage = StringKey("subtitleSearchLanguage", default: "en")
    /// Check a fetched subtitle's timing against the audio as it downloads.
    public static let subtitleSyncOnDownload = Key("subtitleSyncOnDownload", default: true)
    /// How sure a sync must be, in percent, before its shift is applied.
    /// Measured on this library: a right match scores 50–90, one episode's
    /// subtitle against another's audio 25. See `subs.MinConfidence`.
    public static let subtitleSyncTrustPercent = IntKey("subtitleSyncTrustPercent", default: 40)
    /// How far out, in seconds, a subtitle may be and still be found.
    public static let subtitleSyncMaxShiftSeconds = IntKey("subtitleSyncMaxShiftSeconds", default: 60)

    public struct StringKey: Sendable {
        public let name: String
        public let defaultValue: String
        init(_ name: String, default value: String) {
            self.name = name
            self.defaultValue = value
        }
        public var value: String {
            UserDefaults.standard.string(forKey: name) ?? defaultValue
        }
    }

    public struct IntKey: Sendable {
        public let name: String
        public let defaultValue: Int
        init(_ name: String, default value: Int) {
            self.name = name
            self.defaultValue = value
        }
        public var value: Int {
            UserDefaults.standard.object(forKey: name) as? Int ?? defaultValue
        }
    }

    public struct Key: Sendable {
        public let name: String
        public let defaultValue: Bool
        init(_ name: String, default value: Bool) {
            self.name = name
            self.defaultValue = value
        }

        /// For the places that cannot hold an `@AppStorage` — pure code, a
        /// model. Reads the same store Settings writes.
        public var value: Bool {
            UserDefaults.standard.object(forKey: name) as? Bool ?? defaultValue
        }
    }
}

/// Which libraries never show a frame from the episode on a wide card.
///
/// Continue Watching draws a 16:9 card per item and fills it with the best
/// wide picture it has: the show's backdrop, else the episode's own still.
/// Where the show has no backdrop — most of an adult library — that fallback
/// is a frame from the video, on the front page, at 384 points wide. For those
/// libraries the card should show the *show's* artwork or nothing: its
/// backdrop, else its poster, never the frame.
///
/// Same shape as `RecentlyAddedPolicy`: adult-named libraries by default, any
/// library by choice.
public enum DiscreetArtPolicy {

    public static let storageKey = "discreetArtLibraryChoices"

    public static func excludedByDefault(_ library: LibraryRecord) -> Bool {
        RecentlyAddedPolicy.isAdult(library.name)
    }

    /// The libraries whose wide cards use show artwork only.
    public static func discreet(libraries: [LibraryRecord], stored: String?) -> Set<String> {
        let chosen = RecentlyAddedPolicy.choices(from: stored)
        return Set(libraries.filter { library in
            if let choice = chosen[library.id] { return choice }
            return excludedByDefault(library)
        }.map(\.id))
    }
}

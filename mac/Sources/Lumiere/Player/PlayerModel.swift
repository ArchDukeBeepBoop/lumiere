import Foundation
import Observation
import LumiereKit
import LumierePlayer

/// Orchestrates one playback session, start to finish.
///
/// Ask the server how the item can be played, decide locally how it *will* be,
/// build the URL, drive the engine, and report progress back. The decision is
/// made once here and never revisited mid-playback.
@MainActor
@Observable
final class PlayerModel {

    enum State: Equatable {
        case preparing
        case playing
        case paused
        /// libmpv failed to load, so a file only it can play cannot be played
        /// at all. Stated plainly rather than handed to AVPlayer to fail opaquely.
        case engineNotAvailable(PlaybackDecision)
        case failed(String)
    }

    var state: State = .preparing
    var decision: PlaybackDecision?
    var position: Double = 0
    var duration: Double = 0
    var title: String = ""
    var subtitleLine: String?
    /// The show's or film's logo, where the server has one — drawn in place
    /// of `title`. The series' for an episode, so the episode name stays on
    /// the line below. See `PlayerTitleBar`.
    var logo: (itemId: String, tag: String)?

    /// Exposed so the view can attach the right surface: an AVPlayerLayer for
    /// one engine, mpv's own NSView for the other. Exactly one is ever non-nil.
    var avEngine: AVPlayerEngine?
    var mpvEngine: MPVEngine?

    // MARK: - Control state
    //
    // Held here rather than read from the engine on every frame: SwiftUI redraws
    // from these, and an await per property per redraw would stutter the overlay.

    /// Starts at whatever the last session left it. See `setVolume`.
    var volume: Double = PlayerVolume.remembered()
    var isMuted = false
    var volumeBoost: Double = 100
    /// Repeat this file instead of ending it. Per session, not remembered: a
    /// player that silently loops the next thing you open is a player that will
    /// not stop, and the reason is not on screen.
    var isLooping = false
    /// Where this session resumed from, while the notice is still worth showing.
    /// Nil for a file that started at the beginning. See `Prompt.resumed`.
    var resumedFrom: Double?
    /// A brief line saying what the player just did on its own, and how to undo
    /// it. A silent ninety-second jump is indistinguishable from a seek bug.
    var lastAction: PlayerAction?

    /// The pending tidy-up after a run of quick seeks. See `nudge(by:)`.
    ///
    /// Observation-ignored: nothing draws it, and letting it invalidate the
    /// player's view on every keypress would be the opposite of the point.
    @ObservationIgnored var settleTask: Task<Void, Never>?
    /// The scrub the picture has not caught up with yet, and whether one is on
    /// its way. See `scrub(to:)`.
    @ObservationIgnored var pendingScrub: Double?
    @ObservationIgnored var isScrubSeekInFlight = false
    /// Seeks the engine has been asked for and not yet landed. While any are
    /// out, position ticks are the old place and are ignored — see `attachCallbacks`.
    @ObservationIgnored var seeksInFlight = 0
    /// Whether the picture was running when the scrubber was grabbed, so release
    /// can start it again. See `beginScrub`.
    @ObservationIgnored var resumesAfterScrub = false
    /// The picture's width in pixels, from the media source. Decides whether
    /// a release lands exactly — see `SeekLanding`.
    @ObservationIgnored var videoWidth: Int?

    /// How many of this episode's linked segments — its release's opening and
    /// ending — the library does not hold. Shown once, so a file that plays
    /// without its opening is understood rather than wondered at.
    var missingLinkedSegments = 0
    /// What a subtitle search or sync is doing, and what it found. See
    /// `PlayerModel+Subtitles.swift`.
    var subtitleTask: SubtitleTask = .idle
    var subtitleResults: [RemoteSubtitle] = []
    /// The series this file belongs to, for intro learning. Nil for a film,
    /// which has nothing to generalise across.
    var introSeriesId: String?
    /// What has been learned about this series' intro. See `IntroLearning`.
    var learnedIntro: IntroSkip?
    var playbackSpeed: Double = 1

    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var selectedAudioTrack: Int?
    var selectedSubtitleTrack: Int?
    /// The tracks this session was started on, resolved before the engine existed.
    /// Held because the stream URL is built from them — see `PreferredTracks`.
    var startingTracks: PreferredTracks.Choice?

    var aspectOverride: AspectOverride = .auto
    var verticalShift: Double = 0
    /// Mirrored, per session like the rest of the geometry. See `setFlip`.
    var flipHorizontal = false
    var flipVertical = false
    var upscaling: UpscalingMode = .auto
    /// Seconds subtitles are shifted by, for *this file*.
    ///
    /// Starts at zero and is filled in from `SubtitleOffset` once the item is
    /// known. It was a single saved default applied to everything, which fixed the
    /// one episode it was set on and put every other episode out by the same
    /// amount. Positive is later, mpv's sign convention.
    var subtitleDelay: Double = 0
    /// Seconds the sound is shifted by. See `setAudioDelay`.
    var audioDelay: Double = 0
    /// The A-B loop's ends, as set so far. See `stepABLoop`.
    var abLoop: (a: Double?, b: Double?) = (nil, nil)
    /// The output chosen from Audio › Output; nil is the system's.
    var audioDeviceUID: String?
    /// A word on screen for a moment after a menu command. See `PlayerOSD`.
    var osd: (text: String, at: Date)?
    /// How large subtitles are drawn. A preference rather than a per-file
    /// correction — unlike the delay above — so it is remembered app-wide and is
    /// also settable from Settings without a file open.
    var subtitleSize: SubtitleSize = .size(
        id: UserDefaults.standard.string(forKey: "subtitleSize")
    )
    /// Which preset subtitles are drawn with. Same reasoning as the size above, and
    /// the same storage — the player's panel and Settings write one preference.
    var subtitleStyle: SubtitleStyle = .style(
        id: UserDefaults.standard.string(forKey: "subtitleStyle")
    )
    var ambientMode = false
    var showsStatisticsHUD = false

    var statistics = PlaybackStatistics(engineName: "—")
    /// How far ahead of zero the engine holds data, in seconds.
    ///
    /// Nil where the engine cannot say, which is the whole AVPlayer path — only
    /// mpv reports a demuxer cache depth. The scrub bar then draws no buffered
    /// band rather than inventing one, which is the same rule the statistics HUD
    /// follows for every field it cannot fill.
    var bufferedSeconds: Double?
    var chapters: [Chapter] = []
    var trickplay: TrickplayInfo?
    var trickplayWidth: Int?

    /// Labelled intro/outro stretches, when the server has a plugin that provides
    /// them. Empty is the ordinary case, not a failure.
    var segments: [MediaSegment] = []
    /// Keyboard seeking: the scan a held arrow is running, and where the bar's
    /// preview points after a press. See PlayerModel+KeySeek.swift.
    var keyScan: KeyScan?
    var keyPreviewSeconds: Double?
    var keyPreviewClear: Task<Void, Never>?
    /// The episodes either side of this one, for the prev/next controls.
    var previousEpisode: LibraryEntry?
    var nextEpisode: LibraryEntry?
    /// Bumped each time a file plays to its end; the view carries on from it
    /// when "Play the next episode automatically" is on.
    var endedCount = 0

    /// Everything queued behind this file: the season, in order.
    ///
    /// Free — `loadEpisodeContext` already fetches the whole season to work out what
    /// the previous and next episodes are, and threw the rest away. What it costs is
    /// one array of rows the repository had already materialised.
    var queue: [LibraryEntry] = []
    /// Where the file now playing sits in `queue`.
    var queueIndex: Int?

    /// The engine, for the controls extension. Read-only by intent: nothing
    /// outside this file may swap it.
    var engineRef: (any PlayerEngine)? { engine }

    // Internal so the episode extension can ask for media segments.
    let client: JellyfinClient
    // Internal rather than private so the controls extension can read preferences.
    let repository: LibraryRepository
    /// What remembered track choices are stored against: the series for an episode,
    /// the item itself for a film. Captured at load because the entry is not kept.
    var preferenceKey: String?
    /// Falls back to the whole library's default when the series has no choice of
    /// its own. Set alongside `preferenceKey` from the same cached row.
    var libraryPreferenceKey: String?
    let capabilities: SystemCapabilities
    // Internal so the episode extension can key its lookups.
    let itemId: String
    /// Which media source to prefer. Nil means the server's first, which is right
    /// for the overwhelming majority of titles — they only have one file.
    var preferredSourceId: String?

    // Not private: PlayerModel+Transport.swift sends commands to it, and Swift's
    // `private` is file-scoped.
    var engine: (any PlayerEngine)?
    var mediaSourceId: String?
    var playSessionId: String?
    var lastReportedAt: Double = -.infinity
    var didStart = false
    var didTick = false

    /// Jellyfin's own web client reports every ten seconds. Matching it keeps the
    /// "now playing" panel live without a request per frame.
    let reportInterval: Double = 10

    init(
        itemId: String,
        client: JellyfinClient,
        repository: LibraryRepository,
        capabilities: SystemCapabilities
    ) {
        self.itemId = itemId
        self.client = client
        self.repository = repository
        self.capabilities = capabilities
    }

    var progressFraction: Double {
        duration > 0 ? min(1, max(0, position / duration)) : 0
    }

    /// Where the buffered band ends on the scrub bar, or nil when the engine has
    /// not said. Never behind the playhead: a cache reading shorter than what has
    /// already been played is a measurement artefact, not something to draw.
    var bufferedFraction: Double? {
        guard duration > 0, let bufferedSeconds else { return nil }
        return min(1, max(progressFraction, bufferedSeconds / duration))
    }

    var isPlaying: Bool { state == .playing }
}

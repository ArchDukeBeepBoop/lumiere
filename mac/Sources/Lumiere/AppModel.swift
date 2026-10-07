import Foundation
import Observation
import LumiereKit
import LumierePlayer

/// Owns the signed-in state and the three long-lived services: the cache, the
/// repository that reads it, and the image pipeline. One instance, created at
/// launch and rebuilt on sign-in.
@MainActor
@Observable
final class AppModel {

    // The properties without `private(set)` below are the ones the extensions in
    // AppModel+Downloads/Artwork/Demo.swift write to. Swift's `private` is
    // file-scoped, so splitting this type across files is what forces them open;
    // they stay module-internal, so nothing outside the app target can reach them.
    // Anything only this file writes keeps `private(set)`.
    var client: JellyfinClient?
    var repository: LibraryRepository?
    var imagePipeline: ImagePipeline?
    var database: LibraryDatabase?
    private(set) var downloads: DownloadManager?
    private(set) var prefetcher: ArtworkPrefetcher?
    /// Mirrored for the UI: reading an actor's property needs an await, and a view
    /// body cannot await.
    var downloadRecords: [DownloadRecord] = []
    var prefetchProgress: ArtworkPrefetcher.Progress?
    var artworkFetcher: ArtworkAutoFetcher?
    var artworkFetchProgress: ArtworkAutoFetcher.Progress?
    var isShowingSetupGuide = false

    /// Which file of a multi-version title to play.
    ///
    /// The detail page has had a version picker since phase 4 — a 4K and a 1080p
    /// rip of one film — and playback always took `sources.first` regardless, so
    /// the picker was decoration. Set alongside `nowPlayingItemId`, cleared with it.
    var nowPlayingSourceId: String?

    /// A section the menu bar has asked to open.
    ///
    /// The app had no keyboard route to anything outside the player: no ⌘F for
    /// search, and ⌘, did nothing because a `Window` scene has no Settings scene
    /// behind it. The shell owns the actual selection, so the menu posts an
    /// intention here and the shell picks it up.
    var pendingRoute: Route?

    /// A one-line report of something that just failed.
    ///
    /// The app had no way to say "that didn't work": nearly every mutation went
    /// through `try?`, so a server refusal and a success were indistinguishable —
    /// a sheet closed either way. One shared line, shown next to the connection
    /// banner, is enough to stop a silent failure looking like a completed action.
    var transientMessage: String?
    /// What the banner's Undo does, when the message is one that can be undone.
    var transientUndo: (@MainActor () async -> Void)?

    /// Items being re-scraped right now.
    ///
    /// A metadata refresh takes four to five seconds — the server scrapes
    /// asynchronously, so the app waits, then re-reads — and for all of that
    /// time nothing on screen changed. Right-clicking a poster, choosing Refresh
    /// Metadata and watching absolutely nothing happen is indistinguishable from
    /// a menu item that does not work, which is what it was reported as.
    ///
    /// A set rather than a flag: two refreshes can be in flight, and the tile
    /// that shows a spinner must be the tile that was asked.
    var refreshingItemIds: Set<String> = []

    var libraries: [LibraryRecord] = []
    /// Whether private libraries are on screen. Session-only and never persisted —
    /// see AppModel+Privacy.swift for why that is the point rather than an
    /// oversight.
    var isShowingPrivateLibraries = false
    /// Bumped whenever something changes what the home screen's queries return but
    /// not what it was asked to show. Revealing a private library is the case:
    /// every shelf has to be re-read, and nothing in the view's own inputs moved.
    var homeReloadToken: UInt64 = 0
    /// How many titles carry watch progress this Mac has not managed to report.
    /// Zero in the ordinary case; above zero after watching with the server away.
    var pendingOfflineProgress = 0
    /// The home screen's model while one is on screen, so a finished sync can tell
    /// it directly rather than through the view. Weak: the view owns it, and a
    /// signed-out app should not keep a screen's worth of entries alive.
    weak var homeModel: HomeModel?
    /// Whether the home screen has finished its first load. Set by HomeView.
    ///
    /// The launch screen used to lift the moment `attach` returned — before the
    /// library list was read or a single shelf had run a query — so the window went
    /// from a tidy splash to a half-built home filling in a row at a time.
    var homeDidLoad = false
    /// So the launch timing is logged once, not on every home reload.
    var didNoteReady = false

    /// When this model was built — as close to process start as the app can see.
    /// Stored rather than a `static let`: a static initialises lazily on first
    /// *access*, so reading it at the end of launch created it right then and the
    /// elapsed time came out as -0.00s. The instrument measured itself.
    let startedAt = Date()
    /// What the launch screen says it is doing, in the user's terms.
    var launchStatus = "Opening your library"
    var syncProgress: SyncProgress?
    /// Stamps each sync task so a finishing one only clears its own handle. See
    /// `startSync`.
    var syncGeneration: UInt64 = 0
    /// Libraries whose last sync missed a page. Reported in the sync panel rather
    /// than as an outage, because the server was reachable throughout.
    var lastPartialLibraries: [String] = []
    /// When the last full sync finished, for the panel to say how current the
    /// cache is without anyone having to guess.
    var lastSyncFinished: Date?
    /// The running sync, so a second press cannot start a duplicate and Stop has
    /// something to cancel. Not private: AppModel+Sync.swift owns the sync.
    var syncTask: Task<Void, Never>?
    /// The periodic pass that notices content added while the app is open. See
    /// `AppModel+AutoSync`.
    var autoSyncTask: Task<Void, Never>?
    /// The listener that re-reads the shelves when anything writes to the cache,
    /// and the debounce that collapses a batch of writes into one pass. See
    /// `AppModel+LibraryChanges`.
    var libraryChangeTask: Task<Void, Never>?
    var pendingChangeTask: Task<Void, Never>?
    var startupError: String?

    /// Whether the server answered the last time we asked. Defined in the kit —
    /// see `ConnectionState` — because mapping a transport failure onto a sentence
    /// worth reading is domain logic, not presentation.
    typealias Connection = ConnectionState

    // Written by AppModel+Sync.swift, which decides what a sync outcome means, and
    // by AppModel+Offline.swift, which is what any *other* failed request goes
    // through. Both write it through `goOffline`/`didReconnect` so the reconnect
    // probe below is started and stopped in one place.
    var connection: Connection = .unknown

    // Offline mode's state. All four are owned and explained by
    // AppModel+Offline.swift; they live here because @Observable needs its stored
    // properties in the class body. The probe task is held so sign-out and a manual
    // Retry can stop it, and `reconnectAttempts` outlives it on purpose — a server
    // that answers the cheap probe but fails every sync must keep widening its
    // backoff rather than restart it at five seconds.
    var reconnectTask: Task<Void, Never>?
    var nextReconnectAttempt: Date?
    var isCheckingConnection = false
    var reconnectAttempts = 0
    var justReconnected = false

    /// The item the player is showing, if any.
    ///
    /// Its `didSet` is what puts the app into and out of playback focus — see
    /// AppModel+Playback.swift. Hooked here rather than at the two call sites so a
    /// third one cannot forget.
    /// A page something asked the shell to open, where there was no
    /// `NavigationLink` to press — the keyboard's Return key on a wall of tiles.
    ///
    /// Through the app model for the same reason `nowPlayingItemId` is: the
    /// navigation path belongs to the shell, and handing every grid a binding
    /// to it would make the path four views' business instead of one's.
    /// The shell clears it once it has pushed.
    var requestedRoute: DetailRoute?

    var nowPlayingItemId: String? {
        didSet {
            guard oldValue != nowPlayingItemId else { return }
            playbackStateChanged()
        }
    }

    /// Held while a video plays: App Nap off, timer coalescing off, display awake.
    /// Not private: AppModel+Playback.swift owns it.
    var playbackActivity: NSObjectProtocol?

    /// Set when an automatic sync was held back during playback; `true` if the one
    /// wanted was a full pass. Nil means nothing is waiting.
    var deferredSyncIsFull: Bool?

    /// Whether libmpv loaded. False turns files mpv should have taken into
    /// server transcodes, so it is worth knowing rather than assuming.
    private(set) var mpvAvailable = false
    private(set) var mpvVersion: String?

    let capabilities = SystemCapabilities.detect()

    /// Owned here rather than by a view, because that is the entire point: the queue
    /// has to outlive whatever screen started it.
    let music = MusicPlayerModel()

    /// The probe, held so the player can wait for it.
    ///
    /// Launch does not wait — see RootView — because 0.57s of mpv initialisation in
    /// front of the first frame is 0.57s of nothing. But `mpvAvailable == false` is
    /// not "we do not know yet", it is "libmpv failed to load", and
    /// `PlaybackDecision` turns that into a *server transcode*. Anything that starts
    /// playing before the probe lands must wait for it rather than read the default.
    /// Not private: AppModel+Session.swift both builds these and tears them down, and
    /// the `private(set)` that stops views writing them is file-scoped. One setter
    /// rather than two loose ones, so the pair cannot drift out of step.
    func setTransfers(downloads: DownloadManager?, prefetcher: ArtworkPrefetcher?) {
        self.downloads = downloads
        self.prefetcher = prefetcher
    }

    var mpvProbe: Task<Void, Never>?

    func probeMPV() async {
        let version = await Task.detached(priority: .utility) { MPVRuntime.probe() }.value
        mpvVersion = version
        mpvAvailable = version != nil
    }

    var isSignedIn: Bool { client != nil }

    var serverURL: URL? { client?.session.serverURL }

    // `SyncProgress` and `SyncSummary` are declared in AppModel+Sync.swift, with the
    // loop that fills them and this file's 300-line limit in mind.

    /// What the last completed pass did. Read by the sync panel, written by the
    /// sync loop.
    var lastSyncSummary: SyncSummary?

    /// Which libraries to read and how deeply. Loaded once at launch and written
    /// back whenever the panel changes it, so the choice survives a relaunch —
    /// a preference that has to be re-made every session is not a preference.
    var syncSelection = SyncSelection.load()

    /// A session restored from disk, waiting to be wired up. Held rather than
    /// attached immediately because attaching reads the token off the client
    /// actor, which cannot be awaited from an initialiser.
    private var pendingClient: JellyfinClient?

    /// Whether the saved session is still being read.
    ///
    /// Distinct from "signed out", so the sign-in form does not flash up for the
    /// moment it takes — and, more importantly, so the window can exist while the
    /// stored session is being read.
    private(set) var isRestoring = true

    init() { adoptMusicPlayback() }

    /// Reads the saved session off the main thread.
    ///
    /// Off the main thread because it touches the filesystem, and kept out of
    /// `init()` for a reason that outlived its original cause. It used to read the
    /// Keychain, which *prompts* whenever the binary's signature no longer matches
    /// the item's ACL — every rebuild — and blocking there froze the main thread
    /// before SwiftUI had made a window, leaving the app in the Dock with no window
    /// and a system dialog behind everything. `TokenStore` cannot prompt, but a
    /// disk read still has no business on the path that draws the first frame.
    func restoreSession() async {
        let restored = await Task.detached { SessionStore.restoreClient() }.value
        pendingClient = restored
        client = restored
        isRestoring = false
    }

    /// Completes startup. Called once from the root view's task.
    ///
    /// The sync starts here rather than from the shell's `.task`, and that is the
    /// whole point: `init` sets `client` from the restored session, so `isSignedIn`
    /// is true and the shell appears *before* `attach` has built the repository. The
    /// shell's task raced it and lost, and both sync entry points then returned
    /// silently on `guard let repository` — so on every launch after the first, no
    /// sync ran at all, with no error and nothing on screen to say so.
    func start() async {
        guard let pending = pendingClient else { return }
        pendingClient = nil
        // Once per launch, before any shelf is built. See `Spotlight.beginSession`.
        _ = Spotlight.beginSession()
        launchStatus = "Reaching \(pending.session.serverName)"
        await attach(pending)
        Task { if let warning = await ServerCompatibility.check(pending.session.serverURL) { report(warning) } }
        // Before anything is read. A private library that is filtered out one query
        // too late has already been on screen.
        await applyPrivacy()
        launchStatus = "Reading your library"
        await loadCachedLibraries()
        if libraries.isEmpty { launchStatus = "Building your library for the first time" }
        await applyLaunchJobs()
        // Before the sync, which would otherwise pull the server's watch state down
        // over anything watched while it was away. See `AppModel+Outbox`.
        await flushPlaybackOutbox()
        // And after the home screen has its content. Both want the repository actor
        // at exactly this moment and only one of them is being looked at. See
        // `AppModel+Foreground`.
        await waitForHomeLoad()
        await catchUpAtLaunch()
        watchRoomIdle()
        startLibraryChangeListener()
    }

    func signedIn(_ client: JellyfinClient) async {
        await attach(client)
        await applyPrivacy()
        await loadCachedLibraries()
        // Signing in fresh takes a different path to relaunching, and a listener
        // started on only one of them is the per-surface wiring this replaced.
        startLibraryChangeListener()
        await catchUpAtLaunch()
    }
}

import SwiftUI
import LumiereKit

/// Where you are in the app. Kept as a value so the sidebar selection, the
/// content pane and the back stack all agree without cross-references.

enum Route: Hashable {
    case home
    case favourites
    case library(id: String, name: String)
    case search
    case settings
}

/// The navigation shell: sidebar plus content.
///
/// `NavigationSplitView` is AppKit's real split view underneath, so the sidebar
/// gets native translucency, the divider drag, and the collapse behaviour for free.
struct ShellView: View {
    @Bindable var app: AppModel
    let bridge: PlayerBridge
    // Not private: ShellView+Sidebar.swift binds the List selection to it.
    @State var route: Route = .home
    /// Same key as the root, which owns the window's own backing.
    @AppStorage("glassBackground") private var isGlass = true
    // Not private: ShellView+Launch.swift pushes onto it.
    @State var path = NavigationPath()
    /// The namespace the poster → detail zoom matches within. One per window;
    /// see `PosterTransition`.

    /// Whether the pill is pinned open, the page moved aside for it. Off by
    /// default: folded to its icons, it opens over the page when pointed at.
    /// The old sidebar's preference, so a Mac that kept that open keeps this open.
    @AppStorage("showsSidebar") var showsSidebar = false
    // Not private: the pill's Library Sync row opens it.
    @State var showingSyncPanel = false
    /// Set by the ceiling in `content`, so a stalled startup cannot strand the
    /// window on the launch screen.
    @State private var launchTimedOut = false
    // Not private: ShellView+Sections.swift hands it to Home and to Settings.
    @AppStorage("homeLayout") var homeLayout: HomeLayout = .classic
    // Per-library overrides of the folder/grid default, as comma-joined ids.
    // Not private: ShellView+Sections.swift reads them, and unwraps them there.
    @AppStorage("folderModeLibraries") var folderModeRaw: String = ""
    @AppStorage("gridModeLibraries") var gridModeRaw: String = ""

    var body: some View {
        ZStack {
            // Over the entire window, including the sidebar and the nav bar — a
            // launch screen with the app's chrome already drawn around it is not a
            // launch screen, it is a half-loaded app with a spinner in the middle.
            //
            // Layered *over* the shell rather than replacing it, because the shell
            // has to be alive to load: the home screen's shelves only run their
            // queries once the view exists. So the work happens behind the curtain
            // and the curtain lifts on a finished screen rather than on an empty one
            // that then fills in a row at a time.
            // A VStack rather than a `safeAreaInset` on the split view. As an inset
            // the banner drew *over* the detail column's own header — the library
            // title, item count and filter row all vanished behind it. Stacked, it
            // takes real layout space and everything below simply moves down.
            VStack(spacing: 0) {
                if let phase = connectionPhase {
                    ConnectionBanner(
                        phase: phase,
                        serverName: app.client?.session.serverName ?? "the server",
                        playableOffline: app.playableOfflineCount,
                        onRetry: { Task { await app.retryConnection() } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = app.transientMessage {
                    TransientBanner(
                        message: message,
                        onUndo: app.transientUndo.map { undo in
                            { app.transientMessage = nil; Task { await undo() } }
                        }
                    ) { app.transientMessage = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                shell
                // Outside the page's stack on purpose: a queue that stopped
                // when you changed section would not be a music player.
                if app.music.hasQueue,
                   let pipeline = app.imagePipeline,
                   let serverURL = app.serverURL {
                    MiniPlayerBar(
                        music: app.music, pipeline: pipeline, serverURL: serverURL
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(Theme.Motion.transition, value: connectionPhase)
            .animation(Theme.Motion.transition, value: app.music.hasQueue)

            // The full-window players, and the reason they vanished: they live in
            // a computed property, nothing referenced it, and a computed property
            // nobody calls still compiles. The split that moved them out took the
            // video player off screen without a single warning — no test covers
            // "is the player in the view tree", and the build stayed green.
            overlays

            // Last in the root stack, so it covers the sidebar, the nav bar and the
            // banners rather than sitting in a window that has already drawn its
            // chrome — a launch screen framed by the app's own furniture is not a
            // launch screen, it is a half-loaded app with a spinner in the middle.
            if !launchComplete {
                LaunchView(status: app.launchStatus, detail: app.startupError)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showingSyncPanel) {
            SyncPanel(app: app, onDone: { showingSyncPanel = false })
        }
        .sheet(isPresented: $app.isShowingSetupGuide) { SetupGuide(app: app) }
        .animation(Theme.Motion.transition, value: app.nowPlayingItemId)
        .animation(Theme.Motion.transition, value: app.music.isFullscreen)
        // Strips the window's title bar for the duration of playback, so the video
        // is not capped by a pale toolbar band.
        .background(WindowChrome(immersive: app.nowPlayingItemId != nil))
    }

    /// What the connection banner should say, or nil for the ordinary case where
    /// there is nothing to say at all.
    ///
    /// Derived rather than stored: the app model already holds the three facts this
    /// is made of, and a fourth field mirroring them would be a fourth thing that
    /// can disagree with the connection state.
    private var connectionPhase: ConnectionBanner.Phase? {
        if case .offline(let message) = app.connection {
            return app.isCheckingConnection
                ? .checking(message: message)
                : .offline(message: message, nextAttempt: app.nextReconnectAttempt)
        }
        // Outlives the offline state by a few seconds on purpose. A banner that
        // simply disappears has told the user nothing about why.
        return app.justReconnected ? .reconnected : nil
    }

    /// The page, with the pill floating down its left edge. See `PillSidebar`.
    private var shell: some View {
        ZStack(alignment: .topLeading) {
        NavigationStack(path: $path) {
            content
                // So a grid can open a page from the keyboard, where there
                // is no NavigationLink to press. See `AppModel.requestedRoute`.
                .onChange(of: app.requestedRoute) {
                    guard let route = app.requestedRoute else { return }
                    path.append(route)
                    app.requestedRoute = nil
                }
                // Deliberately no canvas fill: the root supplies the background — glass or
    // flat — and repainting it here is what hid it.
                .navigationDestination(for: DetailRoute.self) { route in
                    // The poster you clicked becomes the page. See
                    // `PosterTransition` for why the namespace travels
                    // through the environment.
                    detailPage(for: route)
                        .posterTransitionDestination()
                }
                // Genres push onto the same stack rather than switching
                // section, so a genre card behaves like a poster: it has a
                // back button and Home is still where you are.
                .navigationDestination(for: GenreRoute.self) { genrePage(for: $0) }
                // "See All" on a Latest shelf. Pushed like a genre rather than
                // switching section, so the shelf you came from is one Back away.
                .navigationDestination(for: LatestRoute.self) { latestPage(for: $0) }
                .navigationDestination(for: ResumeRoute.self) { resumePage($0) }
                .navigationDestination(for: NextUpRoute.self) { _ in nextUpPage }
                // Cast members push onto the same stack for the same reason
                // genres do: following a face out of a film and coming back to
                // it is one history, and the person page is reachable from a
                // detail page that is itself somewhere in this stack.
                .navigationDestination(for: PersonRoute.self) { personPage(for: $0) }
        }
            // Room kept for the pill — the collapsed one always, the whole of it
            // when pinned open. Opened by pointing, it floats over the page instead.
            .padding(.leading, (showsSidebar ? PillSidebar.expandedWidth : PillSidebar.collapsedWidth)
                     + PillSidebar.margin * 2)
            PillSidebar(
                app: app, route: route, isPinned: $showsSidebar,
                onGenre: { path.append(GenreRoute(name: $0)) },
                onSync: { showingSyncPanel = true }
            )
            .padding(PillSidebar.margin)
        }
        .animation(Theme.Motion.transition, value: showsSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .openDetail)) { note in
            if let id = note.object as? String, id.hasPrefix("play:") { app.nowPlayingItemId = String(id.dropFirst(5)) } else if let id = note.object as? String { path.append(DetailRoute(itemId: id)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
            if !path.isEmpty {
                path.removeLast()
            } else if route == .settings {
                NotificationCenter.default.post(name: .settingsBack, object: nil)
            }
        }
        .onChange(of: app.pendingRoute) {
            guard let requested = app.pendingRoute else { return }
            // The path is cleared here as well as in the route handler below, and
            // that is the fix for "Home does nothing".
            //
            // Drilling from Home into a detail page pushes onto the stack without
            // changing `route` — you are still in the Home section. Pressing Home
            // then assigned `.home` over `.home`, which is not a change, so
            // `onChange(of: route)` never fired and the stack was never emptied:
            // the button lit up as current while the detail page stayed on screen.
            // Nothing was broken about the button; the only thing that needed
            // undoing was the one thing that did not run.
            path = NavigationPath()
            route = requested
            app.pendingRoute = nil
        }
        .onChange(of: route) {
            // Changing section resets the drill-down; otherwise the back button
            // would walk you into the previous section's items.
            path = NavigationPath()
        }
        .task {
            openLaunchRoute()
            app.applyForcedOfflineIfRequested()
            await app.offerSetupIfNew()
            // Syncing is owned by AppModel.start()/signedIn(), which run after the
            // repository exists. Driving it from here raced that and silently did
            // nothing — see the note on AppModel.start().
        }
        .animation(Theme.Motion.transition, value: launchComplete)
        .task {
            // A ceiling on the splash, whatever is happening behind it. Readiness
            // waits on a first sync and a first render, and neither is worth betting
            // a blank window on: if either stalls, the app appears anyway rather
            // than stranding someone on a launch screen with no way past it.
            try? await Task.sleep(for: .seconds(20))
            launchTimedOut = true
        }
    }

    // MARK: - Content

    /// Ready, or waited long enough.
    // Not private: the root overlay in `body` reads it.
    var launchComplete: Bool { app.isReady || launchTimedOut }

    @ViewBuilder
    private var content: some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            // Offline with an empty cache is the one case where the banner is not
            // enough: every section below would render as a blank page, and a
            // blank page reads as "your library is empty" rather than "we never
            // reached the server". Handled here rather than in each section, since
            // no library means there is nothing for any of them to show.
            if app.connection.isOffline, app.libraries.isEmpty, route != .settings {
                EmptyStateView(reason: .offline(
                    serverName: app.client?.session.serverName ?? "the server",
                    retry: { Task { await app.retryConnection() } }
                ))
            } else {
                sections(repository: repository, pipeline: pipeline, serverURL: serverURL)
            }
        }
    }
}

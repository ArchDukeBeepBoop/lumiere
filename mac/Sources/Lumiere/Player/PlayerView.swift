import SwiftUI
import AVKit
import LumiereKit
import LumierePlayer

/// The player.
///
/// Chrome auto-hides after a few idle seconds and returns on any pointer
/// movement, as every video player does — the picture is the content, and
/// controls that never leave read as an app window rather than a film.
struct PlayerView: View {
    let itemId: String
    /// The version chosen on the detail page, if any.
    var preferredSourceId: String?
    let client: JellyfinClient
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let capabilities: SystemCapabilities
    let mpvAvailable: Bool
    /// Resolves once the mpv probe has finished. See `AppModel.mpvReady`.
    ///
    /// `mpvAvailable` above is read when this view is built, which for a file opened
    /// in the first moments after launch is before the probe has answered — and a
    /// false there is not "unknown", it is "use the server", which silently turns a
    /// direct play into a transcode.
    var mpvReady: (() async -> Bool)?
    let bridge: PlayerBridge
    let onClose: () -> Void

    @State var model: PlayerModel?
    @State var showsChrome = true
    /// Keep Watching pressed on this item's Up Next. See `UpNextStage`.
    @State var upNextDismissedFor: String?
    /// The time and a line of progress, kept a few seconds after the controls go.
    @State var showsGlance = false
    @State var showsSettings = false
    /// Which tab of the tracks panel is open, if any.
    ///
    /// Owned here rather than by `PlayerControls` because the idle countdown in
    /// PlayerView+Input.swift has to see it: chrome that fades while someone is
    /// picking a subtitle track takes the list with it.
    @State var openTab: PlayerTrackPanel.Tab?
    /// Whether the Up Next list is open. Separate from `openTab` because it is a
    /// separate panel with a separate button — see `PlayerQueuePanel`.
    @State var showsQueue = false
    @State var idleTask: Task<Void, Never>?
    /// Throttles the hover-driven wake, which otherwise fires per pointer sample.
    @State var lastWake = Date.distantPast
    /// Movement does not summon the chrome again until this moment passes.
    ///
    /// Set when the pointer leaves the bar. Without it, "hide the moment the mouse
    /// leaves" and "any movement brings the chrome back" are the same event: the
    /// gesture that takes the pointer off the bar is itself movement, so the bar
    /// would vanish and reappear inside one frame. A short window lets the leaving
    /// gesture finish before move-to-summon starts working again.
    /// Not private: the countdown that reads it lives in PlayerView+Input.swift.
    @State var suppressWakeUntil = Date.distantPast
    @State var statsTask: Task<Void, Never>?
    @State var publishTask: Task<Void, Never>?
    /// Holds the PiP controller for the lifetime of the player. AVKit ends the
    /// session the moment its controller is deallocated, so it cannot be built
    /// on demand inside the toggle.
    @State var pip = PictureInPictureBox()
    /// The player's own size, for the panels that have to fit inside it.
    ///
    /// Fullscreen on this Mac is 1512pt wide; a 344pt panel is a fifth of that and
    /// an episode list inside it wrapped every title to three lines. The panel now
    /// takes a share of whatever it is floating over. See `Theme.PlayerMetric.panel`.
    @State var playerSize: CGSize = .zero
    /// Whether the one-time key card is up. Set at launch from the preference,
    /// which is written the moment it is shown — see `PlayerKeyCard`.
    @State var showsKeyCard = false

    /// Whether the pointer is on the transport bar or the title bar.
    ///
    /// The chrome never hides while it is, however long the pointer sits still.
    /// Without this the one-second timeout below would take the bar away from
    /// under the cursor while it was being aimed at — a stationary pointer over a
    /// button is someone deciding, not someone finished. Not private: the hover
    /// that sets it is on the bars themselves, and the countdown that reads it is
    /// in PlayerView+Input.swift.
    @State var isPointerOnChrome = false

    /// How long the pointer must sit still, away from the bar, before the chrome
    /// goes. One second, because with the hold above it now only ever measures
    /// time spent over the *picture*, where there is nothing to aim at and the
    /// controls are simply in the way of the film.
    /// Not private: the countdown that reads it lives in PlayerView+Input.swift.
    var idleTimeout: Duration { .seconds(1) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let model {
                Group {
                    videoSurface(for: model)
                        // Up Next: the picture steps back into the corner.
                        .frame(width: upNext(model) == nil ? nil : playerSize.width * 0.4,
                               height: upNext(model) == nil ? nil : playerSize.height * 0.4)
                        .clipShape(RoundedRectangle(cornerRadius: upNext(model) == nil ? 0 : 14,
                                                    style: .continuous))
                        .padding(upNext(model) == nil ? 0 : 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .animation(.easeInOut(duration: 0.5), value: upNext(model)?.id)
                    if let next = upNext(model) {
                        UpNextStage(
                            next: next, pipeline: pipeline, serverURL: client.session.serverURL,
                            isPlaying: model.isPlaying,
                            onPlayNow: { playNextEpisode(model) },
                            onKeepWatching: { upNextDismissedFor = model.itemId }
                        )
                        .transition(.opacity)
                    }

                    // Outside the switch: in `.preparing` the whole chrome was absent,
                    // and with it the only Close button — a file that never started
                    // playing had no way out at all.
                    escapeHatch(model)
                    PlayerOSD(model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    PlayerPauseCard(model: model, isShown: !showsChrome && !model.isPlaying && model.state == .playing)
                    PlayerGlance(model: model, isShown: showsGlance && !showsChrome && model.isPlaying)

                    switch model.state {
                    case .preparing:
                        preparing
                    case .playing, .paused:
                        chrome(for: model)
                    case .engineNotAvailable(let decision):
                        engineMissing(decision)
                    case .failed(let message):
                        failure(message)
                    }
                }
                // Everything over the picture is dark chrome regardless of the
                // app's appearance, because the surface underneath is a film on
                // black rather than a page. Forcing the scheme here is what makes
                // `Material` and the appearance-dynamic tokens — the route badge,
                // the failure red — resolve to their dark values over video.
                //
                // On the group rather than on the ZStack on purpose: the settings
                // sheet is presented from the ZStack below, and it is a normal app
                // panel that should keep the appearance the user chose.
                .environment(\.colorScheme, .dark)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(KeyCaptureView(
            onKey: { key in handle(key) },
            onScroll: { seconds in handleScroll(seconds: seconds) },
            onKeyUp: { key in handleKeyUp(key) }
        ))
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        // Play All: the next episode when this one ends, where asked for.
        .onChange(of: model?.endedCount) {
            // "Stop after this episode" wins over going on. See SleepTimer.
            if SleepTimer.takeEndOfEpisode() { onClose(); return }
            if Preference.playsNextAutomatically.value, let model, StillWatching.mayAdvance() {
                playNextEpisode(model)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepTimerFired)) { _ in onClose() }
        .onDisappear { if MiniPlayer.isOn { MiniPlayer.toggle() } }
        .onChange(of: bridge.token) {
            guard let command = bridge.pending else { return }
            perform(command)
        }
        .task {
            // Written when it is *shown*, not when it is dismissed: a card that
            // came back because the app was quit while it was open would have
            // failed at the one thing it does.
            if !UserDefaults.standard.bool(forKey: PlayerKeyCard.storageKey) {
                UserDefaults.standard.set(true, forKey: PlayerKeyCard.storageKey)
                showsKeyCard = true
            }

            // `let`: PlayerModel is a reference type, so setting a property on it
            // needs no mutable binding. `var` compiled and warned, and the warning
            // only surfaced on a cold rebuild of this file — which is exactly the
            // kind that reaches a release build having passed every warm check.
            let model = model ?? PlayerModel(
                itemId: itemId, client: client,
                repository: repository, capabilities: capabilities
            )
            model.preferredSourceId = preferredSourceId
            self.model = model
            let engineAvailable = await mpvReady?() ?? mpvAvailable
            await model.start(mpvAvailable: engineAvailable)
            startStatisticsPolling()
            startBridgePublishing()
            wakeChrome()
        }
        .onDisappear {
            idleTask?.cancel()
            statsTask?.cancel()
            publishTask?.cancel()
            // Leaving the player with the pointer still hidden would strand it
            // invisible over the library.
            NSCursor.unhide()
            // Playback menus grey out rather than acting on a player that is gone.
            bridge.menuState = PlayerMenuState()
            // The resume position is written here. Closing the window must not
            // be a way to lose your place.
            let model = self.model
            Task { await model?.finish() }
        }
    }

    @ViewBuilder
    private func videoSurface(for model: PlayerModel) -> some View {
        Group {
            if let engine = model.avEngine {
                VideoSurface(player: engine.player, pip: pip).ignoresSafeArea()
            } else if let engine = model.mpvEngine {
                MPVSurface(view: engine.view).ignoresSafeArea()
            }
        }
        // Double-click the picture to enter full screen, and again to leave — what
        // every video player on the platform does, and the gesture people try first.
        //
        // The count-2 gesture is declared before the count-1 one so that a double
        // click is not consumed as two single clicks; SwiftUI resolves the higher
        // count first only when it is attached first.
        //
        // The sides skip, as on iPhone and iPad: a double-click in the left
        // third goes back a step, the right third forward. The middle keeps
        // full screen.
        .gesture(SpatialTapGesture(count: 2).onEnded { tap in
            let width = max(1, playerSize.width)
            let step = Double(Preference.seekStepSeconds.value)
            if tap.location.x < width / 3 {
                Task { await model.keyStep(by: -step, isRepeat: false) }
            } else if tap.location.x > width * 2 / 3 {
                Task { await model.keyStep(by: step, isRepeat: false) }
            } else {
                toggleFullScreen()
            }
        })
        .onTapGesture {
            // A click on the picture is also how you put the tracks panel away.
            // Anywhere-else-to-dismiss is what every menu on the platform does,
            // and the panel is drawn in-window, so nothing does it for free.
            openTab = nil
            showsQueue = false
            wakeChrome()
        }
        // Movement, not only clicks. The controls used to return only when you
        // clicked the picture, which in a video player means either pausing or
        // guessing — and is most of what made the chrome feel clunky. Every player
        // on the platform brings them back when the pointer moves.
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
    }

}

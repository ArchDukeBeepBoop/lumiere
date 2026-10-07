import SwiftUI
import LumiereKit

/// The layer over the picture: scrims, the title bar, the transport, the prompt.
///
/// Split from PlayerView.swift for the project's 300-line limit. It reads
/// PlayerView's state rather than holding any — `showsChrome` in particular, which
/// the idle timer in PlayerView+Input.swift owns.
extension PlayerView {

    // MARK: - Chrome

    /// A Close button in the corner whatever state the player is in.
    @ViewBuilder
    /// Not private: called from `body` in PlayerView.swift, and Swift's `private`
    /// is file-scoped.
    func escapeHatch(_ model: PlayerModel) -> some View {
        if case .playing = model.state {
            // The full chrome already draws one, and two would overlap.
            EmptyView()
        } else if case .paused = model.state {
            EmptyView()
        } else {
            VStack {
                HStack {
                    Spacer()
                    PlayerCloseButton(action: onClose)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.shelfInset)
            .padding(.top, Theme.Space.xl)
        }
    }

    /// Not private: called from `body` in PlayerView.swift.
    func chrome(for model: PlayerModel) -> some View {
        ZStack {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { playerSize = geometry.size }
                    .onChange(of: geometry.size) { playerSize = geometry.size }
            }
            .allowsHitTesting(false)

            // Ambient mode dims everything *around* the picture rather than the
            // picture itself, so a lit room stops competing with the film.
            if model.ambientMode {
                Color.black.opacity(0.55).ignoresSafeArea().allowsHitTesting(false)
            }

            // The scrims fade with the chrome they exist to serve. First in the
            // stack, so nothing they exist to make legible is drawn under them —
            // the prompt included — and non-interactive, so a click anywhere on
            // the picture still reaches the video surface underneath.
            Group {
                PlayerScrim(edge: .top)
                PlayerScrim(edge: .bottom)
            }
            .opacity(showsChrome ? 1 : 0)
            .animation(chromeAnimation, value: showsChrome)

            // Outside the opacity below on purpose: the prompt is the one piece of
            // chrome that has to be reachable without moving the mouse first, so it
            // does not fade with the rest.
            // With the Up Next stage up, it is the offer — not a second one.
            let prompts = model.activePrompts.filter { prompt in
                if case .nextEpisode = prompt { return upNext(model) == nil }
                return true
            }
            if !prompts.isEmpty {
                // The bottom-right corner, as low as it can sit without ever
                // touching the transport bar — and at one fixed height, not two.
                //
                // The two-height version is what made it dodge the pointer: it sat
                // low with the chrome hidden and rose as the bar appeared, and the
                // bar appears the moment you move the mouse. It moved out from under
                // the cursor exactly as you reached for it, every time.
                // `promptLift` is derived from the bar's own measured height, so the
                // clearance holds if the bar is ever restyled.
                //
                // One row, flush to the right edge. Where a skip offer and a
                // next-episode offer are both live they sit side by side rather than
                // one hiding the other.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(Array(prompts.enumerated()), id: \.element) { _, prompt in
                            PlayerPrompt(
                                prompt: prompt,
                                onSkip: { target, label in
                                    // Zero is Start Over, which also has to
                                    // retire the notice — a seek alone leaves it
                                    // offering to do what it just did.
                                    Task {
                                        if target == 0 {
                                            await model.startOver()
                                        } else {
                                            await model.skip(to: target, label: label)
                                        }
                                    }
                                },
                                onNextEpisode: { playNextEpisode(model) },
                                isPlaying: model.isPlaying
                            )
                        }
                    }
                    .padding(.bottom, Theme.PlayerMetric.promptLift)
                    .padding(.trailing, Theme.PlayerMetric.promptInset)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(spacing: 0) {
                PlayerTitleBar(
                    model: model, pipeline: pipeline,
                    serverURL: client.session.serverURL, onClose: onClose
                )
                    .offset(y: showsChrome ? 0 : -Theme.PlayerMetric.chromeSlide)
                    .onHover { onChromeHover($0) }
                Spacer()
                PlayerControls(
                    model: model,
                    serverURL: client.session.serverURL,
                    pipeline: pipeline,
                    // The *model's* id, not the view's. `itemId` here is a `let`
                    // handed down by the parent and never changes; taking the next
                    // episode rebuilds the model in place, so the trickplay preview
                    // kept building its URLs and its cache key from the episode you
                    // had just finished while `model.trickplay` described the new
                    // one — a scrub bar showing the previous episode's frames at
                    // the wrong timestamps.
                    itemId: model.itemId,
                    showsSettings: $showsSettings,
                    openTab: $openTab,
                    showsQueue: $showsQueue,
                    onToggleFullScreen: toggleFullScreen,
                    onPictureInPicture: togglePictureInPicture,
                    onPlayEpisode: { play($0) },
                    playerSize: playerSize
                )
                // A tighter inset than the title's `shelfInset`: the bar is
                // already capped and centred, so this only bites in a window too
                // narrow for the cap, which is exactly where the space is needed.
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.PlayerMetric.barInset)
                .offset(y: showsChrome ? 0 : Theme.PlayerMetric.chromeSlide)
                .onHover { onChromeHover($0) }
            }
            .opacity(showsChrome ? 1 : 0)
            .animation(chromeAnimation, value: showsChrome)

            panels(for: model)

            if model.showsStatisticsHUD {
                StatisticsHUD(model: model)
            }

            settingsOverlay(model)

            // What the player just did on its own, bottom-left so it never
            // sits under the skip prompt on the right.
            if let action = model.lastAction {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: Theme.Space.sm) {
                            Text(action.text)
                                .font(Theme.Font.cardTitle)
                                .foregroundStyle(Theme.Palette.onPlayerChrome)
                            Button("Undo") {
                                Task { await model.undoLastAction() }
                            }
                            .buttonStyle(.plain)
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.PlayerPalette.primaryGlyph)
                        }
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.sm)
                        .background(Theme.PlayerPalette.surfaceBottom, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.PlayerPalette.surfaceStroke) }
                        Spacer()
                    }
                }
                .padding(.leading, Theme.Space.xl)
                .padding(.bottom, Theme.PlayerMetric.promptLift)
                .transition(.opacity)
            }

            // Once, over the first film. See `PlayerKeyCard`.
            if showsKeyCard {
                PlayerKeyCard { showsKeyCard = false }
                    .transition(.opacity)
            }
        }
    }

    /// The tracks panel and the Up Next list, floating above the transport bar.
    ///
    /// Drawn here rather than as an overlay on `PlayerControls`, and that is the
    /// whole fix: an overlay is proposed its parent's size, so a panel hung off the
    /// bar could never be taller than the bar — Up Next showed two episodes however
    /// much height it asked for. Over the player it is bounded by the picture, which
    /// is what `panelMaxHeight(in:rows:)` was always describing.
    ///
    /// Outside the chrome's fade, like the prompt: a panel you opened deliberately
    /// should not dim because the pointer went still. Nothing hides it but closing
    /// it — see the idle timer's guards in PlayerView+Input.swift.
    @ViewBuilder
    private func panels(for model: PlayerModel) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if showsQueue {
                PlayerQueuePanel(
                    model: model,
                    onPlayEpisode: { play($0) },
                    onClose: { showsQueue = false },
                    width: Theme.PlayerMetric.panelWidth(in: playerSize),
                    maxHeight: Theme.PlayerMetric.panelMaxHeight(
                        in: playerSize, rows: Theme.PlayerMetric.queueTargetRows
                    )
                )
                .transition(.opacity)
            } else if openTab != nil {
                PlayerTrackPanel(
                    model: model, tab: $openTab,
                    width: Theme.PlayerMetric.panelWidth(in: playerSize),
                    maxHeight: Theme.PlayerMetric.panelMaxHeight(in: playerSize),
                    pipeline: pipeline, serverURL: client.session.serverURL
                )
                .transition(.opacity)
            }
        }
        .padding(.bottom, Theme.PlayerMetric.promptLift)
        .padding(.trailing, Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(Theme.Motion.transition, value: showsQueue)
        .animation(Theme.Motion.transition, value: openTab)
    }

    /// Chrome arrives faster than it leaves.
    ///
    /// Controls you just asked for should already be there; controls you stopped
    /// using should drift out rather than blink off. One curve for both directions
    /// makes the fast case feel slow or the slow case feel abrupt — there is no
    /// single duration that is right for a summons and a dismissal.
    private var chromeAnimation: Animation {
        showsChrome ? Theme.Motion.chromeReveal : Theme.Motion.chrome
    }


    /// The next episode when Up Next should take the screen: the credits have
    /// started (the Next offer is live), it is switched on, and Keep Watching
    /// has not been pressed for this item.
    func upNext(_ model: PlayerModel) -> LibraryEntry? {
        guard Preference.showsUpNextStage.value, upNextDismissedFor != model.itemId,
              let next = model.nextEpisode,
              model.activePrompts.contains(where: { if case .nextEpisode = $0 { true } else { false } })
        else { return nil }
        return next
    }
}

import SwiftUI
import LumiereKit
import LumierePlayer

/// The transport bar.
///
/// One designed surface centred over the bottom of the picture rather than
/// controls scattered across it: a tinted slab with a hairline edge, the scrubber
/// across the top of it and the transport beneath, everything on one grid.
///
/// The row is read as three groups. Volume sits left, the transport is centred on
/// the play button — the one control with any weight on the bar — and everything
/// that opens something else is collected on the right. That ordering is the whole
/// hierarchy: there is exactly one primary, and it is the only filled shape.
struct PlayerControls: View {
    let model: PlayerModel
    let serverURL: URL
    let pipeline: ImagePipeline
    let itemId: String

    @Binding var showsSettings: Bool
    /// Which tab of the tracks panel is open, or nil for closed. Owned by
    /// `PlayerView` because the chrome must not auto-hide while it is up.
    @Binding var openTab: PlayerTrackPanel.Tab?
    /// Whether the Up Next list is showing. Its own state rather than a fifth tab —
    /// see `PlayerQueuePanel`.
    @Binding var showsQueue: Bool
    let onToggleFullScreen: () -> Void
    let onPictureInPicture: () -> Void
    /// Switches to another episode. Nil where there is nothing to switch to — the
    /// buttons are hidden in that case rather than present and inert.
    var onPlayEpisode: ((LibraryEntry) -> Void)?
    /// The whole player's size, not the bar's — the panel floats over the picture,
    /// so the picture is what it has to fit inside.
    var playerSize: CGSize = .zero

    @State var isScrubbing = false
    @State var scrubFraction: Double = 0
    @State var hoverFraction: Double?
    /// The remaining time reads as the clock time it ends at while hovered.
    @State private var isHoveringPlay = false

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            scrubberRow
            transportRow
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
        // No plate, and no width cap: the controls sit straight on the picture and
        // run the full width of the window.
        //
        // What made the slab defensible was legibility, and that job belongs to
        // `PlayerScrim(edge: .bottom)`, which is already drawn under this and fades
        // with it. The plate was doing it a second time, in a hard-edged rounded
        // rectangle that announced itself as a widget floating over the film —
        // and capped at `barMaxWidth`, so on a wide window the scrubber stopped
        // short of the picture it was scrubbing.
        // No panel overlay any more. An overlay is proposed its parent's size, so
        // hanging the panels off this bar capped them at the bar's own height —
        // whatever height they asked for, Up Next drew two episodes. They are drawn
        // over the player in `PlayerView+Chrome` instead.
        .animation(Theme.Motion.transition, value: openTab)
    }

    // MARK: - Transport

    /// Three groups on one row: volume left, transport centred, everything that
    /// opens something else on the right.
    ///
    /// The window can be as narrow as 720, and at that width the full row does not
    /// fit. The transport is not what gives way — losing a chapter button to make
    /// room for a volume slider is the wrong trade — so `ViewThatFits` drops the
    /// slider first and leaves the mute button, rather than letting the three
    /// groups overlap each other.
    private var transportRow: some View {
        ViewThatFits(in: .horizontal) {
            row(showsVolumeSlider: true)
            row(showsVolumeSlider: false)
        }
    }

    private func row(showsVolumeSlider: Bool) -> some View {
        HStack(spacing: Theme.Space.md) {
            volumeControl(showsSlider: showsVolumeSlider)
                .frame(maxWidth: .infinity, alignment: .leading)
            centreCluster
            secondaryCluster
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var centreCluster: some View {
        HStack(spacing: Theme.Space.xs) {
            // Episode navigation sits outside the chapter controls, because they are
            // different questions — "somewhere else in this file" against "a
            // different file entirely". Only shown for episodes that have a
            // neighbour, so a film never carries two dead buttons.
            if model.previousEpisode != nil {
                PlayerIconButton(systemName: "backward.frame.fill", help: "Previous episode") {
                    if let previous = model.previousEpisode { onPlayEpisode?(previous) }
                }
            }

            PlayerIconButton(systemName: "backward.end.fill", help: "Previous chapter") {
                Task { await model.skipChapter(forward: false) }
            }
            PlayerIconButton(systemName: "gobackward.15", help: "Back 15 seconds") {
                Task { await model.skip(by: -15) }
            }

            playButton
                .padding(.horizontal, Theme.Space.sm)

            PlayerIconButton(systemName: "goforward.15", help: "Forward 15 seconds") {
                Task { await model.skip(by: 15) }
            }
            PlayerIconButton(systemName: "forward.end.fill", help: "Next chapter") {
                Task { await model.skipChapter(forward: true) }
            }

            if model.nextEpisode != nil {
                PlayerIconButton(systemName: "forward.frame.fill", help: "Next episode") {
                    if let next = model.nextEpisode { onPlayEpisode?(next) }
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            Task { await model.togglePlayPause() }
        } label: {
            ZStack {
                Circle().fill(Theme.PlayerPalette.primaryFill)
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Theme.PlayerMetric.primaryGlyph, weight: .semibold))
                    .foregroundStyle(Theme.PlayerPalette.primaryGlyph)
            }
            .frame(
                width: Theme.PlayerMetric.primaryButton,
                height: Theme.PlayerMetric.primaryButton
            )
            // The same lift every card in the app uses, so the one button on the
            // bar answers the pointer the way a poster does.
            .scaleEffect(isHoveringPlay ? Theme.Elevation.hoverScale : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringPlay = $0 }
        .animation(Theme.Motion.hover, value: isHoveringPlay)
        .labelledHelp(model.isPlaying ? "Pause" : "Play")
    }

    private var secondaryCluster: some View {
        HStack(spacing: Theme.Space.xxs) {
            // A quiet status rather than a control: it appears only once the speed
            // is off normal, which is the only time anyone needs telling.
            if abs(model.playbackSpeed - 1) > 0.001 {
                speedPill
            }

            // Beside the tracks button and before it: which file to play is a
            // bigger question than which subtitle track to play it with. Hidden
            // where there is nothing to switch to — a film — rather than present
            // and inert.
            if model.queue.count > 1, onPlayEpisode != nil {
                PlayerIconButton(
                    systemName: "list.and.film",
                    help: "Up Next",
                    isActive: showsQueue
                ) {
                    openTab = nil
                    showsQueue.toggle()
                }
            }

            // The current audio and subtitle choice, in the chrome rather than
            // two levels into a panel. It is the most-changed setting in an
            // anime library, and the icon alone never said what was selected —
            // so checking whether you were on the dub meant opening the panel.
            trackSummaryButton
            PlayerIconButton(systemName: "gearshape.fill", help: "Playback settings") {
                // The sheet covers the panel anyway; leaving it open would put it
                // back underneath when the sheet is dismissed.
                openTab = nil
                showsQueue = false
                showsSettings = true
            }
            // Picture in Picture on every file: AVKit's own on the AVPlayer
            // path, and on mpv — whose GL surface AVKit cannot take — the
            // window shrunk to a small frame floating above everything. See
            // `PlayerView.togglePictureInPicture`.
            PlayerIconButton(
                systemName: "pip", help: "Picture in Picture (P)", action: onPictureInPicture
            )
            PlayerIconButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                help: "Full screen",
                action: onToggleFullScreen
            )
        }
    }

    private var speedPill: some View {
        Button { openTab = .speed } label: {
            // The same formatting the settings panel uses, so "1.25×" means the
            // same thing in both places.
            Text(String(format: "%.2f×", model.playbackSpeed))
                .font(Theme.Font.playerTab)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(
                    Capsule().fill(Theme.PlayerPalette.controlHover)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .labelledHelp("Playback speed")
    }

    // MARK: - Volume

}

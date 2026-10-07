import SwiftUI
import LumiereKit

/// The scrubber: the bar, its buffered band, its chapter marks, and the trickplay
/// card that follows the cursor.
///
/// Split out of PlayerControls.swift to keep it under the project's 300-line
/// limit. No state of its own — it reads PlayerControls'.
extension PlayerControls {

    // MARK: - Row

    var scrubberRow: some View {
        HStack(spacing: Theme.Space.lg) {
            Text(isScrubbing ? PlayerModel.timecode(scrubFraction * model.duration)
                             : model.elapsedText)
                .font(Theme.Font.playerTimecode)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .frame(width: timecodeWidth, alignment: .leading)

            scrubber

            // The time left, and under it when it ends, always — as tvOS
            // shows both. The question asked at night is rarely "how long"
            // but "until when", and it was only answered on hover.
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.remainingText)
                    .font(Theme.Font.playerTimecode)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                Text(endsAtText.capitalizingFirst)
                    .font(Theme.Font.trickplayTimecode)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary.opacity(0.75))
            }
            .frame(minWidth: timecodeWidth, alignment: .trailing)
            .fixedSize()
        }
    }

    /// Wide enough for `-1:02:03` without the bar shifting when a film crosses an
    /// hour or the sign appears.
    private var timecodeWidth: CGFloat { 68 }

    /// "ends 11:40 PM", at the current speed.
    var endsAtText: String {
        let left = max(0, model.duration - model.position) / max(model.playbackSpeed, 0.1)
        return "ends " + Date().addingTimeInterval(left).formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Bar

    var scrubber: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let fraction = isScrubbing ? scrubFraction : model.progressFraction
            let active = isScrubbing || hoverFraction != nil || model.keyPreviewSeconds != nil
            let height = active
                ? Theme.PlayerMetric.scrubHeightActive
                : Theme.PlayerMetric.scrubHeight

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.PlayerPalette.scrubTrack)
                    .frame(height: height)

                // How much is downloaded ahead of the picture. Only mpv reports a
                // cache depth, so on the AVPlayer path this band is simply absent
                // rather than guessed at — the same rule the statistics HUD follows.
                if let buffered = model.bufferedFraction {
                    Capsule()
                        .fill(Theme.PlayerPalette.scrubBuffered)
                        .frame(width: width * buffered, height: height)
                }

                Capsule()
                    .fill(Theme.PlayerPalette.scrubPlayed)
                    .frame(width: width * fraction, height: height)

                chapterMarkers(width: width, height: height)

                handle(width: width, fraction: fraction, active: active)
            }
            .animation(Theme.Motion.hover, value: active)
            .frame(height: Theme.PlayerMetric.scrubHitHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                            Task { await model.beginScrub() }
                        }
                        scrubFraction = max(0, min(1, value.location.x / width))
                        // The picture follows the cursor rather than waiting for the
                        // release — which is the single thing that made scrubbing
                        // feel unresponsive. The model coalesces: one seek out at a
                        // time, newest target wins, so a 4K file never builds a
                        // backlog it then has to lurch through.
                        let target = scrubFraction * model.duration
                        Task { await model.scrub(to: target) }
                    }
                    .onEnded { value in
                        let target = max(0, min(1, value.location.x / width))
                        scrubFraction = target
                        Task {
                            await model.endScrub(at: target * model.duration)
                            // Cleared only once the exact seek has landed. Dropping
                            // it first let the bar snap back to the old position for
                            // the frame or two before the engine caught up.
                            isScrubbing = false
                        }
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverFraction = max(0, min(1, point.x / width))
                case .ended:
                    hoverFraction = nil
                }
            }
            // Above the bar, and out of it: the card's own bottom edge is placed
            // against the top of the scrub area, so nothing has to know how tall a
            // trickplay sheet's cells happen to be.
            // A zero-height line at the top of the bar, with the card hung from
            // its bottom edge: it can only grow upwards, whatever height the
            // still turns out to be. An alignment guide did this before and put
            // the server's previews under the bar once real sheets arrived.
            .overlay(alignment: .topLeading) {
                Color.clear.frame(width: width, height: 0)
                    .overlay(alignment: .bottomLeading) {
                        trickplayPreview(width: width)
                            .padding(.bottom, previewClearance)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            }
        }
        .frame(height: Theme.PlayerMetric.scrubHitHeight)
    }

    /// Room under the card, so the handle — at its dragging size — always
    /// shows clear of the still: at least ten points between the handle's top
    /// and the card's bottom, and never less than the usual lift.
    private var previewClearance: CGFloat {
        let handleTop = Theme.PlayerMetric.handleActive / 2 - Theme.PlayerMetric.scrubHitHeight / 2
        return max(Theme.PlayerMetric.trickplayLift, handleTop + 10)
    }

    /// Grows on hover and again while dragging.
    ///
    /// That is the affordance: a 6pt line does not look grabbable, and a handle
    /// that is already large enough to grab is a handle that obscures the picture
    /// it is drawn over for the whole film.
    private func handle(width: CGFloat, fraction: Double, active: Bool) -> some View {
        let size = active ? Theme.PlayerMetric.handleActive : Theme.PlayerMetric.handle
        return Circle()
            .fill(Theme.PlayerPalette.handle)
            // One handle, one shadow — it is what keeps a white dot visible over a
            // white scene, and there is exactly one of it on screen.
            .shadow(
                color: Theme.PlayerPalette.handleShadow,
                radius: Theme.PlayerMetric.handleShadow,
                y: Theme.PlayerMetric.handleShadowY
            )
            .frame(width: size, height: size)
            .offset(x: width * fraction - size / 2)
    }

    /// Chapter boundaries.
    ///
    /// Full-height notches rather than the old floating hairlines: at 2pt on a 4pt
    /// bar they read as artefacts, and they were drawn in the chrome colour, so a
    /// mark on the played gold and a mark on the empty track were two different
    /// things. One dark notch punched through the bar reads the same everywhere.
    @ViewBuilder
    func chapterMarkers(width: CGFloat, height: CGFloat) -> some View {
        if model.chapters.count > 1, model.duration > 0 {
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { _, chapter in
                let fraction = chapter.startSeconds / model.duration
                if fraction > 0.001 && fraction < 0.999 {
                    Capsule()
                        .fill(Theme.PlayerPalette.chapterMark)
                        .frame(width: Theme.PlayerMetric.chapterMarkWidth, height: height)
                        .offset(x: width * fraction - Theme.PlayerMetric.chapterMarkWidth / 2)
                }
            }
        }
    }

    private var keyFraction: Double? {
        guard let seconds = model.keyPreviewSeconds, model.duration > 0 else { return nil }
        return max(0, min(1, seconds / model.duration))
    }

    @ViewBuilder
    func trickplayPreview(width: CGFloat) -> some View {
        // The pointer's place, else an arrow key's: every press shows where it
        // went, and a held arrow's scan runs the preview along the bar.
        if let fraction = isScrubbing ? scrubFraction : (hoverFraction ?? keyFraction),
           model.duration > 0 {
            let hasSheet = model.trickplay != nil && model.trickplayWidth != nil
            // Without a sheet the card is just the timecode, and a timecode is
            // narrow — clamping a 208pt box would park it well off the cursor.
            // Wider when chapters have names to show beside the time.
            let named = model.chapters.contains { ($0.name ?? "").count > 3 }
            let cardWidth = hasSheet ? Theme.PlayerMetric.trickplayWidth(playing: model.isPlaying)
                                     : (named ? 240 : Theme.PlayerMetric.timecodeCardWidth)
            TrickplayPreview(
                model: model,
                serverURL: serverURL,
                pipeline: pipeline,
                itemId: itemId,
                seconds: fraction * model.duration
            )
            // A fixed width even when there is no still, so the label centres on
            // the pointer instead of growing rightwards from it as the digits
            // change — which is what made the bare timecode look like it lagged
            // the cursor rather than tracking it.
            .frame(width: hasSheet ? nil : cardWidth)
            .offset(x: previewOffset(
                fraction: fraction, width: width, cardWidth: cardWidth
            ))
        }
    }

    /// Keeps the card inside the bar rather than hanging off either end.
    ///
    /// A leading-edge coordinate, and the overlay it feeds is anchored leading for
    /// that reason. Against the centred anchor it used to have, this same number
    /// pushed the card half the spare width to the right — visible on any film long
    /// enough for the preview to matter.
    func previewOffset(fraction: Double, width: CGFloat, cardWidth: CGFloat) -> CGFloat {
        let ideal = width * fraction - cardWidth / 2
        return max(0, min(max(0, width - cardWidth), ideal))
    }
}

/// The volume slider.
///
/// `Slider` brings its own tint and focus ring, both of which fight chrome drawn
/// over video. Its handle appears on hover rather than sitting there permanently,
/// so at rest the volume is a line reporting a level rather than a fourth control
/// competing with the transport.
struct PlayerSlider: View {
    @Binding var value: Double

    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.PlayerPalette.scrubTrack)
                    .frame(height: Theme.PlayerMetric.volumeTrackHeight)
                Capsule()
                    .fill(Theme.Palette.onPlayerChrome)
                    .frame(width: width * value, height: Theme.PlayerMetric.volumeTrackHeight)
                Circle()
                    .fill(Theme.PlayerPalette.handle)
                    .frame(
                        width: Theme.PlayerMetric.volumeHandle,
                        height: Theme.PlayerMetric.volumeHandle
                    )
                    .offset(x: width * value - Theme.PlayerMetric.volumeHandle / 2)
                    .opacity(isHovering ? 1 : 0)
            }
            .frame(height: Theme.PlayerMetric.secondaryButton)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(Theme.Motion.hover, value: isHovering)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value = max(0, min(1, $0.location.x / width)) }
            )
        }
        .frame(height: Theme.PlayerMetric.secondaryButton)
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}

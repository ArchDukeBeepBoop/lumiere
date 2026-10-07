import SwiftUI
import LumiereKit

/// The Skip Intro / Skip Credits / Next Episode offer.
///
/// Bottom-right, above the controls, and it does not auto-dismiss — a prompt that
/// vanishes on a timer is one you have to race. It disappears when the moment it
/// belongs to passes, which is the only thing that should retire it.
///
/// Deliberately not part of the auto-hiding chrome: the whole point is to be
/// available without moving the mouse first, so it stays visible while the controls
/// are hidden.
struct PlayerPrompt: View {
    let prompt: PlayerModel.Prompt
    /// Carries the prompt's own label with the target, so the undo notice can
    /// name what was actually skipped rather than guessing "intro".
    let onSkip: (Double, String) -> Void
    let onNextEpisode: () -> Void
    /// Whether the picture is moving; the countdown waits while it is not.
    var isPlaying = true

    @State private var isHovering = false
    /// Seconds left before the next episode starts by itself, when "Play the
    /// next episode automatically" is on. Counted from when the offer appears
    /// — the credits — rather than from the end of the file, which made a
    /// season binge sit through every ending in full.
    @State private var countdown: Int?
    @AppStorage(Preference.playsNextAutomatically.name) private var autoplays
        = Preference.playsNextAutomatically.defaultValue

    var body: some View {
        // No `Spacer` and no outer `HStack` any more. The pill used to push itself
        // right from inside, which fought the row that now places it — and the row
        // is what lets a skip offer and a next-episode offer sit side by side.
        Group {
            // Shaped like the detail page's Play pill rather than like a tooltip:
            // it is an offer to press, and it has to hold its own against a moving
            // picture. Hovering fills it the way the primary on the bar is filled,
            // so the two most pressable things in the player agree on what
            // "pressable" looks like.
            Button(action: act) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    Text(label)
                        .font(Theme.Font.playerSubtitle)
                        // One line, truncated. "Next: " plus an episode title is
                        // unbounded — anime titles reach ninety characters — and
                        // an uncapped pill grew past the window's edge, taking
                        // the button it contains with it.
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // The cap belongs to the *label*, which is the only part
                        // that can grow without bound. It used to sit outside the
                        // background, so the pill drew at its content's width while
                        // the button still reserved 460pt and left-aligned it: the
                        // visible pill floated up to 300pt clear of the edge it was
                        // supposed to be pinned to, by an amount that depended on
                        // the length of the episode title.
                        .frame(maxWidth: Theme.PlayerMetric.promptMaxWidth,
                               alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(
                    isHovering
                        ? Theme.PlayerPalette.primaryGlyph
                        : Theme.Palette.onPlayerChrome
                )
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.md)
                .background {
                    let shape = RoundedRectangle(
                        cornerRadius: Theme.Radius.playControl, style: .continuous
                    )
                    ZStack {
                        GlassFill(shape: shape)
                        shape.fill(
                            isHovering
                                ? Theme.PlayerPalette.primaryFill
                                : Theme.PlayerPalette.surfaceBottom
                        )
                    }
                    .overlay {
                        shape.strokeBorder(Theme.PlayerPalette.surfaceStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: Theme.PlayerPalette.surfaceShadow,
                        radius: Theme.PlayerMetric.surfaceShadow,
                        y: Theme.PlayerMetric.surfaceShadowY
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(Theme.Motion.hover, value: isHovering)
        }
        // The edge inset belongs to the caller — see `PlayerMetric.promptInset`.
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .task(id: isPlaying) { await countDown() }
    }

    /// Ten seconds, paused while the picture is, then the next episode.
    private func countDown() async {
        guard autoplays, SleepTimer.mode != .afterEpisode, case .nextEpisode = prompt,
              !StillWatching.isAsking
        else { countdown = nil; return }
        if countdown == nil { countdown = 10 }
        while isPlaying, let left = countdown, left > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isPlaying else { return }
            countdown = left - 1
        }
        if countdown == 0 {
            countdown = nil
            if StillWatching.mayAdvance() { onNextEpisode() }
        }
    }

    private var label: String {
        switch prompt {
        case .skip(let label, _): return label
        case .nextEpisode(let title):
            if autoplays, StillWatching.isAsking { return "Still watching? Next: \(title)" }
            return countdown.map { "Next: \(title) · \($0)" } ?? "Next: \(title)"
        case .resumed(let from):
            return "Resuming from \(PlayerModel.timecode(from)) — Start Over"
        }
    }

    private var icon: String {
        switch prompt {
        case .skip: return "forward.end.fill"
        case .nextEpisode: return "play.fill"
        case .resumed: return "arrow.counterclockwise"
        }
    }

    private func act() {
        switch prompt {
        case .skip(let label, let target): onSkip(target, label)
        case .nextEpisode:
            StillWatching.someoneIsHere()
            onNextEpisode()
        // Reuses the skip channel: "start over" is a seek to zero, and giving it
        // a callback of its own would be a second path to the same call.
        case .resumed: onSkip(0, "Skip Intro")
        }
    }
}

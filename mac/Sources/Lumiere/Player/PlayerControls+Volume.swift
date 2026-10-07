import SwiftUI
import LumiereKit

/// The volume group at the left of the transport bar.
///
/// Split from PlayerControls.swift for the project's 300-line rule. `private`
/// widened to file scope for the usual reason: the row that places these lives
/// next door.
extension PlayerControls {

    func volumeControl(showsSlider: Bool) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                Task { await model.toggleMute() }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: Theme.PlayerMetric.secondaryGlyph, weight: .medium))
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .frame(width: 22, height: Theme.PlayerMetric.secondaryButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelledHelp(model.isMuted ? "Unmute" : "Mute")

            if showsSlider {
                PlayerSlider(
                    value: Binding(
                        get: { model.isMuted ? 0 : model.volume },
                        set: { newValue in Task { await model.setVolume(newValue) } }
                    )
                )
                .frame(width: Theme.PlayerMetric.volumeWidth)

                boostBadge
            }
        }
        .labelledHelp(volumeHelp)
    }

    /// Says when the audio is being amplified past unity.
    ///
    /// Boost is the only setting in this player that changes what you hear
    /// without changing anything you can see. Set once for a quiet film and
    /// forgotten, it makes every later file loud and clipped, and the cause is
    /// three levels down a settings panel. A badge beside the slider is the
    /// whole fix: it appears only when boost is on, and it names the number.
    @ViewBuilder
    var boostBadge: some View {
        if model.volumeBoost > 100.5 {
            Text("+\(Int(model.volumeBoost - 100))%")
                .font(Theme.Font.badge)
                .monospacedDigit()
                .foregroundStyle(Theme.PlayerPalette.primaryGlyph)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, 1)
                .background(
                    Theme.PlayerPalette.primaryFill,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                )
                .transition(.opacity)
                .animation(Theme.Motion.hover, value: model.volumeBoost)
        }
    }

    /// The level as a number, which the slider itself cannot say.
    ///
    /// On the control rather than in it: a readout drawn beside the slider moves
    /// the transport every time the volume changes, and a row that reflows under
    /// the pointer is worse than one you have to hover to read.
    var volumeHelp: String {
        if model.isMuted { return "Muted" }
        let level = "Volume \(Int((model.volume * 100).rounded()))%"
        guard model.volumeBoost > 100.5 else { return level }
        return level + " · boosted to \(Int(model.volumeBoost))%"
    }

    var volumeIcon: String {
        if model.isMuted || model.volume <= 0.001 { return "speaker.slash.fill" }
        if model.volume < 0.34 { return "speaker.fill" }
        if model.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

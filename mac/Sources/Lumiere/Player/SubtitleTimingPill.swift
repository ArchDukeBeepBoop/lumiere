import SwiftUI
import LumiereKit

/// Subtitle timing from the control bar, one click away: a tenth earlier or
/// later, and sync by ear. The sidebar has the same controls with a slider;
/// this is for the moment a line is visibly late and the film is still going.
struct SubtitleTimingPill: View {
    let model: PlayerModel

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            step("minus", "Subtitles earlier") { await model.nudgeSubtitleDelay(-1) }
            Text(SidebarFormat.seconds(model.subtitleDelay))
                .font(Theme.Font.playerRow.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            step("plus", "Subtitles later") { await model.nudgeSubtitleDelay(1) }
            Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(width: 1, height: 18)
            Button { Task { await model.syncSubtitleLine(1) } } label: {
                Label("Next Line Now", systemImage: "forward.end")
                    .font(Theme.Font.playerRow.weight(.medium))
            }
            .buttonStyle(PlayerCapsuleButtonStyle(prominent: true))
            .labelledHelp("As you hear a line spoken, press to bring its subtitle forward (⌥⌘')")
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .playerSurface(cornerRadius: Theme.Radius.playerGlass)
        .environment(\.colorScheme, .dark)
        .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
    }

    private func step(_ icon: String, _ help: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: icon)
                .font(Theme.Glyph.sm(.bold))
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.PlayerPalette.segmentTrack))
        }
        .buttonStyle(.plain)
        .labelledHelp(help)
    }
}

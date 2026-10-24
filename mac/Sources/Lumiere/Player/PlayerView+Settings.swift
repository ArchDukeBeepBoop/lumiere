import SwiftUI
import LumiereKit

/// Where the settings sidebar is drawn.
///
/// Split from PlayerView.swift for the project's 300-line rule.
extension PlayerView {

    /// Settings, in the player's own view tree rather than as a sheet.
    ///
    /// A sheet covered the film in order to change how the film looks, which is the
    /// wrong way round for every control in it: subtitle delay, aspect, upscaling
    /// and the picture sliders are all judged against the picture. A sidebar down
    /// the right edge leaves the frame visible beside it — VLC's redesign made the
    /// same move — and each change lands while you watch it.
    ///
    /// Not a `.popover` either, for the reason `PlayerTrackPanel` documents: an
    /// AppKit popover takes first responder, and the whole keyboard grammar hangs
    /// off it — see `KeyCaptureView`.
    @ViewBuilder
    func settingsOverlay(_ model: PlayerModel) -> some View {
        if showsSettings {
            HStack {
                Spacer()
                PlayerSidebar(model: model, isPresented: $showsSettings, playerSize: playerSize)
            }
            .padding(.trailing, Theme.Space.lg)
            .padding(.top, Theme.PlayerMetric.panelTopMargin)
            // Clear of the control bar, so the scrubber stays usable with the
            // sidebar open — the same lift the tracks and Up Next panels take.
            .padding(.bottom, Theme.PlayerMetric.promptLift)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

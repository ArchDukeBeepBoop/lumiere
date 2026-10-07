import SwiftUI
import LumiereKit

/// Where the settings panel is drawn.
///
/// Split from PlayerView.swift for the project's 300-line rule.
extension PlayerView {

    /// Settings, in the player's own view tree rather than as a sheet.
    ///
    /// A sheet covered the film in order to change how the film looks, which is the
    /// wrong way round for every control in it: subtitle delay, aspect, upscaling
    /// and vertical shift are all judged against the picture, and you cannot judge
    /// them against a picture behind a modal. Here the frame stays visible and each
    /// change lands under the panel while you watch it.
    ///
    /// Not a `.popover` either, for the reason `PlayerTrackPanel` documents: an
    /// AppKit popover takes first responder, and the whole keyboard grammar hangs
    /// off it — see `KeyCaptureView`.
    @ViewBuilder
    func settingsOverlay(_ model: PlayerModel) -> some View {
        if showsSettings {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PlayerSettingsPanel(
                        model: model, isPresented: $showsSettings,
                        playerSize: playerSize
                    )
                }
            }
            .padding(.trailing, Theme.Space.xl)
            // The same lift the tracks and Up Next panels take, so the three
            // boxes sit at one height instead of three.
            //
            // This used to be `barInset + xxxl`, which is 76 against the bar's
            // own 136: the panel's bottom edge landed on the scrubber, so the
            // control you drag to find a moment was underneath the box you
            // opened to change how that moment looks.
            .padding(.bottom, Theme.PlayerMetric.promptLift)
            .transition(.opacity)
        }
    }
}

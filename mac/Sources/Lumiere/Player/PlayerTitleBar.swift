import SwiftUI
import LumiereKit

/// What is playing, while the chrome is up.
///
/// Left-aligned at `Theme.Space.shelfInset`, which is the column every home shelf
/// and every detail page starts at — walking from a poster into the thing it plays
/// should not move the title. It replaces a centred 12pt line: centred, it landed
/// in the middle of the picture, which is where the subject of a shot usually is,
/// and at 12pt it read as a tooltip rather than as the identity of the film.
///
/// Two lines at most, and the second one only where there is something to say:
/// for an episode the season and number and the episode's own name, for a film
/// its year. Quiet — the picture is the content.
struct PlayerTitleBar: View {
    let model: PlayerModel
    let pipeline: ImagePipeline
    let serverURL: URL
    let onClose: () -> Void
    @Environment(\.displayScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            titleBlock
                .padding(.top, Theme.PlayerMetric.titleTopInset)

            Spacer(minLength: Theme.Space.xl)

            HStack(alignment: .center, spacing: Theme.Space.md) {
                // No route badge. "Direct Play" was on screen for every film, and it
                // is the answer to a question almost nobody is asking while they
                // watch — a permanent label reporting that the ordinary thing is
                // happening. It stays in the statistics HUD, where the Route row
                // sits beside the decode path and the reason, which is where you go
                // when you actually want to know.
                PlayerCloseButton(action: onClose)
                    // Escape reaches `onClose` through the key capture view as
                    // well. Kept here too because it is what makes the button
                    // announce its own shortcut, and calling `onClose` twice is
                    // idempotent.
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.top, Theme.Space.xl)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            // The logo where there is one, as on the hero and the detail page:
            // the same mark names the film from the shelf to the screen.
            if let logo = model.logo {
                RemoteImage(
                    request: ImageRequest(
                        serverURL: serverURL, itemId: logo.itemId, kind: .logo, tag: logo.tag,
                        displayWidth: Theme.PlayerMetric.titleLogoWidth,
                        aspectRatio: 2.5, screenScale: scale
                    ),
                    pipeline: pipeline, contentMode: .fit
                )
                .frame(
                    maxWidth: Theme.PlayerMetric.titleLogoWidth,
                    maxHeight: Theme.PlayerMetric.titleLogoHeight,
                    alignment: .leading
                )
                .accessibilityLabel(model.title)
            } else {
                Text(model.title)
                    .font(Theme.Font.playerTitle)
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                    .lineLimit(1)
            }

            if let subtitle = model.subtitleLine {
                Text(subtitle)
                    .font(Theme.Font.playerSubtitle)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

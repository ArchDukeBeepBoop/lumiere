import SwiftUI
import LumiereKit

/// The keys, once.
///
/// The player is the most finished part of this app — frame stepping, loop, an
/// intro skip that teaches itself, a remembered volume — and none of it is
/// visible. The chrome shows a transport and a gear, so a viewer would never
/// learn that `,` steps a frame while paused.
///
/// A card over the first film rather than an entry in a Help menu: nobody opens
/// Help to find out what a player can do, and a menu item is the same
/// invisibility with an extra click. It appears once, is dismissed for ever, and
/// never returns — a tutorial you have to close twice is worse than one you
/// never saw.
struct PlayerKeyCard: View {

    /// Written the moment it is shown, not when it is dismissed. A card that
    /// reappears because the app was quit while it was open is a card that has
    /// failed at the one thing it does.
    static let storageKey = "playerKeysSeen"

    let onDismiss: () -> Void

    /// Six, not sixteen. This is the set somebody would otherwise never find;
    /// the rest are discoverable from the transport or the menus.
    private let keys: [(String, String)] = [
        ("Space", "Play or pause"),
        ("← →", "Back or forward — hold to scan"),
        (", .", "One frame at a time, while paused"),
        ("↑ ↓", "Volume"),
        ("F", "Full screen"),
        ("Esc", "Close the player"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("A few keys")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.onArtworkText)
                Text("Shown once. Everything else is in the Playback menu.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.onArtworkTextMuted)
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(keys, id: \.0) { key, meaning in
                    HStack(spacing: Theme.Space.md) {
                        Text(key)
                            .font(Theme.Font.timecode)
                            .foregroundStyle(Theme.Palette.onArtworkText)
                            .frame(width: 58, alignment: .leading)
                        Text(meaning)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                    }
                }
            }

            Button("Got it", action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.xxl)
        .frame(width: 360, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            ZStack {
                GlassFill(shape: shape)
                shape.fill(Theme.PlayerPalette.surfaceBottom)
            }
            .overlay { shape.strokeBorder(Theme.PlayerPalette.surfaceStroke, lineWidth: 1) }
            .shadow(color: Theme.PlayerPalette.surfaceShadow, radius: 24, y: 8)
        }
        .transition(.opacity)
    }
}

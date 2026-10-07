import SwiftUI
import LumiereKit

/// What the player draws when it is not playing: preparing, engine missing, failed.
///
/// Split out of PlayerView.swift to stay under the project's 300-line rule.
extension PlayerView {

    // MARK: - States

    // Widened by the split: Swift's `private` is file-scoped, so moving these out
    // of PlayerView.swift to stay under the line limit opens them by one level.
    var preparing: some View {
        VStack(spacing: Theme.Space.lg) {
            ProgressView().controlSize(.large)
            Text("Preparing…")
                .font(Theme.Font.playerSubtitle)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
        }
        .padding(.horizontal, Theme.Space.xxxl)
        .padding(.vertical, Theme.Space.xxl)
        // The same plate the transport sits on. A bare spinner on black is the
        // one screen that looked like nothing had loaded at all rather than like
        // the app was working.
        .playerSurface(cornerRadius: Theme.Radius.playerPanel)
    }

    func engineMissing(_ decision: PlaybackDecision) -> some View {
        messagePanel(
            icon: "wrench.and.screwdriver",
            tint: Theme.Palette.onPlayerChromeSecondary,
            title: "The mpv engine didn't load",
            message: decision.reason.explanation,
            detail: "Without it, files like this one have to be transcoded by the "
                  + "server. Check that libmpv is installed."
        )
    }

    func failure(_ message: String) -> some View {
        messagePanel(
            icon: "exclamationmark.triangle",
            tint: Theme.Palette.danger,
            title: "Couldn't play this",
            message: message,
            detail: nil
        )
    }

    func messagePanel(
        icon: String, tint: Color, title: String, message: String, detail: String?
    ) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.Font.playerTitle)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Font.playerRow)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(Theme.Font.playerRow)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .multilineTextAlignment(.center)
            }
            // A pill rather than a text link. This is the only action on the
            // screen, and on the one screen a stuck load leaves you with, the way
            // out should look like a button.
            Button(action: onClose) {
                Text("Close")
                    .font(Theme.Font.playLabel)
                    .foregroundStyle(Theme.PlayerPalette.primaryGlyph)
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.md)
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.playControl, style: .continuous
                        )
                        .fill(Theme.PlayerPalette.primaryFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.md)
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, Theme.Space.xxxl)
        .padding(.vertical, Theme.Space.xxl)
        .playerSurface(cornerRadius: Theme.Radius.playerPanel)
    }
}

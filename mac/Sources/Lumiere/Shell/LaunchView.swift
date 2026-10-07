import SwiftUI
import AppKit
import LumiereKit

/// What the window shows while the app is getting ready.
///
/// A bare spinner on an empty canvas was doing this job, and it says nothing: on a
/// cold launch the database opens, migrations run, the image pipeline warms and the
/// library list is read, which on a 44,000-item cache is several seconds of a blank
/// window that reads as a hang rather than as work.
///
/// So it says the app's name, shows its icon, and names the step it is on. The step
/// is the part that matters — "Opening your library" and "Reaching your server" fail
/// for completely different reasons, and knowing which one you were on is most of
/// the diagnosis when it does.
struct LaunchView: View {
    /// What is happening right now, in the user's terms rather than the code's.
    let status: String
    /// Shown under the status when something has gone wrong but the app is still
    /// trying — an unreachable server on launch, most often.
    var detail: String?

    @State private var breathing = false

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                // A slow pulse rather than a spinner beside the icon. Two things
                // moving at different rates reads as busier than the work actually
                // is; one thing breathing reads as alive.
                .opacity(breathing ? 1 : 0.72)
                .scaleEffect(breathing ? 1 : 0.97)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: breathing
                )

            VStack(spacing: Theme.Space.xs) {
                Text("Lumiere")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(status)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .transition(.opacity)
                    .id(status)

                if let detail {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                        .padding(.top, Theme.Space.xs)
                }
            }

            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
        .animation(Theme.Motion.transition, value: status)
        .onAppear { breathing = true }
    }
}

import SwiftUI

/// A one-line "that didn't work", shown under the connection banner.
///
/// Deliberately not an alert. These report actions that failed on the server —
/// a collection that was not created, a thumbnail that could not be generated —
/// and an alert for each would be a modal interruption for something the user can
/// often simply retry. It takes real layout space rather than floating, so nothing
/// is drawn over.
struct TransientBanner: View {
    let message: String
    /// Present for a change that can be taken back; the banner is then a
    /// confirmation rather than a warning.
    var onUndo: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: onUndo == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(onUndo == nil ? Theme.Palette.danger : Theme.Palette.accent)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onUndo {
                Button(AppModel.bannerActionTitle, action: onUndo)
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.Palette.surfaceRaised)
    }
}

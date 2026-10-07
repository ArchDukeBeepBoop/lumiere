import SwiftUI

/// What a detail page shows when it has nothing to show.
///
/// Split out rather than inlined so the retry has somewhere to live. The state it
/// replaces was a `ProgressView` with no timeout and no message — a page that had
/// already given up looked exactly like one still working.
struct DetailUnavailable: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textMuted)
            Text("This title didn't open.")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message ?? "The server didn't return anything for it, and it isn't "
               + "in the local cache either.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

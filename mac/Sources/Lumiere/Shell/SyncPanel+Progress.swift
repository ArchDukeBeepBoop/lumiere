import SwiftUI
import LumiereKit

/// The running readout: which library, how far through it, and how far through the
/// selection as a whole.
///
/// A separate view rather than a computed property on `SyncPanel` so that the panel
/// file stays inside the project's 300-line limit, and because this is the one part
/// that redraws on every page of every library.
struct SyncActiveCard: View {
    let app: AppModel
    let progress: AppModel.SyncProgress

    var body: some View {
        SettingsCard(
            title: progress.isFullScan ? "Full Scan" : "Quick Scan",
            icon: "arrow.triangle.2.circlepath",
            subtitle: "Library \(progress.libraryIndex) of \(progress.libraryCount)"
        ) {
            Text(progress.libraryName)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            ProgressView(value: progress.fraction)
                .tint(Theme.Palette.accent)

            HStack {
                // Counts, not just a bar: a bar at 40% of an unknown total says
                // nothing, and the total is exactly what someone wants to know
                // before deciding whether to wait.
                Text(progress.total > 0
                     ? "\(progress.synced.formatted()) of \(progress.total.formatted()) items"
                     : "Counting…")
                Spacer()
                Text("\(Int(progress.fraction * 100))%")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)

            SettingsNote(progress.isFullScan
                ? "Reading every item in each ticked library. Anything the server no "
                + "longer has is removed at the end of each library — this is the pass "
                + "that clears out titles whose files were deleted or renamed. Stopping "
                + "is safe: a library that is not read in full is never swept."
                : "Reading newest-first and stopping as soon as a whole page is already "
                + "known, so a routine check costs a request or two rather than a walk "
                + "of the whole library. This pass cannot remove anything.")
        }
    }
}

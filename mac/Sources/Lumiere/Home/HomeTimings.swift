import SwiftUI
import LumiereKit

/// How long the home screen took to rebuild, the last few times, and why.
///
/// Logged to the diagnostics file as before, and kept in memory too, so the
/// question "which rebuild is slow on my library" has an answer in Settings
/// rather than in a log nobody opens.
@MainActor
enum HomeTimings {
    struct Entry: Identifiable {
        let id = UUID()
        let reason: String
        let seconds: Double
        let at: Date
        let summary: String
    }

    private(set) static var recent: [Entry] = []

    static func record(reason: String, seconds: Double, rows: [Int]) {
        let summary = "\(rows[0]) resume, \(rows[1]) recent, \(rows[2]) next up, \(rows[3]) shelves"
        Diagnostics.log("[home] \(reason) — \(summary) in \(String(format: "%.2f", seconds))s")
        recent.insert(Entry(reason: reason, seconds: seconds, at: Date(), summary: summary), at: 0)
        if recent.count > 10 { recent.removeLast() }
        LibraryHealthWatch.shared.homeIsSlow = slowness != nil
    }

    /// The tripwire: the median of the recent rebuilds over two seconds, and
    /// what was slowest — or nil while the home screen keeps up. Five
    /// rebuilds at least, so one slow launch is not called a trend.
    static var slowness: String? {
        guard recent.count >= 5 else { return nil }
        let sorted = recent.map(\.seconds).sorted()
        let median = sorted[sorted.count / 2]
        guard median > 2, let worst = recent.max(by: { $0.seconds < $1.seconds }) else { return nil }
        return String(format: "Rebuilds take %.1f s at the median; the slowest was “%@” at %.1f s.",
                      median, worst.reason, worst.seconds)
    }
}

/// The Settings rows that show them.
struct HomeTimingsRows: View {
    @State private var entries: [HomeTimings.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let slow = HomeTimings.slowness {
                Text(slow)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if entries.isEmpty {
                Text("No rebuilds yet this session.").font(Theme.Font.caption)
            }
            ForEach(entries) { entry in
                LabeledContent {
                    Text(String(format: "%.2f s", entry.seconds)).monospacedDigit()
                        .foregroundStyle(entry.seconds > 2 ? Theme.Palette.danger : Theme.Palette.textSecondary)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.reason)
                        Text("\(entry.at.formatted(date: .omitted, time: .standard)) · \(entry.summary)")
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }
                .font(Theme.Font.caption)
            }
            Button("Refresh List") { entries = HomeTimings.recent }
                .font(Theme.Font.caption)
        }
        .onAppear { entries = HomeTimings.recent }
    }
}

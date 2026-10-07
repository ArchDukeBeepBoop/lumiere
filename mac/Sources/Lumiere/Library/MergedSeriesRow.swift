import SwiftUI
import LumiereKit

/// One series in the merged-series list: a tick, a summary, and the episodes
/// underneath when you ask for them.
///
/// The summary carries the two facts that decide it — how many episodes change and
/// which seasons come out. "1–16" against a show you know has two seasons is the
/// signal to expand and look before ticking, and it should not need expanding to
/// see.
struct MergedSeriesRow: View {
    let series: MergedSeries
    let isSelected: Bool
    let isDone: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Button(action: onToggle) {
                    Image(systemName: tickIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isDone || isSelected ? Theme.Palette.accent : Theme.Palette.textMuted
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDone)

                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(summary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer(minLength: 0)

                Button(action: onExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(series.changes) { change in
                        Text("S\(pad(change.proposal.season))E\(pad(change.proposal.episode))"
                           + "  \(change.proposal.title)   ·   was "
                           + "\(current(change))  \(change.currentName)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ForEach(series.skipped) { skip in
                        Label(skip.reason, systemImage: "exclamationmark.triangle")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, Theme.Space.xl)
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private var tickIcon: String {
        if isDone { return "checkmark.circle.fill" }
        return isSelected ? "checkmark.square.fill" : "square"
    }

    private var summary: String {
        let seasons = series.seasons
        let range = seasons.count > 1
            ? "seasons \(seasons.first ?? 1)–\(seasons.last ?? 1)"
            : "season \(seasons.first ?? 1)"
        let skipped = series.skipped.isEmpty
            ? "" : " · \(series.skipped.count) not touched"
        return isDone
            ? "Repaired · \(series.changes.count) episodes"
            : "\(series.changes.count) episodes → \(range)\(skipped)"
    }

    private func current(_ change: MergedSeriesChange) -> String {
        guard let season = change.currentSeason, let episode = change.currentEpisode else {
            return "unnumbered"
        }
        return "S\(pad(season))E\(pad(episode))"
    }

    private func pad(_ value: Int) -> String { String(format: "%02d", value) }
}

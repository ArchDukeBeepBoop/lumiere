import SwiftUI
import LumiereKit

/// About This Library: what it holds, how much of it is watched, what came
/// this month and what takes the most room. Read once, not tuned.
struct LibraryOverviewCard: View {
    @Bindable var app: AppModel
    @State private var overview: LibraryOverview?

    var body: some View {
        if let client = app.client {
            SettingsCard(title: "About This Library", icon: "chart.bar") {
                if let o = overview {
                    row("Films", "\(o.Films.formatted()) · \(percent(o.WatchedFilms, o.Films)) watched")
                    row("Shows", "\(o.Shows.formatted()) · \(o.Episodes.formatted()) episodes, \(percent(o.WatchedEpisodes, o.Episodes)) watched")
                    if o.Videos > 0 { row("Other videos", o.Videos.formatted()) }
                    if o.Tracks > 0 { row("Music", "\(o.Albums.formatted()) albums · \(o.Tracks.formatted()) tracks") }
                    row("On disk", ByteCountFormatter.string(fromByteCount: o.Bytes, countStyle: .file))
                    row("Added this month", o.AddedThisMonth.formatted())
                    if let largest = o.Largest, !largest.isEmpty {
                        Text("Largest").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                        ForEach(largest, id: \.Name) { file in
                            row(file.Name, ByteCountFormatter.string(fromByteCount: file.Bytes, countStyle: .file))
                        }
                    }
                } else {
                    SettingsNote("Counting…")
                }
            }
            .task { overview = await client.libraryOverview() }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary) }
            .lineLimit(1)
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "0%" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
}

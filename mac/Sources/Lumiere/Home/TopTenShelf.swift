import SwiftUI
import LumiereKit

/// A Top 10 row, shared by the Classic and Hero layouts: ranked as the TV
/// app draws it — larger posters, each beside its number — or, with that
/// turned off in Settings › Home › Top 10 Rows, a plain row of posters.
///
/// The subtitle names what the ranking is, because "Top 10" on its own
/// invites the question. See `HomeModel+Top10`.
struct TopTenShelf: View {
    let title: String
    let entries: [LibraryEntry]
    let serverURL: URL
    let pipeline: ImagePipeline
    let onRefresh: () -> Void
    let metadata: (LibraryEntry) -> MetadataActions?
    @AppStorage(Preference.ranksTopTen.name) private var ranked = Preference.ranksTopTen.defaultValue

    var body: some View {
        let posterWidth = ranked ? Theme.Art.rankedPosterWidth : Theme.Art.shelfPosterWidth
        Shelf(
            title: title,
            subtitle: "By community rating",
            action: onRefresh,
            actionTitle: "Refresh",
            actionIcon: "arrow.triangle.2.circlepath",
            itemCount: entries.count,
            itemWidth: ranked ? RankedCard<EmptyView>.width(card: posterWidth) : posterWidth
        ) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    if ranked {
                        RankedCard(rank: index + 1) { poster(entry, width: posterWidth) }
                    } else {
                        poster(entry, width: posterWidth)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func poster(_ entry: LibraryEntry, width: CGFloat) -> some View {
        PosterCard(entry: entry, serverURL: serverURL, pipeline: pipeline, width: width,
                   metadata: metadata(entry))
    }
}

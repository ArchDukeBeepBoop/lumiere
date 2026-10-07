import SwiftUI
import LumiereKit

/// The Top 10 rows on the classic home screen.
///
/// Split from ClassicHomeView.swift for the project's 300-line limit. Which
/// libraries each row draws from is `TopShelfSelection`'s answer, not this view's.
extension ClassicHomeView {

    /// A Top 10 row, with the control that changes it.
    ///
    /// The subtitle names what the ranking is, because "Top 10" on its own invites
    /// the question and the answer is not obvious — see `HomeModel+Top10` for what
    /// this ranking can and cannot do.
    ///
    /// Not private: called from `body` in ClassicHomeView.swift, and Swift's
    /// `private` is file-scoped.
    @ViewBuilder
    func topShelf(
        _ title: String, kind: LibraryKinds.Kind, entries: [LibraryEntry]
    ) -> some View {
        if !entries.isEmpty {
            Shelf(
                title: title,
                subtitle: "By community rating",
                // This row's kind, so a press moves this row and no other.
                action: { Task { await model.refreshTop(kind) } },
                actionTitle: "Refresh",
                actionIcon: "arrow.triangle.2.circlepath",
                itemCount: entries.count,
                itemWidth: Theme.Art.shelfPosterWidth
            ) {
                ForEach(entries) { entry in
                    NavigationLink(value: DetailRoute.forEntry(entry)) {
                        PosterCard(
                            entry: entry, serverURL: serverURL,
                            pipeline: pipeline, width: Theme.Art.shelfPosterWidth,
                            metadata: shelfActions(for: entry)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

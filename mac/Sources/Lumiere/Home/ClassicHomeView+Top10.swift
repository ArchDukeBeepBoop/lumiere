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
            TopTenShelf(
                title: title, entries: entries, serverURL: serverURL, pipeline: pipeline,
                // This row's kind, so a press moves this row and no other.
                onRefresh: { Task { await model.refreshTop(kind) } },
                metadata: { shelfActions(for: $0) }
            )
        }
    }
}

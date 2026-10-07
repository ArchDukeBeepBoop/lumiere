import SwiftUI
import LumiereKit

/// The right-click menu a search result carries.
///
/// The same menu a library grid carries, because it is the same object and
/// search is the likeliest place to *find* a mis-scraped title. It used to be a
/// separate forty-line copy that happened to agree; now it cannot disagree.
extension SearchView {

    var entryContext: EntryActionContext {
        EntryActionContext(
            app: app,
            repository: repository,
            // A search has no rows to refresh individually — the result set is
            // the query — so re-running it is the honest equivalent.
            refreshRow: { _ in search() }
        )
    }

    func actions(for entry: LibraryEntry) -> MetadataActions? {
        entryState.actions(
            for: entry,
            in: entryContext,
            extras: EntryActionExtras(deleteCollection: { deleteCollectionTarget = $0 })
        )
    }
}

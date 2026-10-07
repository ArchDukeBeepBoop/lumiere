import SwiftUI
import LumiereKit

/// What right-clicking a tile in a library grid offers.
///
/// Nothing, now, that the grid decides for itself. This file used to build the
/// whole menu — seventy lines of it — and six other surfaces built their own
/// copies beside it, which is how the home shelves ended up without offline
/// guards and the music browser ended up firing its destructive command straight
/// off the click.
///
/// What is left is the two things that are genuinely the grid's: a selection,
/// and a collection it is allowed to delete. See `EntryActionExtras`.
extension LibraryGridView {

    var entryContext: EntryActionContext {
        EntryActionContext(
            app: app,
            repository: repository,
            // The row, not the grid. A reload refetches from offset zero and
            // takes the scroll position with it, which on a wall of 24,000 is
            // the difference between seeing your change and losing your place.
            refreshRow: { await refreshRow(id: $0) }
        )
    }

    func metadataActions(for entry: LibraryEntry) -> MetadataActions? {
        entryState.actions(
            for: entry,
            in: entryContext,
            extras: EntryActionExtras(
                // The one command here that needs nothing but the rows already
                // on screen.
                beginSelection: { selection.begin(with: $0) },
                deleteCollection: { deleteCollectionTarget = $0 }
            )
        )
    }
}

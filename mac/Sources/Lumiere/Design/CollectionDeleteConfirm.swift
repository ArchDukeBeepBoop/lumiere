import SwiftUI
import LumiereKit

/// The "delete this collection?" dialog, wherever a collection can be right-clicked.
///
/// One modifier rather than a copy per surface. The library grid had this and the
/// home shelves did not, so right-clicking a collection on the homepage offered
/// "Add to Collection" — on a collection — and no way to remove it. Commands that
/// exist in one place and not an equivalent one are the recurring shape of this
/// app's bugs, and the fix is to make adding the command to a new surface one line.
struct CollectionDeleteConfirm: ViewModifier {
    @Binding var target: LibraryEntry?
    /// Optional because the home views hold one: without it the dialog simply
    /// cannot act, which is the same reason the menu item would not be offered.
    let repository: LibraryRepository?
    var app: AppModel?
    /// Called after a deletion the server actually honoured.
    let onDeleted: () async -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(target?.item.name ?? "this collection")?",
            isPresented: Binding(
                get: { target != nil },
                set: { if !$0 { target = nil } }
            ),
            titleVisibility: .visible
        ) {
            // First, because for the collections that keep coming back it is the
            // one that works. See the message below.
            Button("Hide in Lumiere") {
                guard let entry = target else { return }
                target = nil
                Task { await hide(entry) }
            }
            Button("Delete on Server", role: .destructive) {
                guard let entry = target else { return }
                target = nil
                Task { await delete(entry) }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: {
            // Says what survives, and says why there are two answers.
            //
            // Deleting was never broken: Jellyfin's TMDB scraper creates a BoxSet
            // for every film that belongs to a film collection and re-creates it on
            // the next library scan, so a deletion undoes itself minutes later.
            // Hiding is the client's own decision and nothing on the server reverses
            // it.
            Text("Every title in it stays in your library with its watch history — a "
               + "collection groups titles, it does not contain them.\n\n"
               + "Hide keeps it out of Lumiere and cannot be undone by the server. "
               + "Delete removes it from the server and hides it here as well, so that "
               + "if the TMDB scraper builds it again on the next scan — which it "
               + "will, under a new id — it still does not come back. Turning the "
               + "collection setting off on the server's Movies library stops it at "
               + "source.")
        }
    }

    private func hide(_ entry: LibraryEntry) async {
        guard let repository else { return }
        do {
            try await repository.hideCollection(id: entry.id, name: entry.item.name)
            await onDeleted()
        } catch {
            app?.report(ConnectionState.message(for: error))
        }
    }

    /// Deletes on the server *and* leaves the local tombstone.
    ///
    /// Both, always. Deleting alone was never enough: the scraper builds a fresh
    /// BoxSet with the same name and a new id on the next scan, so the only thing
    /// that makes a deletion look like a deletion is a record of the name. Hiding
    /// alongside costs nothing when the server never brings it back, and is the
    /// whole difference when it does.
    private func delete(_ entry: LibraryEntry) async {
        guard let repository else { return }
        do {
            try await repository.hideCollection(id: entry.id, name: entry.item.name)
            try await repository.deleteCollection(id: entry.id)
            await onDeleted()
        } catch {
            Diagnostics.log("[collection] delete failed for \(entry.id): \(error)")
            app?.report(ConnectionState.message(for: error))
        }
    }
}

extension View {
    func collectionDeleteConfirm(
        target: Binding<LibraryEntry?>,
        repository: LibraryRepository?,
        app: AppModel?,
        onDeleted: @escaping () async -> Void
    ) -> some View {
        modifier(CollectionDeleteConfirm(
            target: target, repository: repository, app: app, onDeleted: onDeleted
        ))
    }
}

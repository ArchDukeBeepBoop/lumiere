import SwiftUI
import LumiereKit

/// Selecting many titles and acting on all of them.
///
/// The tile is the whole target while selecting, rather than a checkbox in a
/// corner: hitting a five-point control to choose a two-hundred-point poster is a
/// worse gesture than the one it replaces.
extension LibraryGridView {

    @ViewBuilder
    func tile(_ entry: LibraryEntry) -> some View {
        if selection.isActive {
            // Deliberately not a NavigationLink while selecting. A grid that both
            // selects and navigates on the same click is one where every mis-aim
            // costs a screen change and loses the selection behind it.
            Button { selection.toggle(entry.id) } label: {
                PosterCard(
                    entry: entry, serverURL: serverURL, pipeline: pipeline,
                    width: CGFloat(tileWidth)
                )
                .overlay { SelectionOverlay(isSelected: selection.contains(entry.id)) }
            }
            .buttonStyle(.plain)
            .keyboardFocusRing(keyboard.focusedId == entry.id)
        } else {
            NavigationLink(value: DetailRoute.forEntry(entry)) {
                PosterCard(
                    entry: entry, serverURL: serverURL, pipeline: pipeline,
                    width: CGFloat(tileWidth),
                    metadata: metadataActions(for: entry)
                )
            }
            .buttonStyle(.plain)
            .keyboardFocusRing(keyboard.focusedId == entry.id)
        }
    }

    /// Stars everything selected.
    ///
    /// Sets rather than toggles, and that is the right call for a batch: a toggle
    /// over a mixed selection flips half of it on and half off, which is never what
    /// anyone means by "favourite these".
    func batchFavourite() async {
        guard let app else { return }
        await selection.run { await app.toggleFavourite(itemId: $0, isFavourite: false) }
        await reload()
    }

    /// Queues subtitles for every season of each selected show, in the
    /// search language — the whole-library version of a series page's
    /// Queue Subtitles…. Films in the selection are passed over.
    func batchQueueSubtitles() async {
        let shows = visibleEntries.filter { selection.ids.contains($0.id) && $0.item.itemType == .series }
        guard !shows.isEmpty else {
            app?.report("Queue Subtitles works on shows — select one or more.")
            return
        }
        let language = Preference.subtitleSearchLanguage.value.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? "en"
        var added = 0
        for show in shows {
            added += (try? await repository.queueSubtitles(
                seriesId: show.id, seasonId: "", language: language.isEmpty ? "en" : language)) ?? 0
        }
        app?.report("\(added) episode\(added == 1 ? "" : "s") across \(shows.count) "
                    + "show\(shows.count == 1 ? "" : "s") queued for subtitles.")
        selection.end()
    }

    func batchWatched(_ played: Bool) async {
        await selection.run { await repository.setPlayed(itemId: $0, played: played) }
        await reload()
    }
}

/// The sheets a batch opens.
///
/// An extension method rather than a modifier holding a copy of the view, so the
/// ids it clears are the grid's own state. Split out for the 300-line limit.
extension LibraryGridView {
    func withBatchSheets(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Delete \(deleteCollectionTarget?.item.name ?? "this collection")?",
                isPresented: Binding(
                    get: { deleteCollectionTarget != nil },
                    set: { if !$0 { deleteCollectionTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    if let target = deleteCollectionTarget {
                        Task { await deleteCollection(id: target.id) }
                    }
                    deleteCollectionTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteCollectionTarget = nil }
            } message: {
                // What survives, because "delete" beside a wall of posters reads as
                // though it deletes the films.
                Text("Removes the collection from your server. Every film and series "
                   + "in it stays in your library exactly where it is — a collection "
                   + "groups titles, it does not contain them. Nothing is deleted "
                   + "from disk.")
            }
            .sheet(isPresented: Binding(
                get: { !batchCollectionIds.isEmpty },
                set: { if !$0 { batchCollectionIds = [] } }
            )) {
                AddToCollectionSheet(
                    itemId: batchCollectionIds.first ?? "",
                    itemIds: batchCollectionIds,
                    itemName: "\(batchCollectionIds.count) titles",
                    repository: repository,
                    onDone: { batchCollectionIds = [] }
                )
            }
            .sheet(isPresented: Binding(
                get: { !batchPlaylistIds.isEmpty },
                set: { if !$0 { batchPlaylistIds = [] } }
            )) {
                AddToPlaylistSheet(
                    itemIds: batchPlaylistIds,
                    itemName: "\(batchPlaylistIds.count) titles",
                    repository: repository,
                    onDone: { batchPlaylistIds = [] }
                )
            }
    }
    func deleteCollection(id: String) async {
        do {
            try await repository.deleteCollection(id: id)
            await reload()
        } catch {
            // Said, not only logged. A delete that failed looked exactly like one
            // that worked until the collection reappeared at the next restart —
            // and the reason was in a log nobody sees, on stderr.
            Diagnostics.log("[collection] delete failed for \(id): \(error)")
            app?.report(ConnectionState.message(for: error))
        }
    }
}

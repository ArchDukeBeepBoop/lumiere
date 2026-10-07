import SwiftUI
import LumiereKit

/// The detail page's modals: the metadata editor, the collection item picker and
/// the shelf-relabel prompt.
///
/// An extension on DetailView rather than a standalone modifier, so these still
/// read and write the page's own `@State` — a modifier holding a copy of the view
/// could present a sheet but never write back to it. Split out purely to keep
/// DetailView.swift under the project's 300-line limit.
extension DetailView {
    func withModals(_ content: some View) -> some View {
        content
            .removalConfirmations(target: $removalTarget) { target in
                guard let app, let repository = app.repository else { return }
                if target.permanent {
                    do {
                        try await repository.deleteToTrash(itemId: target.entry.id)
                        app.reportTrashed("\(target.entry.item.name)")
                    } catch {
                        app.report(ConnectionState.message(for: error))
                    }
                } else if await repository.removeFromLibrary(itemId: target.entry.id) {
                    app.report("\(target.entry.item.name) removed. Restore it from Settings › Library.")
                }
                await model?.load()
            }
            .sheet(item: $identifySeason) { season in
                if let app, let client = app.client {
                    IdentifySheet(
                        itemId: season.id,
                        // The season's own name, which for a bundled title is
                        // the title; "Season 2" would find nothing worth
                        // finding.
                        initialQuery: season.item.name,
                        isSeries: true,
                        seasonNumber: season.item.indexNumber ?? 1,
                        client: client,
                        onDone: { changed in
                            identifySeason = nil
                            if changed, let model {
                                Task {
                                    await app.refreshMetadata(itemId: season.id, replaceEverything: false)
                                    await model.load()
                                }
                            }
                        }
                    )
                }
            }
            // Asked rather than done, because the consequence cannot be seen and
            // cannot be undone from the menu. The warning was written as a
            // `.help` on the context-menu row — macOS draws no tooltip there, so
            // the only statement in the app that freezing a thumbnail also stops
            // the synopsis updating was invisible.
            .confirmationDialog(
                "Freeze this episode's thumbnail?",
                isPresented: Binding(
                    get: { freezeThumbnailId != nil },
                    set: { if !$0 { freezeThumbnailId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Freeze Thumbnail") {
                    if let id = freezeThumbnailId, let model {
                        Task { await generateThumbnail(for: id, model: model) }
                    }
                    freezeThumbnailId = nil
                }
                Button("Cancel", role: .cancel) { freezeThumbnailId = nil }
            } message: {
                Text("Takes a frame a fifth of the way into the file and pins "
                   + "it. A later refresh cannot put the scraped still back — "
                   + "and it also stops this episode's synopsis updating.")
            }
            .alert(
                "That didn't apply",
                isPresented: Binding(
                    get: { model?.collectionError != nil },
                    set: { if !$0 { model?.collectionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model?.collectionError = nil }
            } message: {
                Text(model?.collectionError ?? "")
            }
            .confirmationDialog(
                "Delete \(model?.entry?.item.name ?? "this collection")?",
                isPresented: Binding(
                    get: { isConfirmingCollectionDelete },
                    set: { isConfirmingCollectionDelete = $0 }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    Task { await deleteThisCollection() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                // Says what survives. On a page that *is* a wall of the collection's
                // films, "delete" reads as though it deletes them.
                Text("Removes the collection from your server. All "
                   + "\(model?.collectionItems.count ?? 0) titles in it stay in your "
                   + "library exactly where they are, with their watch history "
                   + "intact — a collection groups titles, it does not contain them.")
            }
            .sheet(isPresented: Binding(
                get: { isFinishingCollection },
                set: { isFinishingCollection = $0 }
            )) {
                if let client = app?.client, let pipeline = app?.imagePipeline,
                   let serverURL = app?.serverURL {
                    CollectionAuthoringSheet(
                        collectionIds: [itemId],
                        repository: repository,
                        client: client,
                        pipeline: pipeline,
                        serverURL: serverURL,
                        onDone: {
                            isFinishingCollection = false
                            Task { await model?.load() }
                        }
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { collectionArtworkId != nil },
                set: { if !$0 { collectionArtworkId = nil } }
            )) {
                if let id = collectionArtworkId, let client = app?.client {
                    ArtworkPickerSheet(itemId: id, client: client) { changed in
                        collectionArtworkId = nil
                        if changed { Task { await model?.load() } }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { editingId != nil },
                set: { if !$0 { editingId = nil } }
            )) {
                if let id = editingId, let client = app?.client {
                    EditMetadataSheet(
                        itemId: id,
                        repository: repository,
                        client: client,
                        onDone: { changed in
                            editingId = nil
                            // No wait, unlike a scrape: an edit has already been
                            // applied by the time the request returns.
                            if changed { Task { await model?.load() } }
                        }
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { isRepairingEpisodes },
                set: { isRepairingEpisodes = $0 }
            )) {
                if let client = app?.client {
                    EpisodeRepairSheet(
                        seriesId: itemId,
                        seriesName: model?.entry?.item.name ?? "this series",
                        client: client,
                        repository: repository,
                        onDone: { changed in
                            isRepairingEpisodes = false
                            // Reloading matters more here than after an ordinary
                            // edit: the numbering the season picker groups by is
                            // exactly what just changed underneath it.
                            if changed { Task { await model?.load() } }
                        }
                    )
                }
            }
            .sheet(isPresented: $showingAddItems) {
                if let model {
                AddCollectionItemsSheet(
                    repository: repository,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    excludedIds: Set(model.collectionItems.map(\.id)),
                    onAdd: { ids in
                        await model.addItemsToCollection(ids)
                        app?.report("Added \(ids.count) to the collection.") {
                            for id in ids { await model.removeFromCollection(id) }
                        }
                    }
                )
                }
            }
            .confirmationDialog(
                "Remove \(removingFromCollection?.item.name ?? "this title") from the collection?",
                isPresented: Binding(
                    get: { removingFromCollection != nil },
                    set: { if !$0 { removingFromCollection = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let target = removingFromCollection else { return }
                    Task {
                        await model?.removeFromCollection(target.id)
                        app?.report("Removed \(target.item.name) from the collection.") {
                            await model?.addItemsToCollection([target.id])
                        }
                    }
                    removingFromCollection = nil
                }
                Button("Cancel", role: .cancel) { removingFromCollection = nil }
            } message: {
                Text("It stays in your library with its watch history — only its "
                   + "membership of this collection goes.")
            }
            .confirmationDialog(
                "Delete the downloaded copy?",
                isPresented: Binding(
                    get: { deletingDownloadId != nil },
                    set: { if !$0 { deletingDownloadId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = deletingDownloadId else { return }
                    Task { await app?.removeDownload(itemId: id) }
                    deletingDownloadId = nil
                }
                Button("Cancel", role: .cancel) { deletingDownloadId = nil }
            } message: {
                Text("Frees the space on this Mac. The title stays on your server "
                   + "and can be downloaded again.")
            }
            .alert(
                "Set Position",
                isPresented: Binding(
                    get: { positionEntry != nil },
                    set: { if !$0 { positionEntry = nil } }
                )
            ) {
                TextField("Position in this row", text: $positionText)
                Button("Move") {
                    guard let target = positionEntry,
                          let position = Int(positionText.trimmingCharacters(in: .whitespaces))
                    else { positionEntry = nil; return }
                    Task { await model?.moveInCollection(memberId: target.id, toPosition: position) }
                    positionEntry = nil
                    positionText = ""
                }
                Button("Cancel", role: .cancel) {
                    positionEntry = nil
                    positionText = ""
                }
            } message: {
                // Counted within the row, not the collection: a collection page is
                // several rows, and "third" means third among the ones you can see.
                Text("Where \(positionEntry?.item.name ?? "this title") should sit in "
                   + "its row, counting from 1.")
            }
            .alert(
                "Move to Shelf",
                isPresented: Binding(get: { relabelingEntry != nil }, set: { if !$0 { relabelingEntry = nil } })
            ) {
                TextField("Shelf name", text: $relabelText)
                Button("Move") {
                guard let target = relabelingEntry else { return }
                let label = relabelText.trimmingCharacters(in: .whitespaces)
                Task { await model?.setShelfLabel(itemId: target.id, label: label.isEmpty ? nil : label) }
                relabelingEntry = nil
                relabelText = ""
                }
                Button("Cancel", role: .cancel) {
                relabelingEntry = nil
                relabelText = ""
                }
            } message: {
                Text("Leave blank to return \(relabelingEntry?.item.name ?? "this title") to its automatic shelf.")
            }
    }
    /// Deletes the collection this page is showing, then leaves the page.
    ///
    /// Popping first is not cosmetic: staying on the detail page of something that
    /// no longer exists leaves a header with a name, a row of posters, and every
    /// action failing silently against a missing id.
    func deleteThisCollection() async {
        do {
            try await repository.deleteCollection(id: itemId)
            dismiss()
        } catch {
            // Stays on the page and says why. Dismissing regardless would have
            // shown the collection gone and left it on the server.
            Diagnostics.log("[collection] delete failed for \(itemId): \(error)")
            app?.report(ConnectionState.message(for: error))
        }
    }
}

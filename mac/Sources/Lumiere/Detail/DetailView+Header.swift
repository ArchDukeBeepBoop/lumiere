import SwiftUI
import LumiereKit

/// The top of a detail page. Split from DetailView.swift for the 300-line rule.
extension DetailView {

    /// The hero-led layout for a series; the poster-beside-text layout otherwise.
    /// Series fall back to the plain header until episodes have loaded, so the page
    /// is never blank while that happens.
    @ViewBuilder
    func header(model: DetailModel, entry: LibraryEntry) -> some View {
        if model.isCollection {
            CollectionHeader(
                model: model,
                entry: entry,
                pipeline: pipeline,
                serverURL: serverURL,
                onAddItems: { showingAddItems = true },
                onRefreshArtwork: app == nil ? nil : { await refreshCollectionArtwork(model: model, entry: entry) },
                onFinish: app?.client == nil ? nil : { isFinishingCollection = true },
                onDelete: app?.client == nil ? nil : { isConfirmingCollectionDelete = true },
                onIdentify: app?.client == nil ? nil : { identifyingCollection = true },
                onScan: app?.client == nil ? nil : { await scanCollection(model: model, entry: entry) }
            )
            .sheet(isPresented: $identifyingCollection) {
                if let app, let client = app.client {
                    CollectionSeriesSheet(
                        mode: .identify(collectionId: entry.id), client: client,
                        initialQuery: entry.item.name,
                        privateLibraryIds: app.privateLibraryIds, inRoom: app.isShowingPrivateLibraries
                    ) { changed in
                        identifyingCollection = false
                        if changed {
                            Task { await reread(entry.id, model: model) }
                        }
                    }
                }
            }
        } else if model.isSeries, let hero = model.heroEntry {
            DetailHeroHeader(
                hero: hero,
                artEntry: model.backdropSource(seriesEntry: entry) ?? entry,
                pipeline: pipeline,
                serverURL: serverURL,
                genres: model.detail?.genres ?? [],
                // So the page can lead with where you are in the season. See
                // `DominantFact`.
                seasonEpisodes: model.episodes,
                onPlay: { onPlay(hero.id) },
                onToggleWatched: { await model.toggleHeroWatched() },
                // The series, not the episode the strip happens to have selected.
                onToggleFavourite: { await model.toggleFavourite() },
                favouriteEntry: entry,
                download: heroDownloadAction(for: model, hero: hero),
                // The series, not the episode on display: a katakana title is the
                // show's, where this header's other actions act per-episode
                // precisely because those only make sense that way.
                onEditMetadata: app?.client == nil ? nil : { editingId = itemId }
            )
        } else if !model.isSeries {
            // A film is both roles at once: the thing being played and the source of
            // the art. Series still fall through to the older header while their
            // episodes load, so the page is never blank during that.
            DetailHeroHeader(
                hero: entry,
                artEntry: entry,
                pipeline: pipeline,
                serverURL: serverURL,
                genres: model.detail?.genres ?? [],
                onPlay: {
                    app?.nowPlayingSourceId = model.selectedSourceId
                    onPlay(playableItemId(for: model))
                },
                onToggleWatched: { await model.toggleWatched() },
                onToggleFavourite: { await model.toggleFavourite() },
                download: downloadAction(for: model),
                onEditMetadata: app?.client == nil ? nil : { editingId = itemId },
                versions: model.detail?.mediaSources ?? [],
                selectedVersion: Binding(
                    get: { model.selectedSourceId },
                    set: { model.selectedSourceId = $0 }
                )
            )
        } else {
            DetailHeader(
                model: model,
                entry: entry,
                pipeline: pipeline,
                serverURL: serverURL,
                capabilities: capabilities,
                onPlay: { onPlay(playableItemId(for: model)) },
                download: downloadAction(for: model)
            )
        }
    }

    /// A series is not playable itself: playing it should start the next
    /// unwatched episode, or the first one. Used only as the pre-episode-load
    /// fallback now that the hero header drives Play directly once ready.
    /// Widened by the download split — `private` is file-scoped.
    func playableItemId(for model: DetailModel) -> String {
        guard model.isSeries else { return itemId }
        if let next = model.episodes.first(where: { !$0.isPlayed }) {
            return next.id
        }
        return model.episodes.first?.id ?? itemId
    }

    private func refreshCollectionArtwork(model: DetailModel, entry: LibraryEntry) async {
        guard let app else { return }
        await app.refreshMetadata(itemId: entry.id, replaceEverything: true)
        await model.load()
    }

    /// Scan Collection: the server finds the series itself, then names,
    /// pictures and fills it.
    func scanCollection(model: DetailModel, entry: LibraryEntry) async {
        guard let app, let client = app.client else { return }
        do {
            if try await client.scanCollection(entry.id) {
                await reread(entry.id, model: model)
                app.report("Collection scanned: named, pictured and filled from its film series.")
            } else {
                app.report("No film series found for \(entry.item.name). Try Identify… to choose one.")
            }
        } catch {
            app.report("The scan did not complete: \(error.localizedDescription)")
        }
    }

    /// The collection as the server now has it. Not a metadata refresh, which
    /// would ask the server to scrape again and could undo the series' poster.
    func reread(_ id: String, model: DetailModel) async {
        guard let app else { return }
        try? await app.repository?.refreshItem(itemId: id)
        await model.load()
        await app.contentDidChange("after a collection was identified")
    }
}

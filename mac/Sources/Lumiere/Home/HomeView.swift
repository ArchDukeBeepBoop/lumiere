import SwiftUI
import LumiereKit

/// The home screen, in both layouts.
///
/// One model feeds both, so the setting switches instantly and never refetches.
struct HomeView: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    let layout: HomeLayout
    let libraries: [LibraryRecord]
    var app: AppModel?
    let serverName: String
    let onOpenLibrary: (LibraryRecord) -> Void
    /// "See All" on a Latest shelf: the fifty most recent, not the whole library.
    let onSeeAllLatest: (LibraryRecord) -> Void
    /// The whole unfinished list. The shelf shows a row of it.
    let onSeeAllResume: () -> Void
    /// See All on the Forgotten shelf. Optional with a no-op default so the
    /// previews and the compact layout, which does not draw that shelf, need
    /// not supply one.
    var onSeeAllForgotten: () -> Void = {}
    let onSeeAllNextUp: () -> Void

    // The compact layout had no right-click menu anywhere — neither the poster wall
    // nor the continue rows passed `metadata:`, so choosing Compact in Settings
    // silently removed favourite, edit, refresh, hide and add-to-collection from
    // the entire home screen. Hero had this same regression once and was fixed;
    // Compact was never brought along.
    /// The collection a deletion has been asked for, held while it is confirmed.
    @State private var deleteCollectionTarget: LibraryEntry?
    /// The shared menu's state. See `EntryActionState`.
    @State private var entryState = EntryActionState()

    @State private var model: HomeModel?

    private var entryContext: EntryActionContext {
        EntryActionContext(
            app: app,
            repository: repository,
            refreshRow: { _ in await model?.load(libraries: libraries, layout: layout) }
        )
    }

    /// The same menu the other two layouts offer.
    ///
    /// Compact is the layout that has historically been left behind when a
    /// command was added — which is an argument for it not having a copy of the
    /// menu at all. See `EntryActionExtras`.
    private func shelfActions(for entry: LibraryEntry) -> MetadataActions? {
        entryState.actions(
            for: entry,
            in: entryContext,
            extras: EntryActionExtras(
                hideFromShelves: { id in await app?.hideFromShelves(itemId: id) },
                deleteCollection: { deleteCollectionTarget = $0 }
            )
        )
    }

    var body: some View {
        Group {
            if let model {
                if model.isLoading && model.resume.isEmpty && model.recentlyAdded.isEmpty {
                    loadingOrEmpty
                } else {
                    switch layout {
                    case .classic:
                        ClassicHomeView(
                            model: model,
                            pipeline: pipeline,
                            serverURL: serverURL,
                            serverName: serverName,
                            libraries: libraries,
                            capabilities: capabilities,
                            app: app,
                            onOpenLibrary: onOpenLibrary,
                            onSeeAllLatest: onSeeAllLatest,
                            onSeeAllResume: onSeeAllResume,
                            onSeeAllForgotten: onSeeAllForgotten,
                            onSeeAllNextUp: onSeeAllNextUp,
                            repository: repository
                        )
                    case .hero:
                        HeroHomeView(
                            model: model,
                            pipeline: pipeline,
                            serverURL: serverURL,
                            capabilities: capabilities,
                            onOpenLibrary: onOpenLibrary,
                            onSeeAllLatest: onSeeAllLatest,
                            onSeeAllResume: onSeeAllResume,
                            onSeeAllForgotten: onSeeAllForgotten,
                            onSeeAllNextUp: onSeeAllNextUp,
                            shelfLibraries: libraries,
                            app: app,
                            repository: repository
                        )
                    case .compact:
                        CompactHomeView(
                            model: model,
                            pipeline: pipeline,
                            serverURL: serverURL,
                            actions: { shelfActions(for: $0) },
                            app: app,
                            onOpenLibrary: onOpenLibrary,
                            onSeeAllLatest: onSeeAllLatest,
                            onSeeAllResume: onSeeAllResume,
                            onSeeAllNextUp: onSeeAllNextUp,
                            libraries: libraries
                        )
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it. The hovered title's
        // picture sits on that, behind everything. See `HomeAmbient`.
        .background { HomeAmbientBackdrop(pipeline: pipeline, serverURL: serverURL, app: app) }
        .animation(Theme.Motion.transition, value: layout)
        // The libraries are empty on first appearance — they arrive from the sync a
        // moment later — and the .task below only ran once, so Home stayed bare until
        // you navigated away and back, which rebuilt the view. Reloading when they
        // actually change is the fix.
        // Keyed on the ids, not the records. `LibraryRecord` carries `itemCount`,
        // which the sync rewrites on every pass, so watching the whole array meant a
        // second full rebuild of the home screen at every launch — 1.3s of queries
        // returning counts identical to the load a moment earlier — for a number no
        // shelf displays. A library being added, removed or reordered is the only
        // change here that alters what the shelves should contain.
        .onChange(of: libraries.map(\.id)) { _, _ in
            Task {
                await model?.load(
                    libraries: libraries, layout: layout, reason: "libraries changed"
                )
            }
        }
        // Five sheets in one modifier, shared with every other surface that
        // shows tiles. See `EntryActions+Sheets`.
        .entryActions(entryState, in: entryContext)
        .collectionDeleteConfirm(
            target: $deleteCollectionTarget, repository: repository, app: app
        ) {
            await model?.load(libraries: libraries, layout: layout)
        }
        // Keyed on the token as well, so revealing a private library re-reads every
        // shelf. Nothing in this view's own inputs changes when that happens — the
        // queries simply start returning different rows — so without a key here the
        // home screen would keep showing the answer from before.
        .task(id: app?.homeReloadToken ?? 0) {
            let model = model ?? HomeModel(repository: repository)
            self.model = model
            // So a finished sync can re-read the shelves without going through this
            // view's inputs. See `HomeModel.refresh`.
            app?.homeModel = model
            // Whatever the reveal toggle currently says. The Top 10 rows keep
            // private libraries out of the charts either way — see
            // `LibraryKinds.libraryIds`.
            model.privateLibraryIds = app?.privateLibraryIds ?? []
            await model.load(libraries: libraries, layout: layout, reason: "home appeared")
            // What the launch screen waits for. Every service being up is not the
            // same as there being something to look at, and this is the moment the
            // first screen actually has its content.
            app?.homeDidLoad = true
            app?.noteReady()
        }
    }

    @ViewBuilder
    private var loadingOrEmpty: some View {
        VStack(spacing: Theme.Space.md) {
            if model?.isLoading == true {
                ProgressView()
                Text("Loading your library…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Palette.textDisabled)
                Text("Nothing here yet")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Once your libraries finish syncing, they'll show up here.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI
import LumiereKit

/// The item page: films, series, seasons and episodes all land here.
///
/// The header renders from the cached row the moment you click, so opening
/// something never shows a spinner. Cast, streams and chapters fill in behind it.
struct DetailView: View {
    let itemId: String
    /// Set when arriving from a Next Up or Continue Watching card, naming the episode
    /// to lead with rather than letting the page work it out for itself.
    var focusEpisodeId: String?
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    let serverName: String
    let onPlay: (String) -> Void
    /// Passed in rather than reached for: the detail page is created from the shell,
    /// which already owns the download manager.
    var app: AppModel?

    // Not private: DetailView+Modals.swift reads these to present the sheets, and
    // Swift's `private` is file-scoped.
    @State var model: DetailModel?
    @State var showingAddItems = false
    /// The item whose metadata is being edited. Not private: DetailView+Modals.swift
    /// presents the sheet, and an episode row opens it too — a katakana title lands
    /// on individual episodes as often as on the show.
    @State var editingId: String?
    // Not private: DetailView+Sections.swift sets this from a collection member's
    // context menu to open the alert declared below.
    @State var relabelingEntry: LibraryEntry?
    /// A collection member whose artwork is being chosen. Not private: the shelf
    /// rows in DetailView+Sections.swift set it.
    @State var collectionArtworkId: String?
    /// Whether the authoring wizard is open on this collection.
    @State var isFinishingCollection = false
    @State var isConfirmingCollectionDelete = false
    /// Whether the filename-repair preview is open. Series only — there is nothing
    /// to renumber on a film.
    @State var isRepairingEpisodes = false
    /// The episode whose thumbnail is about to be frozen. Asked rather than done.
    @State var freezeThumbnailId: String?
    /// The season whose Identify sheet is open. See `seasonActions`.
    @State var identifySeason: LibraryEntry?
    /// A collection's Identify sheet. See `CollectionSeriesSheet`.
    @State var identifyingCollection = false
    @State var isScanningCollection = false
    /// An episode about to leave the library, and by which door.
    @State var removalTarget: RemovalTarget?
    // Not private: DetailView+Modals.swift leaves the page after a delete, since
    // staying on the detail page of something that no longer exists is worse than
    // any error it could show.
    @Environment(\.dismiss) var dismiss
    @State var relabelText = ""
    /// The member whose position in its row is being set, and the typed number.
    @State var positionEntry: LibraryEntry?
    @State var positionText = ""
    /// The member a removal has been asked for, held while it is confirmed.
    @State var removingFromCollection: LibraryEntry?
    /// The finished download a deletion has been asked for.
    @State var deletingDownloadId: String?
    // Not private: DetailView+Sections.swift (castMember) reads this too.
    @Environment(\.displayScale) var scale
    @Environment(\.folderLibraryIds) var folderLibraryIds

    private func displayedSource(for model: DetailModel) -> MediaSource? {
        model.isSeries ? model.heroDetail?.mediaSources?.first : model.selectedSource
    }

    private func displayedChapters(for model: DetailModel) -> [Chapter]? {
        model.isSeries ? model.heroDetail?.chapters : model.detail?.chapters
    }

    var body: some View { withModals(core) }

    private var core: some View {
        ScrollView {
            if let model, let entry = model.entry {
                // Tighter under the header than between the sections below it. The
                // hero's gradient has already faded into the page by its last few
                // rows, so a full `shelfGap` there reads as a hole rather than as a
                // separation — the first shelf belongs to the header.
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    header(model: model, entry: entry)

                    // `shelfGap`, the same rhythm Home uses between its rows, and
                    // no horizontal inset on this column: each section applies the
                    // page margin itself so that a shelf's scroll view can still
                    // run to the window edge. Insetting the column clipped every
                    // shelf's first and last card.
                    VStack(alignment: .leading, spacing: Theme.Space.shelfGap) {
                        if model.isCollection {
                            collectionBody(model)
                            MissingFilmsRow(repository: model.repository, collectionId: model.itemId)
                        } else {
                            CollectionNudge(repository: model.repository, itemId: model.itemId)
                            OtherCopiesLine(repository: model.repository, entry: entry)
                            if model.isSeries {
                                SeasonEpisodeList(
                                    model: model,
                                    pipeline: pipeline,
                                    serverURL: serverURL,
                                    onEditEpisode: app?.client == nil ? nil : { editingId = $0 },
                                    onSeasonArtwork: app?.client == nil ? nil : {
                                        collectionArtworkId = $0
                                    },
                                    onRepairEpisodes: app?.client == nil ? nil : {
                                        isRepairingEpisodes = true
                                    },
                                    // Confirmed, because the consequence cannot be
                                    // seen and cannot be undone from the menu: a
                                    // frozen thumbnail also stops the episode's
                                    // synopsis updating. That warning used to live
                                    // in a `.help` on the menu row, where macOS
                                    // never drew it.
                                    onGenerateThumbnail: app?.client == nil ? nil : { id in
                                        freezeThumbnailId = id
                                    },
                                    onEpisodeArtwork: app?.client == nil ? nil : {
                                        collectionArtworkId = $0
                                    },
                                    // Asked through the same dialogs the shared
                                    // menu uses. See `removalTarget`.
                                    onRemoveEpisode: app?.client == nil
                                        || !Preference.allowsRemoval.value ? nil : {
                                        removalTarget = RemovalTarget(entry: $0, permanent: false)
                                    },
                                    onDeleteEpisode: app?.client == nil
                                        || !Preference.allowsRemoval.value ? nil : {
                                        removalTarget = RemovalTarget(entry: $0, permanent: true)
                                    },
                                    onToggleEpisodeWatched: { id, played in
                                        Task { await model.setEpisodeWatched(id, played: played) }
                                    },
                                    seasonActions: { seasonActions($0, model: model) },
                                    onPlayEpisode: { onPlay($0) }
                                )
                            }

                            // The TV app's running order below the hero: who is in
                            // it, then what else there is to watch, and only then
                            // the background details. The technical panel used to
                            // sit third, which put a collapsed box of codec names
                            // between the cast and the extras; it lives inside
                            // About now, at the foot of the page.
                            if !model.credits.isEmpty {
                                castShelf(model.credits, creditedTo: model.creditsSubtitle)
                            }

                            if !model.extras.isEmpty {
                                ForEach(ExtrasGrouping.groups(model.extras, showName: entry.item.name)) { group in
                                    extrasShelf(group.entries, model: model, title: group.title)
                                }
                            }

                            // Above Similar: "the rest of this franchise" is a
                            // stronger relationship than "you might also like",
                            // and burying it under a recommendation shelf is
                            // how the sequence stays invisible.
                            if let franchise = model.franchise {
                                FranchiseStrip(
                                    franchise: franchise,
                                    serverURL: serverURL,
                                    pipeline: pipeline
                                )
                            }

                            if !model.similar.isEmpty {
                                similarShelf(model.similar, model: model)
                            }

                            if let chapters = displayedChapters(for: model), chapters.count > 1 {
                                chapterList(chapters)
                            }

                            DetailAbout(
                                model: model,
                                source: displayedSource(for: model),
                                capabilities: capabilities,
                                folderLibraryIds: folderLibraryIds
                            )
                        }
                    }
                }
                .padding(.bottom, Theme.Space.xxxl)
            } else if let model, !model.isLoadingDetail {
                // Says what went wrong and offers a way on. A bare spinner here was
                // indistinguishable from a page that would arrive in a moment.
                DetailUnavailable(message: model.loadError) {
                    Task { await model.load() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .polishedScrolling()
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Pinned rather than folded into a panel: which server, which file,
            // and what it actually is are the three things you want when
            // something plays badly. A collection is neither, so it gets no footer.
            if let model, let entry = model.entry, !model.isCollection {
                DetailFooter(
                    serverName: serverName,
                    item: (model.isSeries ? model.heroEntry?.item : nil) ?? entry.item,
                    source: displayedSource(for: model),
                    capabilities: capabilities
                )
            }
        }
        .task {
            let model = model ?? DetailModel(
                itemId: itemId, repository: repository, focusEpisodeId: focusEpisodeId
            )
            self.model = model
            // Alongside the load, for the life of the page: the page follows
            // the database rather than each command remembering to re-read.
            async let watching: Void = model.observeWatchState()
            await model.load()
            await watching
        }
        .onLibraryChange { change in
            await model?.refreshFromCache()
            // A collection's members come from the server, not the cache.
            if let model, model.isCollection, change.itemId == model.itemId { await model.loadCollectionItems() }
        }
    }
}

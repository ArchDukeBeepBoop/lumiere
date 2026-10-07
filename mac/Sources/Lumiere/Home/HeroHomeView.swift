import SwiftUI
import LumiereKit

/// Layout A: a full-bleed backdrop of the top resume item, then shelves.
///
/// Differs from Classic only in the backdrop at the top. Everything below — Next Up,
/// the card actions, the routing — is deliberately the same, because switching
/// layouts should change how Home *looks*, not what it can do. It used to lose the
/// Next Up shelf and every right-click action, so choosing this layout quietly gave
/// up features.
struct HeroHomeView: View {
    /// Plain rather than `@Bindable`: nothing on this screen writes back to the
    /// model any more. The one binding it had fed the shelf filter's text field.
    let model: HomeModel
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    let onOpenLibrary: (LibraryRecord) -> Void
    /// "See All" on a Latest shelf. Separate from `onOpenLibrary` because the two
    /// now go to different places: the fifty most recent, or the library itself.
    let onSeeAllLatest: (LibraryRecord) -> Void
    let onSeeAllResume: () -> Void
    /// See All on the Forgotten shelf. Optional with a no-op default so the
    /// previews and the compact layout, which does not draw that shelf, need
    /// not supply one.
    var onSeeAllForgotten: () -> Void = {}
    /// See `ClassicHomeView`.
    let onSeeAllNextUp: () -> Void
    let shelfLibraries: [LibraryRecord]
    var app: AppModel?
    var repository: LibraryRepository?

    /// The item whose artwork is being chosen or removed. Was missing here, which
    /// is why the menu command did nothing on this screen.
    /// The collection a deletion has been asked for, held while it is confirmed.
    @State private var deleteCollectionTarget: LibraryEntry?
    /// The shared menu's state: the sheets it opens. Replaces five separate
    /// @State properties each home layout kept for itself.
    @State private var entryState = EntryActionState()
    /// The item whose Add to Playlist sheet is open. See `shelfActions`.
    /// See `ClassicHomeView`. One order, both layouts.
    @AppStorage(HomeOrder.storageKey) private var storedOrder = ""
    /// Turns the cap off. The cap is an opinion about a default, not a rule
    /// about what anyone is allowed to see.
    @AppStorage("homeShowsAllShelves") private var showsAllShelves = false

    /// Not private: HeroHomeView+Rows.swift draws from it.
    /// Every section the order names, before the cap.
    var allSections: [HomeSection] {
        HomeOrder.resolve(stored: storedOrder, libraryIds: shelfLibraries.map(\.id))
    }

    /// What is actually drawn: at most seven shelves, empty ones skipped rather
    /// than counted. See `HomeShelfCap` — and `showsAllShelves` for the way out.
    var sections: [HomeSection] {
        model.capped(allSections, layout: .hero, showAll: showsAllShelves).visible
    }

    /// How many shelves the cap is holding back, for the note at the foot.
    var heldBackShelves: Int {
        model.capped(allSections, layout: .hero, showAll: showsAllShelves).heldBack
    }

    /// The same actions Classic offers, including the dismissal that only makes
    /// sense on a home shelf.
/// A Top 10 row, with the control that changes it.
    ///
    /// The subtitle names what the ranking is, because "Top 10" on its own invites
    /// the question and the answer is not obvious — see `HomeModel+Top10` for what
    /// this ranking can and cannot do.
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
                            entry: entry, serverURL: serverURL, pipeline: pipeline,
                            width: Theme.Art.shelfPosterWidth,
                            metadata: shelfActions(for: entry)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Not private, here and below: HeroHomeView+Rows.swift draws with them, and
    // Swift scopes `private` to the file.
    var entryContext: EntryActionContext? {
        guard let repository else { return nil }
        return EntryActionContext(
            app: app,
            repository: repository,
            // A home shelf has no single row to refresh: the shelves are
            // queries, so re-running them is the honest equivalent.
            refreshRow: { _ in await model.load(libraries: shelfLibraries, layout: .hero) }
        )
    }

    /// The same menu every other surface offers, plus the one command that only
    /// makes sense here.
    ///
    /// Forty lines of its own until now, and it had drifted where it mattered:
    /// no offline guards at all, and no Add to Playlist, on the shelves people
    /// look at first. See `EntryActionExtras`.
    func shelfActions(for entry: LibraryEntry) -> MetadataActions? {
        guard let entryContext else { return nil }
        return entryState.actions(
            for: entry,
            in: entryContext,
            extras: EntryActionExtras(
                // Nowhere else has shelves to be hidden from.
                hideFromShelves: { id in await app?.hideFromShelves(itemId: id) },
                deleteCollection: { deleteCollectionTarget = $0 }
            )
        )
    }

    var body: some View {
        ScrollView {
            // Lazy vertically, eager horizontally, and the asymmetry is the point.
            //
            // A plain VStack here built every shelf on the home screen at once —
            // one "Latest" row per library, twenty tiles each, every poster
            // decoded whether or not it had ever been on screen. On a library
            // list like this that is over two hundred bitmaps, and it was most of
            // the app's memory.
            //
            // Vertical laziness is the well-behaved case: shelves are uniform
            // height and stack in the scroll direction, so SwiftUI estimates the
            // content size correctly. Doing the same to the *rows* is what left
            // blank space running past the last tile.
            LazyVStack(alignment: .leading, spacing: Theme.Space.shelfGap) {
                // The same order Classic draws, from the same preference. Two
                // layouts holding two opinions about which row comes first would be
                // two things to keep in step, and one of them would drift.
                ForEach(sections, id: \.id) { section in
                    view(for: section)
                }

                // Nothing is dropped silently. A home screen that quietly stops
                // at seven is a bug report; one that says what it is holding
                // back, and offers the rest in one click, is a choice.
                if heldBackShelves > 0 {
                    Button {
                        withAnimation(Theme.Motion.hover) { showsAllShelves = true }
                    } label: {
                        Text("\(heldBackShelves) more shelf\(heldBackShelves == 1 ? "" : "s") · Show all")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.top, Theme.Space.lg)
                }

            }
            // No inset above the hero. The backdrop is meant to reach the top
            // of the screen — a strip of empty page over a full-bleed picture
            // reads as the picture having been placed on the page rather than
            // being it. The inset comes back when there is no hero to show, so a
            // shelf never starts hard against the title bar.
            .padding(.top, model.heroEntries.isEmpty ? Theme.Space.xl : 0)
            .padding(.bottom, Theme.Space.xxxl)
        }
        .polishedScrolling()
        // Five sheets in one modifier, shared with every other surface that
        // shows tiles. See `EntryActions+Sheets`.
        .entryActions(entryState, in: entryContext)
        .collectionDeleteConfirm(
            target: $deleteCollectionTarget, repository: repository, app: app
        ) {
            await model.load(libraries: shelfLibraries, layout: .hero)
        }
    }
}

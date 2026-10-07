import SwiftUI
import LumiereKit

/// Layout C — Infuse's own home, and the default.
///
/// Wide continue cards across the top rather than a full-bleed hero, then the
/// library shelves. Section headers carry the server name, because Infuse can
/// aggregate several sources and "Latest Movies" alone stops meaning anything
/// once there are two — as a subtitle, not appended to the title: repeated down
/// a dozen headers, " - Jellyfin" was the loudest thing on the screen.
struct ClassicHomeView: View {
    /// Plain rather than `@Bindable`: nothing on this screen writes back to the
    /// model any more. The one binding it had fed the shelf filter's text field.
    let model: HomeModel
    let pipeline: ImagePipeline
    let serverURL: URL
    let serverName: String
    let libraries: [LibraryRecord]
    /// Only the hero needs these, and only to decide what a Play button can
    /// promise. Optional so the previews and the demo, which have no probe
    /// result to hand, still build a Classic screen.
    var capabilities: SystemCapabilities?
    var app: AppModel?
    let onOpenLibrary: (LibraryRecord) -> Void
    /// "See All" on a Latest shelf. Separate from `onOpenLibrary` because the two
    /// now go to different places: the fifty most recent, or the library itself.
    let onSeeAllLatest: (LibraryRecord) -> Void
    let onSeeAllResume: () -> Void
    /// See All on the Forgotten shelf. Optional with a no-op default so the
    /// previews and the compact layout, which does not draw that shelf, need
    /// not supply one.
    var onSeeAllForgotten: () -> Void = {}
    /// The same, for Next Up. Its own closure rather than a shared one because the
    /// two rows go to different pages — see `NextUpBrowseView`.
    let onSeeAllNextUp: () -> Void
    var repository: LibraryRepository?

    /// The item whose artwork is being chosen or removed. Was missing here, which
    /// is why the menu command did nothing on this screen.
    /// The collection a deletion has been asked for, held while it is confirmed.
    @State private var deleteCollectionTarget: LibraryEntry?
    /// The shared menu's state: the sheets it opens. Replaces five separate
    /// @State properties each home layout kept for itself.
    @State private var entryState = EntryActionState()
    /// The item whose Add to Playlist sheet is open. See `shelfActions`.
    /// The running order, as chosen in Settings. Stored as one string because
    /// `@AppStorage` holds a value, not a list — `HomeOrder` owns the parsing.
    @AppStorage(HomeOrder.storageKey) private var storedOrder = ""
    /// Turns the cap off. The cap is an opinion about a default, not a rule
    /// about what anyone is allowed to see.
    @AppStorage("homeShowsAllShelves") private var showsAllShelves = false

    /// What to draw, in order, reconciled against the libraries that exist now.
    /// Not private: ClassicHomeView+Rows.swift draws from it.
    /// Every section the order names, before the cap.
    var allSections: [HomeSection] {
        HomeOrder.resolve(stored: storedOrder, libraryIds: libraries.map(\.id))
    }

    /// What is actually drawn: at most seven shelves, empty ones skipped rather
    /// than counted. See `HomeShelfCap` — and `showsAllShelves` for the way out.
    var sections: [HomeSection] {
        model.capped(allSections, layout: .classic, showAll: showsAllShelves).visible
    }

    /// How many shelves the cap is holding back, for the note at the foot.
    var heldBackShelves: Int {
        model.capped(allSections, layout: .classic, showAll: showsAllShelves).heldBack
    }

    /// Right-click actions for a card on a home shelf, including the dismissal that
    /// only makes sense here.
    /// Not private: the Top 10 rows in ClassicHomeView+Top10.swift build their
    /// menus with it, and Swift's `private` is file-scoped.
    var entryContext: EntryActionContext? {
        guard let repository else { return nil }
        return EntryActionContext(
            app: app,
            repository: repository,
            // A home shelf has no single row to refresh: the shelves are
            // queries, so re-running them is the honest equivalent.
            refreshRow: { _ in await model.load(libraries: libraries, layout: .classic) }
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
                // Whatever order the user put them in. See `HomeOrder`: the
                // sequence used to be written here, which made it a fact about the
                // source rather than a preference.
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
            await model.load(libraries: libraries, layout: .classic)
        }
    }

}

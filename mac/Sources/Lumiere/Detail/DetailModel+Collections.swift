import Foundation
import LumiereKit

/// One row on a collection's page — a source library's worth of members, or a
/// manually-labelled group of them.
struct CollectionShelf: Identifiable {
    let id: String
    let title: String
    let entries: [LibraryEntry]
}

/// A collection is not one piece of media: it is a curated group of them, so its
/// page has no cast, no chapters, no single file — only its members, arranged into
/// shelves. Kept out of DetailModel.swift, which is written around a single item's
/// detail; a collection's load path, grouping and editing are a different enough
/// shape to earn their own file.
extension DetailModel {

    var isCollection: Bool {
        entry?.item.itemType == .boxSet
    }

    /// Fetches this collection's members and the library names needed to group
    /// them automatically, then computes shelves.
    func loadCollectionItems() async {
        collectionItems = (try? await repository.collectionItems(collectionId: itemId)) ?? []
        shelfLabelOverrides = (try? await repository.shelfLabels(collectionId: itemId)) ?? [:]
        collectionRanks = (try? await repository.collectionRanks(collectionId: itemId)) ?? [:]
        // A collection never given an order takes the default from Settings.
        let chosen = UserDefaults.standard.string(forKey: Self.sortKey(itemId))
            ?? Preference.collectionDefaultOrder.value
        if let stored = Optional(chosen),
           let sort = CollectionOrder(rawValue: stored), sort != collectionSort {
            // Assigned through the backing store, not the property: the observer on
            // `collectionSort` would re-save what was just read and, worse, seed a
            // personal order from a list that has not been arranged yet.
            storedSort = sort
        }
        if libraryNames.isEmpty {
            let libraries = (try? await repository.libraries()) ?? []
            libraryNames = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.name) })
        }
        recomputeShelves()
    }

    /// Adds items found through the library-wide picker, then reloads so the new
    /// members appear on whichever shelf their library groups them under.
    func addItemsToCollection(_ itemIds: [String]) async {
        guard !itemIds.isEmpty else { return }
        do {
            try await repository.addToCollection(collectionId: itemId, itemIds: itemIds)
        } catch {
            // Reported rather than swallowed: the page reloads either way, so a
            // failed add looked exactly like adding nothing.
            collectionError = ConnectionState.message(for: error)
        }
        await loadCollectionItems()
    }

    func removeFromCollection(_ memberId: String) async {
        do {
            try await repository.removeFromCollection(collectionId: itemId, itemId: memberId)
        } catch {
            collectionError = ConnectionState.message(for: error)
            return
        }
        collectionItems.removeAll { $0.id == memberId }
        shelfLabelOverrides.removeValue(forKey: memberId)
        recomputeShelves()
    }

    /// Takes the order currently on screen as the personal one.
    func seedPersonalOrder() async {
        let ids = collectionShelves.flatMap { $0.entries.map(\.id) }
        guard !ids.isEmpty else { return }
        try? await repository.setCollectionOrder(collectionId: itemId, itemIds: ids)
        collectionRanks = (try? await repository.collectionRanks(collectionId: itemId)) ?? [:]
        recomputeShelves()
    }

    /// Puts a member at a position in the row, counting from one.
    ///
    /// Scoped to the shelf it is on, not to the collection as a whole. A collection
    /// page is several rows — Series, Films, Extras — and "third" means third in the
    /// row you are looking at. Positions across the whole set would be a number
    /// nobody can see or count to.
    func moveInCollection(memberId: String, toPosition position: Int) async {
        guard let shelf = collectionShelves.first(where: { shelf in
            shelf.entries.contains { $0.id == memberId }
        }) else { return }

        var within = shelf.entries.map(\.id)
        guard let from = within.firstIndex(of: memberId) else { return }
        within.remove(at: from)
        within.insert(memberId, at: max(0, min(within.count, position - 1)))

        // Spliced back in place: the other rows keep their own arrangement, and the
        // ranks are global to the collection so all of it has to be written.
        var order: [String] = []
        for other in collectionShelves {
            order += other.id == shelf.id ? within : other.entries.map(\.id)
        }

        try? await repository.setCollectionOrder(collectionId: itemId, itemIds: order)
        collectionRanks = (try? await repository.collectionRanks(collectionId: itemId)) ?? [:]
        recomputeShelves()
    }

    /// Nudges a member one place along its row.
    func nudgeInCollection(memberId: String, by delta: Int) async {
        guard let shelf = collectionShelves.first(where: { shelf in
            shelf.entries.contains { $0.id == memberId }
        }), let index = shelf.entries.firstIndex(where: { $0.id == memberId }) else { return }
        await moveInCollection(memberId: memberId, toPosition: index + 1 + delta)
    }

    /// Forgets the personal arrangement and falls back to release order.
    func clearPersonalOrder() async {
        try? await repository.clearCollectionOrder(collectionId: itemId)
        collectionRanks = [:]
        collectionSort = .releaseDate
    }

    /// The 1-based position of a member in its own row, for the prompt's default.
    func position(of memberId: String) -> Int {
        for shelf in collectionShelves {
            if let index = shelf.entries.firstIndex(where: { $0.id == memberId }) {
                return index + 1
            }
        }
        return 1
    }

    /// `label: nil` returns a member to its automatic, per-library shelf.
    func setShelfLabel(itemId memberId: String, label: String?) async {
        try? await repository.setShelfLabel(collectionId: itemId, itemId: memberId, label: label)
        if let label, !label.isEmpty {
            shelfLabelOverrides[memberId] = label
        } else {
            shelfLabelOverrides.removeValue(forKey: memberId)
        }
        recomputeShelves()
    }

    /// Groups members by manual override first, then by the library each one
    /// actually lives in — "grouped manually and by metadata," in that order, so a
    /// deliberate move always wins over the automatic guess. Shelves are ordered by
    /// first appearance in the collection's own member order, which keeps the
    /// layout stable rather than re-sorting alphabetically on every reload.
    /// The row a member falls into when nobody has moved it by hand.
    ///
    /// By *kind*, not by library. Grouping by library name put a franchise's TV run
    /// under "Anime" and its films under "Anime Movies" — two rows named after where
    /// the files happen to live rather than after what they are, and on a collection
    /// built from one library, one row holding everything. What someone reading a
    /// franchise wants is the distinction between the shows, the films and the
    /// extras, which is a property of the items themselves.
    static func automaticLabel(for entry: LibraryEntry) -> String {
        if entry.item.extraType != nil { return "Extras" }
        switch entry.item.itemType {
        case .series: return "Series"
        case .movie: return "Films"
        case .boxSet: return "Collections"
        case .episode:
            // A loose episode in a collection is an OVA or a special far more often
            // than a stray — those are the ones filed outside a season.
            return entry.item.parentIndexNumber == 0 ? "Specials" : "Episodes"
        default: return "Other"
        }
    }

    /// The order rows appear in, which is the order someone watches them: the shows
    /// first, then the films that go with them, then the material around the edges.
    static func shelfRank(_ title: String) -> Int {
        ["Series", "Films", "Episodes", "Specials", "Collections", "Extras"]
            .firstIndex(of: title) ?? 50
    }

    /// Re-groups after the sort changes. Named apart from `recomputeShelves` only
    /// because a `didSet` in the other file cannot reach a private method here.
    func recomputeShelvesPublicly() { recomputeShelves() }

    private func recomputeShelves() {
        var order: [String] = []
        var groups: [String: [LibraryEntry]] = [:]

        for entry in CollectionOrder.sorted(
            collectionItems, by: collectionSort, ranks: collectionRanks
        ) {
            let label = shelfLabelOverrides[entry.id] ?? Self.automaticLabel(for: entry)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(entry)
        }

        collectionShelves = order
            .sorted { left, right in
                let leftRank = Self.shelfRank(left), rightRank = Self.shelfRank(right)
                // Hand-named rows keep their arrival order after the automatic ones,
                // since a label someone typed has an intent no ranking can guess.
                return leftRank == rightRank
                    ? (order.firstIndex(of: left) ?? 0) < (order.firstIndex(of: right) ?? 0)
                    : leftRank < rightRank
            }
            .map { title in
                CollectionShelf(id: title, title: title, entries: groups[title] ?? [])
            }
    }
}

/// Which artwork the header draws, when a series has seasons.
///
/// Split here for the 300-line limit. It belongs beside the other "what does this
/// page actually show" decisions rather than in the loading path.
extension DetailModel {
    /// The season currently being browsed, when one is.
    var selectedSeason: LibraryEntry? {
        seasons.first { $0.id == selectedSeasonId }
    }

    /// Where the header's backdrop should come from.
    ///
    /// The season's own art when it has any, so stepping between seasons changes
    /// the picture — a long-running show's seasons often look nothing alike, and a
    /// single backdrop for all of them loses that. Falls back to the series, which
    /// on a real library is what happens nearly always: of 3,131 cached seasons,
    /// not one carries a backdrop tag. The chain is here so that setting one
    /// through Choose Artwork takes effect, rather than being quietly ignored.
    func backdropSource(seriesEntry: LibraryEntry?) -> LibraryEntry? {
        if let season = selectedSeason,
           season.item.backdropTag != nil || season.item.thumbTag != nil {
            return season
        }
        return seriesEntry
    }

    /// Finds the franchise, if this is part of one.
    ///
    /// Best-effort and late: it reads every collection to find the one holding
    /// this title, which is cheap on a library with forty collections and not
    /// worth blocking the page for.
    func loadFranchise() async {
        franchise = try? await repository.franchise(for: itemId)
    }
}

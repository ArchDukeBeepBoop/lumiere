import SwiftUI
import LumiereKit

/// How the grid fills itself: one row, one page, or the whole thing again.
///
/// Split from LibraryGridView.swift for the project's 300-line rule.
extension LibraryGridView {

    /// Re-reads one row and swaps it in place.
    ///
    /// What an edit needs, and what `reload()` cannot give it: reload empties
    /// `entries` and refetches from offset zero, so the grid loses every page it
    /// had loaded and the scroll position with them. Editing the title of
    /// something eight screens down threw you back to the top — the change landed
    /// and you could no longer see it.
    ///
    /// Only the row changed, so nothing else moves and nothing is refetched.
    func refreshRow(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let fresh = (try? await repository.entriesById([id]))?.first
        else { return }
        entries[index] = fresh
    }

    func reload() async {
        isLoading = true
        // Bumped before anything is awaited. A page already in flight — a scroll
        // that fired just as the filter debounce landed — used to finish and append
        // its pre-filter rows to the array reload had just cleared, so the grid
        // showed unfiltered results under a filter, or an empty-library message.
        generation += 1
        let pass = generation
        offset = 0
        entries = []
        total = (try? await repository.count(
            types: tab.types,
            libraryId: libraryId, searchTerm: activeFilter,
            genre: genre, studio: studio, unwatchedOnly: unwatchedOnly
        )) ?? 0
        // The rail describes the whole library, so it is rebuilt whenever what
        // "first" means changes — a genre filter or a different sort.
        anchors = (try? await repository.alphabetAnchors(
            libraryId: libraryId,
            types: tab.types,
            sort: sort,
            genre: genre,
            studio: studio,
            // The same two the grid is filtered by, so the rail counts the rows
            // that are actually on screen rather than the whole library.
            searchTerm: activeFilter,
            unwatchedOnly: unwatchedOnly
        )) ?? []
        await loadPage(generation: pass)
        isLoading = false
    }

    func loadPage(generation: Int? = nil) async {
        let generation = generation ?? self.generation
        // The guard admits a *newer* generation, and that is the whole fix.
        //
        // It used to be a plain `!isLoadingPage`, which meant a fresh load whose
        // page fetch arrived while a scroll-triggered page was still in flight
        // returned immediately, having already cleared `entries` — and the in-flight
        // page then discarded itself as stale. The result was a permanently empty
        // list with a non-zero total, no spinner, and nothing left on screen able to
        // trigger paging again. Switching scope, toggling Unwatched, picking a genre
        // or letting the search debounce fire while a page was loading all did it.
        //
        // An older page still cannot append, because the generation check after the
        // await rejects it. So letting the newer one through costs one wasted
        // request and fixes the dead end.
        guard !isLoadingPage || generation > loadingGeneration else { return }
        isLoadingPage = true
        loadingGeneration = generation
        defer { isLoadingPage = false }

        let page = (try? await repository.entries(
            types: tab.types,
            sort: sort,
            descending: descending,
            libraryId: libraryId,
            limit: pageSize,
            offset: offset,
            searchTerm: activeFilter,
            genre: genre,
            studio: studio,
            unwatchedOnly: unwatchedOnly,
            // The grid keeps every row it pages in, and a full library is tens of
            // thousands of them. See `LibraryRepository.Projection`: 51.7 MB of
            // `ItemRecord` for the Anime library, against 12.3 MB for the columns a
            // tile reads.
            projection: .tile
        )) ?? []

        // Discarded if a reload happened while this was in flight: the rows answer
        // a question nobody is asking any more.
        guard generation == self.generation else { return }
        entries.append(contentsOf: page)
        offset += page.count
    }

    /// Right-click actions, nil without an AppModel so a card simply has no menu
    /// rather than a menu that cannot act.
    func loadMoreIfNeeded(currentItem entry: LibraryEntry) async {
        guard entries.count < total,
              let index = entries.firstIndex(where: { $0.id == entry.id }),
              index >= entries.count - 12 else { return }
        await loadPage()
    }
}

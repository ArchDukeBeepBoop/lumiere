import SwiftUI
import LumiereKit

/// Fetching a music listing one window at a time.
///
/// Music and playlists are never synced — recursing a music library pulls every
/// track, which is unbounded work for a cache nothing browses — so every screen
/// here is a live request rather than a query. That made a single large fetch the
/// obvious shape, and it was wrong: a library past the ceiling stopped dead, with
/// no count, no spinner, and an A–Z rail beside it implying the rest was there.
///
/// Split from ServerBrowserView.swift for the project's 300-line rule.
extension ServerBrowserView {

    func load() async {
        loadFailed = false
        expandedSeries = []
        favouriteOverrides = [:]
        playlistEntryIds = [:]
        isEditingPlaylist = false
        generation += 1

        // What this screen showed last time, if it showed anything. Straight back on
        // screen while the request below refreshes it — so stepping into an album and
        // out again is instant rather than a spinner over a list the app already had.
        // See `recentPages`.
        let remembered = recentPages[reloadKey]
        entries = remembered ?? []
        total = remembered?.count ?? 0
        // A spinner only when there is nothing to look at. Over remembered rows it
        // would be reporting work the user has no reason to wait for.
        isLoading = remembered == nil
        defer { isLoading = false }

        await loadPage(generation: generation, offset: 0)
    }

    /// Remembers this screen's rows, dropping the oldest when the shelf is full.
    func remember(_ rows: [LibraryEntry], for key: String) {
        guard !rows.isEmpty else { return }
        if recentPages[key] == nil { recentOrder.append(key) }
        recentPages[key] = rows
        while recentOrder.count > Self.recentPageLimit {
            recentPages.removeValue(forKey: recentOrder.removeFirst())
        }
    }

    /// Fetches the next window and appends it.
    ///
    /// Music is never synced — recursing a music library pulls every track — so
    /// every screen here is a live request. It used to be a single one with a large
    /// limit: a library past that stopped dead, with no count, no spinner and an
    /// A–Z rail beside it implying the rest was there.
    func loadPage(generation pageGeneration: Int? = nil, offset explicitOffset: Int? = nil) async {
        let pageGeneration = pageGeneration ?? generation
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
        guard !isLoadingPage || pageGeneration > loadingGeneration else { return }
        isLoadingPage = true
        loadingGeneration = pageGeneration
        defer { isLoadingPage = false }

        // Not attempted at all with the server away. Nothing on this screen is
        // cached — that is what the note above is about — so the request can only
        // time out, and doing it once per scroll would sit the browser on a spinner
        // for a minute at a time while the reconnect probe is already asking the
        // same question far more cheaply.
        if app?.isOffline == true {
            if entries.isEmpty { loadFailed = true }
            return
        }

        // Normally "how many rows do I already have", but a reload that put
        // remembered rows on screen must still ask for page one — otherwise the
        // refresh fetches page two and appends it under them. See `load`.
        let offset = explicitOffset ?? entries.count
        do {
            let fetched: MusicPage
            if isPlaylist, !path.isEmpty {
                // Inside a playlist, and only here, the rows come from the playlist
                // endpoint — the one that reports each row's own entry id, which is
                // what removal has to name.
                let result = try await repository.playlistChildrenPage(
                    playlistId: currentId, offset: offset, limit: pageSize
                )
                fetched = result.page
                guard pageGeneration == generation else { return }
                playlistEntryIds.merge(result.entryIds) { _, new in new }
            } else if let genre = openGenre {
                // A genre is a filter, not a folder: its id is its own name, so
                // asking for its children would name a row that does not exist.
                fetched = try await repository.musicGenrePage(
                    genre: genre, parentId: libraryId, offset: offset, limit: pageSize
                )
            } else if showsScopePicker, scope == .favourites {
                fetched = try await repository.favouriteAudioPage(
                    offset: offset, limit: pageSize
                )
            } else if showsScopePicker, !scope.types.isEmpty {
                fetched = try await repository.serverItemsPage(
                    parentId: currentId, types: scope.types,
                    // Tracks carry their own order; albums and artists are always
                    // by name, which is the only order those two make sense in.
                    sortBy: scope == .tracks ? trackSort.sortBy : scope.sortBy,
                    sortOrder: scope == .tracks && !trackSortAscending
                        ? .descending : .ascending,
                    offset: offset, limit: pageSize
                )
            } else {
                fetched = try await repository.serverChildrenPage(
                    parentId: currentId, offset: offset, limit: pageSize
                )
            }

            // Discarded if the folder or scope changed while this was in flight.
            guard pageGeneration == generation else { return }
            if offset == 0 {
                // The first page *replaces* what was remembered rather than doubling
                // it — the rows on screen are last visit's answer to the same
                // question, not the start of this one.
                entries = fetched.entries
            } else {
                entries.append(contentsOf: fetched.entries)
            }
            total = fetched.total
            remember(entries, for: reloadKey)
            // A page that came back empty while the total still claims more would
            // otherwise be asked for again on every scroll, forever.
            if fetched.entries.isEmpty { total = entries.count }
        } catch {
            guard pageGeneration == generation else { return }
            if entries.isEmpty { loadFailed = true }
            // Offered to the connection state, which decides whether this was a
            // server that is gone or a request that failed on its own merits. This
            // is one of the few screens that talks to the server outside the sync,
            // so it is often where an outage is first noticed.
            app?.noteRequestFailure(error)
        }
    }

    /// Pulls the next page in as the end of the list comes into view.
    func loadMoreIfNeeded(currentItem entry: LibraryEntry) async {
        guard entries.count < total,
              let index = entries.firstIndex(where: { $0.id == entry.id }),
              index >= entries.count - 20 else { return }
        await loadPage()
    }

    /// Keeps fetching until a letter is reachable, for the A–Z rail.
    ///
    /// The rail is built from what is loaded, so on a paged list every letter past
    /// the first window pointed at nothing. Rows arrive in sort order, so loading
    /// until the last one reaches the letter is enough — and it stops at the end of
    /// the listing rather than spinning when the letter has no rows at all.
    func loadThrough(letter: String) async {
        // Bounded at two seconds of waiting. See the stall branch below.
        var stalls = 0
        while entries.count < total {
            if let last = entries.last?.item.sortName,
               AlphabetIndex.letter(forSortKey: last) >= letter { return }
            let before = entries.count
            await loadPage()
            guard entries.count == before else {
                stalls = 0
                continue
            }
            // No progress. Either the listing is genuinely exhausted, or a
            // scroll-triggered page of the same generation was already in flight
            // and `loadPage` returned at its guard without doing anything — in
            // which case giving up here is what made tapping a letter mid-scroll
            // do nothing at all, silently, with the rail still lit.
            guard isLoadingPage, stalls < 40 else { return }
            stalls += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

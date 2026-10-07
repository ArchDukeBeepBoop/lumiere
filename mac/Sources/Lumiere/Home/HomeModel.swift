import Foundation
import Observation
import LumiereKit

/// Loads what the home screen shows. Both layouts read the same data, so
/// switching between them costs nothing and never refetches.
@MainActor
@Observable
final class HomeModel {
    var resume: [LibraryEntry] = []
    var recentlyAdded: [LibraryEntry] = []
    var nextUp: [LibraryEntry] = [] { didSet { rememberNextUp() } }
    /// Series with a few episodes to go. See `nearlyFinishedSeries`.
    var finishSeason: [LibraryEntry] = []
    var forgotten: [LibraryEntry] = []  // Started long ago, never resumed.
    var newEpisodeIds: Set<String> = []  // See HomeModel+Series.swift.
    var continueSeries: [LibraryEntry] = []  // See HomeModel+Series.swift.
    var libraryShelves: [(library: LibraryRecord, entries: [LibraryEntry])] = []
    var becauseYouWatched: (title: String, entries: [LibraryEntry])?  // See HomeModel+Because.swift.
    /// Filled from HomeModel+Wall.swift, hence not `private(set)`.
    var wallEntries: [LibraryEntry] = []
    var wallTotal = 0
    private(set) var isLoading = true
    /// The genre row. Not `private(set)`, because Swift's `private` is file-scoped
    /// and the loader that fills it lives in HomeModel+Genres.swift.
    var genreCards: [GenreCardItem] = []
    /// The library row — one card per library, and the home screen's replacement
    /// for the sidebar. Not `private(set)` for the same reason: it is filled from
    /// HomeModel+Libraries.swift.
    var libraryCards: [LibraryCardItem] = []
    /// What the hero cycles through. Not `private(set)` for the same reason as the
    /// two rows above: it is filled from HomeModel+Spotlight.swift.
    var spotlight: [LibraryEntry] = []
    /// item id → the sentence under its title. Only the entries that earned one
    /// appear here; see `SpotlightReason`.
    var spotlightReasons: [String: String] = [:]
    /// Whether `loadSpotlight` has finished. See `heroEntries`.
    var didLoadSpotlight = false

    /// The two Top 10 rows, and where in the pool they currently sit.
    var topFilms: [LibraryEntry] = []
    var topSeries: [LibraryEntry] = []
    var topAnime: [LibraryEntry] = []
    /// Where each Top 10 row sits in its pool. One per row, not one shared: a press
    /// on Films must not move Series and Anime with it.
    var topOffsets: [LibraryKinds.Kind: Int] = [:]
    /// Libraries kept out of the charts whatever the privacy toggle says. See
    /// `LibraryKinds.libraryIds`.
    var privateLibraryIds: Set<String> = []

    /// Which `load` owns the screen.
    ///
    /// Twenty-one call sites reload the home screen — a sync finishing, a library
    /// list changing, a sheet closing, the window regaining focus — and several of
    /// them fire together. Without this two passes interleave their assignments,
    /// so the shelves can end up describing two different moments, and the first to
    /// finish clears `isLoading` while the second is still working. Every write
    /// below is gated on still being the newest caller.
    /// Not private: the loaders split into HomeModel+Libraries/+Spotlight/+Genres
    /// have to check it before they assign, and Swift's `private` is file-scoped.
    var generation = 0

    /// Whether `generation` is still the newest load.
    ///
    /// Every check must sit *after* the await it guards, not before. Before is the
    /// mistake this whole mechanism was written with: the guard passed, the query
    /// then suspended for as long as it took, a newer load started and finished
    /// meanwhile, and the stale result was assigned anyway on resume. A guard before
    /// an await only rejects a load that was already superseded when it started —
    /// which is the half that costs nothing to get wrong.
    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

    /// Not `private`: the HomeModel+*.swift extensions query through it.
    let repository: LibraryRepository

    /// The compact wall pages as you scroll. Paging: HomeModel+Wall.swift.
    var wallOffset = 0
    let wallPageSize = 60
    var isLoadingMore = false

    /// What the last completed load covered, and when. See
    /// HomeModel+Coalescing.swift.
    var lastSignature = ""
    var lastCompletedAt: Date?
    /// The load currently running, if any. Cleared when it finishes.
    var inFlightSignature: String?
    /// Callers that asked for a load identical to the one already running, waiting
    /// for it rather than starting a second.
    ///
    /// They have to *wait* rather than return: `HomeView` sets `homeDidLoad` — what
    /// the launch screen is held back by — on the line after `await load(...)`, so a
    /// coalesced call that returned immediately lifted the launch screen before a
    /// single shelf had been filled. Skipping the duplicate work is right; skipping
    /// the wait was not.
    var loadWaiters: [CheckedContinuation<Void, Never>] = []

    /// What the last `load` was asked for, so `refresh` can repeat it.
    var lastLibraries: [LibraryRecord] = []
    var lastLayout: HomeLayout = .classic

    init(repository: LibraryRepository) {
        self.repository = repository
        showRememberedNextUp()   // HomeModel+Patch.swift
    }

    func load(
        libraries: [LibraryRecord],
        layout: HomeLayout = .classic,
        reason: String = "first load"
    ) async {
        let started = Date()
        // Two view triggers land at launch — `.task` when Home appears, and
        // `.onChange` when the cached libraries arrive a moment later — and which
        // order they come in depends on whether the library list beat the first
        // render. Neither can be removed: without the first, a server with no
        // libraries never sets `homeDidLoad` and the launch screen hangs; without
        // the second, Home stays empty until you navigate away and back.
        //
        // So the second one is dropped here instead, where both are visible. They
        // ran sequentially — 1.55s then 1.44s, identical counts — because the
        // generation guard only abandons a load that is still *running* when a newer
        // one starts, and these did not overlap.
        //
        // Only these two reasons coalesce. A sync, a star or a finished film must
        // always re-read, and those arrive named.
        let signature = libraries.map(\.id).joined(separator: ",") + "|\(layout)"
        if Self.lifecycleReasons.contains(reason) {
            // Already running. This is the case the first attempt missed: the two
            // triggers *overlap*, so a guard that compared against the last
            // completed load saw nothing at all — instrumenting it printed
            // `lastAt=nil` on the second call, because the first had not finished.
            //
            // The generation counter does stop the older pass, but only when it
            // reaches its next checkpoint, so it runs several queries first and
            // throws the answers away. Not starting is cheaper than abandoning.
            if signature == inFlightSignature {
                Diagnostics.log("[home] \(reason) — waiting on identical load in flight")
                await withCheckedContinuation { loadWaiters.append($0) }
                return
            }
            // Or just finished, for the runs where the two land sequentially
            // instead. Both orderings happen; which one depends on whether the
            // cached library list beat the first render.
            if signature == lastSignature, let done = lastCompletedAt,
               Date().timeIntervalSince(done) < Self.coalesceWindow {
                Diagnostics.log("[home] \(reason) — skipped, identical load just ran")
                return
            }
        }
        inFlightSignature = signature
        lastLibraries = libraries
        lastLayout = layout
        generation += 1
        let generation = generation
        isLoading = true
        // Only if nobody newer has started. Otherwise the older pass finishing
        // first would declare the screen loaded while the current one is still
        // filling it in.
        defer {
            // Released whether or not this pass is still the current one: either way
            // it is over, and a waiter left suspended is a launch screen that never
            // lifts.
            let waiting = loadWaiters
            loadWaiters = []
            waiting.forEach { $0.resume() }
            if inFlightSignature == signature { inFlightSignature = nil }

            if isCurrent(generation) {
                isLoading = false
                lastSignature = signature
                lastCompletedAt = Date()
                HomeTimings.record(reason: reason, seconds: Date().timeIntervalSince(started),
                                   rows: [resume.count, recentlyAdded.count, nextUp.count, libraryShelves.count])
            }
        }

        // Read once and applied to both shelves. These are the only two places an
        // item can be dismissed from, so filtering here rather than in the queries
        // keeps the repository unaware of a purely presentational choice.
        let hidden = (try? await repository.hiddenShelfIds()) ?? []

        // Was 12, against 24 titles actually in progress on this library — so half
        // of what you had not finished could not be shown however it was sorted.
        let freshResume = ((try? await repository.resumeEntries(limit: Self.resumeLength)) ?? [])
            .filter { !hidden.contains($0.id) }
        guard isCurrent(generation) else { return }
        resume = freshResume

        // The two questions Continue Watching and Next Up raise without
        // answering. Both are local reads against the same warm cache, so they
        // cost the load almost nothing.
        let freshFinish = ((try? await repository.nearlyFinishedSeries()) ?? [])
            .filter { !hidden.contains($0.id) }
        let freshForgotten = ((try? await repository.forgottenEntries()) ?? [])
            // Never both. Something on Finish the Season is a show you are
            // close to done with; calling it forgotten in the next breath is
            // the app disagreeing with itself on one screen.
            .filter { entry in
                !hidden.contains(entry.id)
                    && !freshFinish.contains { $0.id == entry.id }
            }
        guard isCurrent(generation) else { return }
        finishSeason = freshFinish
        forgotten = freshForgotten; Task { await loadContinueSeries(hidden: hidden, generation: generation); await loadBecauseYouWatched(generation: generation) }

        // Only where something draws it. Classic deliberately renders this
        // section as nothing — it says the same thing one library at a time with
        // its Latest rows — yet the whole-library query behind it ran on every
        // load of every layout, which is the most expensive read on the screen
        // done for a shelf that was never shown.
        //
        // The Hero layout draws it, and the spotlight falls back to it on a
        // library too thin to feature, so it cannot simply go.
        if layout == .hero || heroEntries.isEmpty {
            // Not from everywhere. See `recentlyAddedExclusions`.
            let freshLatest = await latestTiles(
                libraryId: nil,
                hidden: hidden,
                excludingLibraries: Self.recentlyAddedExclusions(
                    libraries: libraries, privateIds: privateLibraryIds
                )
            )
            guard isCurrent(generation) else { return }
            recentlyAdded = freshLatest
        } else {
            recentlyAdded = []
        }

        // Next Up is the next unwatched episode of everything in progress. It
        // comes from the server rather than the cache because "next" depends on
        // watch state across every device, not just this one.
        // Bounded. An unreachable server would otherwise hold the entire home
        // screen behind URLSession's 20-second timeout — the shelves below come
        // from the local cache and have no reason to wait for it.
        // Started, not awaited. `nextUpEntries` is the one shelf that is not a cache
        // read: it makes an HTTP request, then takes a write transaction to cache
        // what came back. Awaiting it put a network round trip — bounded at four
        // seconds, and a sleeping server takes all four — ahead of the fourteen
        // local shelf queries that need nothing from the server. It lands when it
        // lands, behind the same generation guard as everything else.
        let nextUpTask = Task { [repository, hidden] in
            (await Timeout.run(seconds: 4) {
                (try? await repository.nextUpEntries(limit: Self.nextUpLength)) ?? []
            } ?? []).filter { !hidden.contains($0.id) }
        }

        var shelves: [(LibraryRecord, [LibraryEntry])] = []
        for library in libraries {
            // See `latestTiles`: one query cannot fill a shelf that collapses runs,
            // and the two libraries with the most in them were the ones left short.
            let entries = await latestTiles(libraryId: library.id, hidden: hidden)
            if !entries.isEmpty {
                shelves.append((library, entries))
            }
        }
        guard isCurrent(generation) else { return }
        libraryShelves = shelves

        // Never awaited, which is what the comment above always intended and this
        // line quietly undid. Moving the await after the local shelves only changed
        // *when* the load blocked on the network, not whether it did — so the home
        // screen, and the launch screen waiting on it, still could not finish faster
        // than a four-second round trip to a sleeping server. Measured: 6.79s for a
        // load whose other fourteen queries are local reads against a warm cache.
        //
        // The shelf fills in when the answer lands, behind the same generation guard
        // as everything else. One shelf appearing a moment late is a far smaller
        // cost than every shelf waiting for it.
        Task { [weak self] in
            let freshNextUp = await nextUpTask.value
            guard let self, self.isCurrent(generation) else { return }
            self.nextUp = freshNextUp
        }

        // After the shelves, deliberately: the cards reuse the entries just fetched
        // for their artwork, so building them here costs a count per library and
        // almost no artwork queries at all.
        await loadLibraryCards(libraries: libraries, generation: generation)
        // After the shelves for the same reason, and after the cards because the
        // hero is the one thing on this screen that fetches a full-window bitmap:
        // letting the rows resolve first means the page has content under the
        // backdrop by the time the backdrop arrives.
        await loadSpotlight(libraries: libraries, hidden: hidden, generation: generation)
        await loadGenres(generation: generation)
        guard isCurrent(generation) else { return }
        await loadTop(generation: generation, libraries: libraries)
        guard isCurrent(generation) else { return }
        // Only the layout that draws it. `wallEntries` and `wallTotal` are read by
        // HomeView+Compact and by nothing else, so on the classic and hero layouts
        // this was a count plus a 60-row page — 0.36s measured — producing state
        // nothing renders, inside the window the launch screen waits on. The compact
        // view seeds it from its own task when you switch to it.
        if layout == .compact {
            await loadWall(reset: true)
        }
    }

    /// The compact layout's poster wall. Movies first, falling back to whatever
    /// the library holds when there are none.
}

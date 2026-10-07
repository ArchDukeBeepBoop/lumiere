import Foundation
import Observation
import LumiereKit

/// Loads a detail page.
///
/// Two-stage on purpose: the cached row renders the header immediately so
/// opening an item never shows a spinner, then the full payload fills in cast,
/// streams and chapters when it arrives.
@MainActor
@Observable
final class DetailModel {

    let itemId: String
    // Not private: DetailModel+Collections.swift calls through it too.
    let repository: LibraryRepository

    /// Settable across the module: the watch-state methods live in
    /// DetailModel+WatchState.swift to keep this file under the line limit, and
    /// Swift's `private(set)` is file-scoped, so splitting the type opens the
    /// setter by exactly one level. `internal(set)` says so redundantly, so the
    /// plain declaration carries the note instead.
    var entry: LibraryEntry?
    private(set) var detail: JellyfinItem?
    var seasons: [LibraryEntry] = []
    private(set) var extras: [LibraryEntry] = []
    var episodes: [LibraryEntry] = []
    /// Whether `loadEpisodes` has finished for the season now selected.
    ///
    /// An empty strip means two different things and the page could not tell them
    /// apart: still fetching, or a season the server holds no episodes for. It
    /// showed "Loading episodes…" for both, so an empty season — and this library
    /// has 320 of them — sat on that line forever.
    var didLoadEpisodes = false
    /// season id → episode count, for the season shelf's caption.
    ///
    /// Every season row in a real cache has a NULL `childCount` — Jellyfin only
    /// sends it for a field the sync does not request — so the count comes from the
    /// episodes actually cached. See `LibraryRepository.episodeCounts`.
    var seasonEpisodeCounts: [String: Int] = [:]
    /// Episode-image backfill state. Stored here because an extension cannot
    /// hold stored properties; the work is in DetailModel+EpisodeImages.swift.
    var isFetchingEpisodeImages = false
    var episodeImageStatus: String?
    private(set) var similar: [LibraryEntry] = []
    /// The franchise this title is part of, where it is part of one. See
    /// `LibraryRepository.franchise(for:)`. Settable across the module for the
    /// same reason `entry` is — the loader lives in DetailModel+Collections.swift.
    var franchise: LibraryRepository.Franchise?
    private(set) var isLoadingDetail = true
    private(set) var loadError: String?

    /// Which file to play when a title has several — a 4K and a 1080p version of
    /// the same film are two media sources on one item.
    var selectedSourceId: String?
    var selectedSeasonId: String?

    /// The episode a series page is currently showing as its hero — title,
    /// synopsis, rating, actions. Distinct from `selectedSeasonId`: choosing a
    /// season picks a list of episodes, this picks which one is "on screen".
    /// Open for the same reason as `entry` — see the note above it.
    var heroEpisodeId: String?
    /// The hero episode's full payload — mediaSources for the footer's technical
    /// specs, mainly. Fetched lazily per episode rather than for the whole season,
    /// since it is only ever needed for whichever one is currently on screen.
    private(set) var heroDetail: JellyfinItem?

    var heroEntry: LibraryEntry? {
        episodes.first { $0.id == heroEpisodeId } ?? episodes.first
    }

    // Collection state. Loaded and mutated entirely from DetailModel+Collections.swift
    // — not private(set), since Swift's file-scoped privacy would otherwise block
    // that extension from writing them. See that file for why a collection needs
    // its own load path rather than folding into `load()` above it.
    var collectionItems: [LibraryEntry] = []
    var collectionShelves: [CollectionShelf] = []
    var shelfLabelOverrides: [String: String] = [:]
    /// Where each member sits in the personal order, keyed by item.
    var collectionRanks: [String: Int] = [:]
    /// The last thing that failed while editing this collection.
    var collectionError: String?
    /// How this collection's contents are ordered.
    ///
    /// Remembered per collection, unlike the sort on a library grid. Arranging a
    /// personal watch order and then finding the page back in release order the
    /// next time you open it would make the arranging pointless — the order *is*
    /// the work, so which order you are in has to survive.
    private var _collectionSort: CollectionOrder = .manual
    var collectionSort: CollectionOrder {
        get { _collectionSort }
        set {
            _collectionSort = newValue
            UserDefaults.standard.set(collectionSort.rawValue, forKey: Self.sortKey(itemId))
            recomputeShelvesPublicly()
            // Switching to a personal order with nothing arranged yet takes the
            // arrangement you were just looking at as its starting point. The
            // alternative is the row rearranging itself the moment you ask to
            // arrange it by hand, which is the opposite of the request.
            if collectionSort == .personal, collectionRanks.isEmpty {
                Task { await seedPersonalOrder() }
            }
        }
    }

    static func sortKey(_ collectionId: String) -> String { "collectionSort.\(collectionId)" }

    /// Assigns the remembered sort without the observer firing.
    ///
    /// Going through `collectionSort` on load would re-save what was just read and,
    /// worse, seed a personal order out of a list that has not been arranged yet —
    /// the observer cannot tell "you chose this" from "this is what you chose last
    /// time".
    var storedSort: CollectionOrder {
        get { collectionSort }
        set {
            _collectionSort = newValue
            recomputeShelvesPublicly()
        }
    }
    var libraryNames: [String: String] = [:]

    /// The episode this page was opened *for*, when it was reached by clicking an
    /// episode card on a shelf. Overrides the server's own next-up answer, since the
    /// user has already said which one they meant.
    private let focusEpisodeId: String?

    init(itemId: String, repository: LibraryRepository, focusEpisodeId: String? = nil) {
        self.itemId = itemId
        self.repository = repository
        self.focusEpisodeId = focusEpisodeId
    }

    var item: ItemRecord? { entry?.item }

    var selectedSource: MediaSource? {
        guard let sources = detail?.mediaSources, !sources.isEmpty else { return nil }
        if let selectedSourceId, let match = sources.first(where: { $0.id == selectedSourceId }) {
            return match
        }
        return sources.first
    }

    var hasMultipleVersions: Bool {
        (detail?.mediaSources?.count ?? 0) > 1
    }

    var isSeries: Bool {
        entry?.item.itemType == .series
    }

    func load() async {
        entry = try? await repository.entry(id: itemId)

        isLoadingDetail = true
        loadError = nil
        defer { isLoadingDetail = false }

        do {
            let full = try await repository.detail(id: itemId)
            detail = full
            // Built from the detail payload when the cache has never seen this id.
            //
            // The page was gated on a *cached* row, so opening a server search hit
            // for an unsynced series left a spinner that never resolved: the id is
            // real, the server answers for it, and nothing on screen ever said why
            // it would not open.
            if entry == nil {
                entry = await repository.transientEntry(from: full)
            }
            // Kept if it still exists. `load()` is not only the first load — ten
            // call sites re-run it when a sheet closes, a favourite is toggled or
            // metadata is refreshed — and reassigning here threw away the version
            // someone had deliberately picked on a title with several files, every
            // time, without anything on screen appearing to have changed.
            let sources = full.mediaSources ?? []
            if selectedSourceId == nil
                || !sources.contains(where: { $0.id == selectedSourceId }) {
                selectedSourceId = sources.first?.id
            }

            if entry?.item.itemType == .series {
                await loadSeasons()
                // Only when there is no valid choice to keep, for the same reason:
                // browsing the strip to episode nine and having a background reload
                // throw you back to Next Up is the strip failing at its one job.
                if heroEpisodeId == nil
                    || !episodes.contains(where: { $0.id == heroEpisodeId }) {
                    await selectInitialHeroEpisode()
                }
            }
            if entry?.item.itemType == .boxSet {
                await loadCollectionItems()
            }
        } catch {
            loadError = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
        }

        // Neither extras nor similar titles are load-bearing: their absence must
        // never read as an error on a page that otherwise loaded.
        if entry?.item.itemType != .boxSet {
            extras = (try? await repository.extras(itemId: itemId)) ?? []
            similar = (try? await repository.similarEntries(to: itemId)) ?? []
            // After Similar, because a franchise is the stronger relationship
            // and the strip is drawn above that shelf: loading it second keeps
            // the cheaper query off the critical path without reordering the
            // page.
            await loadFranchise()
        }
    }

    // MARK: - Hero episode

    /// Picks which episode a freshly opened series page leads with.
    ///
    /// Asks the server which episode is actually next for this series — the same
    /// signal Continue Watching uses — rather than defaulting to season one, episode
    /// one every time. Bounded to 4s with a graceful fallback: an unreachable server
    /// must not hold the whole page hostage over one non-essential lookup, and
    /// "start of season one" is a perfectly reasonable answer for a show nobody has
    /// begun.
    private func selectInitialHeroEpisode() async {
        // An episode named by the caller wins outright: they clicked that card, so
        // asking the server which episode is "next" would be second-guessing them —
        // and for Continue Watching the two genuinely differ, since a part-watched
        // episode is not the next unwatched one.
        if let focusEpisodeId {
            if let entry = try? await repository.entry(id: focusEpisodeId),
               let seasonId = entry.item.seasonId, seasonId != selectedSeasonId {
                selectedSeasonId = seasonId
                await loadEpisodes()
            }
            if episodes.contains(where: { $0.id == focusEpisodeId }) {
                selectEpisode(focusEpisodeId)
                return
            }
        }

        // An episode part-way through comes first — it is where you stopped,
        // and Next Up passes over it because it is not unwatched in the sense
        // Next Up means. Read from the cache, so it costs nothing.
        let started = (try? await repository.resumeEntries(limit: 50))?
            .first { $0.item.seriesId == itemId }
        var next = started
        if next == nil {
            next = await Timeout.run(seconds: 4) { [repository, itemId] in
                (try? await repository.nextUpEntries(seriesId: itemId, limit: 1))?.first
            }
        }

        if let next, let seasonId = next.item.seasonId, seasonId != selectedSeasonId {
            selectedSeasonId = seasonId
            await loadEpisodes()
        }

        if let next, episodes.contains(where: { $0.id == next.id }) {
            selectEpisode(next.id)
        } else {
            selectEpisode(
                episodes.first { !$0.isPlayed }?.id ?? episodes.first?.id
            )
        }
    }

    /// Changes which episode the hero shows, without navigating — the point of the
    /// strip below it is browsing in place.
    func selectEpisode(_ id: String?) {
        guard id != heroEpisodeId else { return }
        heroEpisodeId = id
        heroDetail = nil
        guard let id else { return }
        Task { [repository] in
            let detail = try? await repository.detail(id: id)
            guard id == self.heroEpisodeId else { return }
            self.heroDetail = detail
        }
    }

    // MARK: - Derived text

    var runtimeText: String? {
        guard let seconds = detail?.runtimeSeconds ?? item?.runtimeSeconds else { return nil }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    var directors: [String] {
        people(type: "Director")
    }

    var writers: [String] {
        people(type: "Writer")
    }

    /// The credits row is `credits`, in DetailModel+Credits.swift: it has an order
    /// to it now, and the reasoning behind that order did not fit here.

}

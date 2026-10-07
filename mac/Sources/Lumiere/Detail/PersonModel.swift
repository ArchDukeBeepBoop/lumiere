import Foundation
import Observation
import LumiereKit

/// One show's worth of a person's episode appearances.
///
/// Keyed on the series id where the server gives one and on the series *name*
/// where it does not — a loose episode file with no parent series still has a
/// name, and two of them under the same show should not become two groups.
struct PersonEpisodeGroup: Identifiable, Hashable {
    let id: String
    let title: String
    /// Where the group's heading should go. Nil for the name-keyed fallback above,
    /// which has no series page to open.
    let seriesId: String?
    var entries: [LibraryEntry]
}

/// Loads everything in the library one person is credited on.
///
/// Two independent listings rather than one, because they are two different
/// questions with two different answers on screen: the titles they are *in*
/// (posters, newest first) and the individual episodes they turn up in (a strip
/// per show). Running them as separate queries also means a guest star with 200
/// episode credits cannot push their four films off the end of a shared page.
@MainActor
@Observable
final class PersonModel {

    let personId: String
    private let repository: LibraryRepository

    private(set) var titles: [LibraryEntry] = []
    private(set) var titleTotal = 0
    private(set) var episodeGroups: [PersonEpisodeGroup] = []
    private(set) var episodeTotal = 0
    /// How many episodes have actually arrived. Kept alongside the groups rather
    /// than summed from them, so "is there more" stays an O(1) question asked on
    /// every scroll.
    private(set) var loadedEpisodeCount = 0
    private(set) var isLoading = true
    private(set) var loadError: String?

    private var titleOffset = 0
    private var episodeOffset = 0
    private var isLoadingTitles = false
    private var isLoadingEpisodes = false
    private var hasLoaded = false

    /// The same window the genre wall uses. A prolific actor is most of a library.
    private let pageSize = 60

    init(personId: String, repository: LibraryRepository) {
        self.personId = personId
        self.repository = repository
    }

    var isEmpty: Bool { titles.isEmpty && episodeGroups.isEmpty }
    var hasMoreTitles: Bool { titles.count < titleTotal }
    var hasMoreEpisodes: Bool { loadedEpisodeCount < episodeTotal }
    var isLoadingMoreEpisodes: Bool { isLoadingEpisodes }

    /// A one-line summary of what the page is about to show.
    var summary: String? {
        var parts: [String] = []
        if titleTotal > 0 {
            parts.append(titleTotal == 1 ? "1 title" : "\(titleTotal) titles")
        }
        if episodeTotal > 0 {
            parts.append(episodeTotal == 1 ? "1 episode" : "\(episodeTotal) episodes")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Guarded, like the genre wall's: `.task` runs again whenever the view is
    /// rebuilt, and a second pass would append the first page on top of itself.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        await loadMoreTitles()
        await loadMoreEpisodes()
    }

    func loadMoreTitles() async {
        guard !isLoadingTitles, titleOffset == 0 || hasMoreTitles else { return }
        isLoadingTitles = true
        defer { isLoadingTitles = false }
        do {
            let page = try await repository.personTitlesPage(
                personId: personId, offset: titleOffset, limit: pageSize
            )
            titleTotal = max(page.total, titles.count + page.entries.count)
            titles.append(contentsOf: page.entries)
            titleOffset += page.entries.count
            // A server that claims more than it will hand over would otherwise
            // leave the wall asking for the same window forever. An empty page is
            // the end of the listing whatever the count said.
            if page.entries.isEmpty { titleTotal = titles.count }
        } catch {
            loadError = error.localizedDescription
            // Stops the retry loop: without this the failed window is still
            // "missing", so the next cell to appear asks for it again.
            titleTotal = titles.count
        }
    }

    func loadMoreEpisodes() async {
        guard !isLoadingEpisodes, episodeOffset == 0 || hasMoreEpisodes else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            let page = try await repository.personEpisodesPage(
                personId: personId, offset: episodeOffset, limit: pageSize
            )
            episodeTotal = max(page.total, loadedEpisodeCount + page.entries.count)
            append(episodes: page.entries)
            episodeOffset += page.entries.count
            if page.entries.isEmpty { episodeTotal = loadedEpisodeCount }
        } catch {
            loadError = error.localizedDescription
            episodeTotal = loadedEpisodeCount
        }
    }

    /// Folds a window of episodes into the groups already on screen.
    ///
    /// The server is asked to sort by series first, so in practice every episode
    /// extends the group at the end of the list and this is a walk. The
    /// `firstIndex` branch is the honest fallback for a server that ignores or
    /// reorders that sort: it costs a scan of the groups — tens, not thousands —
    /// and it is the difference between one strip per show and the same show
    /// appearing three times down the page.
    private func append(episodes entries: [LibraryEntry]) {
        for entry in entries {
            let key = entry.item.seriesId ?? entry.item.seriesName ?? entry.id
            if let last = episodeGroups.indices.last, episodeGroups[last].id == key {
                episodeGroups[last].entries.append(entry)
            } else if let index = episodeGroups.firstIndex(where: { $0.id == key }) {
                episodeGroups[index].entries.append(entry)
            } else {
                episodeGroups.append(PersonEpisodeGroup(
                    id: key,
                    title: entry.item.seriesName ?? entry.item.name,
                    seriesId: entry.item.seriesId,
                    entries: [entry]
                ))
            }
            loadedEpisodeCount += 1
        }
    }

    /// Re-reads one row in place after a right-click command writes to the server.
    ///
    /// A person's page is two different shapes over the same rows — a grid of titles
    /// and strips of episodes grouped by series — and an item can only be in one of
    /// them, so both are checked and the first match wins.
    func refreshRow(id: String) async {
        guard let fresh = (try? await repository.entriesById([id]))?.first else { return }
        if let index = titles.firstIndex(where: { $0.id == id }) {
            titles[index] = fresh
            return
        }
        for group in episodeGroups.indices {
            if let index = episodeGroups[group].entries.firstIndex(where: { $0.id == id }) {
                episodeGroups[group].entries[index] = fresh
                return
            }
        }
    }
}

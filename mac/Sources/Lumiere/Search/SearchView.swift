import SwiftUI
import LumiereKit

/// Search.
///
/// Two passes, and the order matters. The local cache holds every title, so
/// results appear as you type with no round trip. A server query follows a beat
/// later for what the cache cannot answer — cast, overview text — and merges in
/// behind the local ones rather than replacing them, so the list never jumps
/// under the pointer.
struct SearchView: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    /// For the actions a result carries. Optional so a preview can leave it out.
    var app: AppModel?

    /// The collection a deletion has been asked for, held while it is confirmed.
    /// Not private: the menu that sets it lives in SearchView+Actions.swift, and
    /// Swift's `private` is file-scoped.
    @State var deleteCollectionTarget: LibraryEntry?
    @State private var query = ""
    @State private var localResults: [LibraryEntry] = []
    @State private var serverResults: [LibraryEntry] = []
    @State private var isSearchingServer = false
    @State private var searchTask: Task<Void, Never>?
    /// The shared menu's state. See `EntryActionState`.
    @State var entryState = EntryActionState()
    @FocusState private var isFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: Theme.Space.lg, alignment: .top)
    ]

    /// Local first, then anything the server found that the cache did not.
    private var results: [LibraryEntry] {
        var seen = Set(localResults.map(\.id))
        var combined = localResults
        for entry in serverResults where !seen.contains(entry.id) {
            seen.insert(entry.id)
            combined.append(entry)
        }
        return combined
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if query.isEmpty {
                RecentSearchesList { query = $0 }
                prompt
            } else if results.isEmpty {
                noResults
            } else {
                resultsGrid
            }
        }
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        .onAppear { isFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textMuted)
            TextField("Search your library", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($isFocused)
                .onChange(of: query) { search() }

            if isSearchingServer {
                ProgressView().controlSize(.small)
            }
            if !query.isEmpty {
                Button {
                    query = ""
                    localResults = []
                    serverResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(Theme.Space.xxl)
    }

    private var resultsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SearchNamesRow(term: query, repository: repository)
                Text(countLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .padding(.horizontal, Theme.Space.xxl)

                // Grouped, as Apple TV's search groups them: shows, films,
                // collections, episodes — each a row of large artwork rather
                // than one wall where a film and an episode look alike.
                ForEach(groups, id: \.title) { group in
                    Shelf(title: group.title, itemCount: group.entries.count,
                          itemWidth: group.wide ? Theme.Art.continueCardWidth * 0.7 : Theme.Art.shelfPosterWidth) {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: DetailRoute.forEntry(entry)) {
                                if group.wide {
                                    WideCard(entry: entry, serverURL: serverURL, pipeline: pipeline,
                                             width: Theme.Art.continueCardWidth * 0.7,
                                             metadata: actions(for: entry))
                                } else {
                                    PosterCard(entry: entry, serverURL: serverURL, pipeline: pipeline,
                                               width: Theme.Art.shelfPosterWidth,
                                               metadata: actions(for: entry))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        // Five sheets in one modifier, shared with every other surface that
        // shows tiles. See `EntryActions+Sheets`.
        .entryActions(entryState, in: entryContext)
        .collectionDeleteConfirm(
            target: $deleteCollectionTarget, repository: repository, app: app
        ) {
            search()
        }
    }

    /// Results by kind, in the order they are most often wanted.
    private var groups: [(title: String, entries: [LibraryEntry], wide: Bool)] {
        let kinds: [(String, Set<JellyfinItem.ItemType>, Bool)] = [
            ("Shows", [.series], false), ("Films", [.movie], false),
            ("Collections", [.boxSet], false), ("Episodes", [.episode], true),
        ]
        var used = Set<String>()
        var out: [(title: String, entries: [LibraryEntry], wide: Bool)] = []
        for (title, types, wide) in kinds {
            let found = results.filter { types.contains($0.item.itemType) }
            used.formUnion(found.map(\.id))
            if !found.isEmpty { out.append((title, found, wide)) }
        }
        let rest = results.filter { !used.contains($0.id) }
        if !rest.isEmpty { out.append(("More", rest, false)) }
        return out
    }

    private var countLabel: String {
        let total = results.count
        let extra = results.count - localResults.count
        if extra > 0 {
            return "\(total) result\(total == 1 ? "" : "s") · \(extra) from the server"
        }
        return "\(total) result\(total == 1 ? "" : "s")"
    }

    private var prompt: some View {
        emptyState(
            icon: "magnifyingglass",
            title: "Search your library",
            message: "Films, shows and episodes. Titles come from the local cache "
                   + "instantly; cast and synopsis are matched by the server."
        )
    }

    private var noResults: some View {
        emptyState(
            icon: "questionmark.circle",
            title: "No matches for \"\(query)\"",
            message: isSearchingServer
                ? "Still checking the server…"
                : "Check the spelling, or try part of the title."
        )
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        EmptyStateView(reason: .empty(icon: icon, title: title, detail: message))
    }

    /// Debounced with cancellation: typing "interstellar" runs one server query,
    /// not eleven, and an in-flight one cannot land after a newer keystroke and
    /// overwrite fresher results.
    func search() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)

        guard !term.isEmpty else {
            localResults = []
            serverResults = []
            isSearchingServer = false
            return
        }

        searchTask = Task {
            // The local pass is immediate — it is a SQL LIKE over a cache that is
            // already in memory, and waiting on a debounce for it would make
            // typing feel laggy for no reason.
            let local = (try? await repository.entries(
                // Collections and music included. The menu below has always had a
                // guard for a BoxSet result, which could never fire because the
                // query excluded them — so a collection was unfindable by name, and
                // the only way to a collection page was scrolling the grid it sits in.
                types: [.movie, .series, .episode, .boxSet, .musicAlbum, .audio],
                sort: .title,
                // Fetched wider than shown, then ranked. The old 120 was both
                // the fetch and the answer, so on a large library the exact
                // title could sit outside the window and never be seen.
                limit: 400,
                searchTerm: term
            )) ?? []
            guard !Task.isCancelled else { return }
            localResults = Self.ranked(local, term: term)
            serverResults = []

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            isSearchingServer = true
            defer { isSearchingServer = false }

            // Bounded, like every other server call: an unreachable server must
            // not leave a spinner running behind perfectly good local results.
            let remote = await Timeout.run(seconds: 6) { [repository] in
                (try? await repository.searchServer(term: term)) ?? []
            } ?? []
            guard !Task.isCancelled else { return }
            serverResults = remote
        }
    }
}

/// The actions a search result carries.
///
/// Split into its own extension because a search hit is the same object as a grid
/// tile and deserves the same menu: finding something and then being unable to
/// favourite it, add it to a playlist, or fix its title is exactly the moment the
/// result stops being useful.
extension SearchView {

    /// Best match first. See `SearchRanking`.
    ///
    /// Sorted here rather than in SQL because relevance is not something the
    /// LIKE that found these rows can express, and 400 rows is nothing to sort.
    static func ranked(_ entries: [LibraryEntry], term: String) -> [LibraryEntry] {
        var scored: [(entry: LibraryEntry, score: Int)] = []
        scored.reserveCapacity(entries.count)
        for entry in entries {
            // A collection is scored by its name without "Collection", so
            // "alien" finds Alien Collection first — then its films below it.
            let isCollection = entry.item.itemType == .boxSet
            let score = SearchRanking.score(
                name: isCollection ? SearchRanking.bareCollectionName(entry.item.name) : entry.item.name,
                term: term,
                kindWeight: isCollection ? 4 : kindWeight(entry.item.itemType)
            )
            scored.append((entry, score))
        }
        scored.sort { left, right in
            if left.score != right.score { return left.score > right.score }
            // Title order within a tie, so a repeated search does not reshuffle
            // results that scored the same.
            let order = left.entry.item.name
                .localizedStandardCompare(right.entry.item.name)
            return order == .orderedAscending
        }
        return scored.prefix(120).map(\.entry)
    }

    /// A series or a film is what someone is usually looking for; an episode or
    /// a track is what they get twelve of. Only ever a tie-break — an episode
    /// searched for by its own exact name still outranks a series that merely
    /// contains the word.
    static func kindWeight(_ type: JellyfinItem.ItemType?) -> Int {
        switch type {
        case .series, .movie, .boxSet: return 3
        case .musicAlbum: return 2
        case .episode: return 1
        default: return 0
        }
    }
}

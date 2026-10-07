import Foundation
import GRDB

extension ItemRecord {
    /// No foreign key exists in the schema — watch state is written and deleted
    /// independently of metadata — so the association is declared explicitly.
    static let userDataAssociation = hasOne(
        UserDataRecord.self,
        key: "userData",
        using: ForeignKey(["itemId"], to: ["id"])
    )
}

/// Reads the cache and reconciles it with the server.
///
/// Every view reads through here and never touches `JellyfinClient` for browsing.
/// That is what makes scrolling instant and keeps a 5,000-item library from ever
/// being resident in memory: queries are windowed, so a grid holds ~60 rows.
public actor LibraryRepository {

    // Internal rather than private so the detail extension in
    // LibraryRepository+Detail.swift can reach them.
    let database: LibraryDatabase
    let client: JellyfinClient
    let serverId: String

    /// Libraries kept out of every read that nobody explicitly asked for — the
    /// home screen, Continue Watching, search, the spotlight.
    ///
    /// Held here rather than filtered by each caller, because privacy that has to
    /// be remembered at thirty call sites is privacy that leaks at the thirty-first.
    /// LibraryRepository+Privacy.swift has the rest of the reasoning, including
    /// what this deliberately is not.
    // Not `private(set)`: the setter lives in LibraryRepository+Privacy.swift, and
    // Swift scopes that access level to this file.
    public var privateLibraryIds: Set<String> = []
    /// Non-empty while in the private room: then *only* these libraries show.
    /// See LibraryRepository+Privacy.swift.
    public var roomLibraryIds: Set<String> = []
    /// The database's own announcement of watch-state changes. See
    /// `announceWatchStateChanges`.
    var watchStateAnnouncer: Task<Void, Never>?

    public init(database: LibraryDatabase, client: JellyfinClient) {
        self.database = database
        self.client = client
        self.serverId = client.session.serverId
    }

    /// What belongs in a library grid: one row per title.
    ///
    /// Excludes episodes, seasons and folders. A TV library recursively holds tens
    /// of thousands of episodes — 24,200 in the Anime library alone — so without
    /// this a grid is a wall of individual episodes with the series buried among
    /// them, and the folder rows the server also returns show up as blank cards
    /// with no artwork. Defined once here because the grid, its item count and the
    /// home shelves must all agree; a header reading "24,200 items" over a grid of
    /// series would be worse than no count.
    public static let topLevelTypes: [JellyfinItem.ItemType] = [.movie, .series, .boxSet]

    // MARK: - Resilience

    /// Runs `work`, retrying transient failures with a widening delay.
    ///
    /// Cancellation is never retried — that is the user closing something, not a
    /// flaky network — and the last failure is rethrown so a genuinely dead server
    /// still surfaces instead of looping forever.
    /// The attempt number is handed to the work so a retry can ask a *different*
    /// question. Four identical requests to a server that could not answer the first
    /// is four ways of failing the same way — see the page fetch in
    /// LibraryRepository+Sync.swift, which halves its page each time.
    static func retrying<T: Sendable>(
        attempts: Int,
        _ work: @Sendable (Int) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await work(attempt)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                Diagnostics.log("[sync] attempt \(attempt)/\(attempts) failed: \(error)")
                guard attempt < attempts else { break }
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        throw lastError ?? CancellationError()
    }

    // MARK: - Queries

    /// Which servers' rows this session may see: the one signed in, and the
    /// machine itself.
    ///
    /// Folders added from this Mac are cached as ordinary rows under a synthetic
    /// server — see `LocalLibrary` — so every read has to admit both, and every
    /// *write* that belongs to Jellyfin still names `serverId` alone. That is the
    /// single condition the whole local-files feature rests on: the sync deletes
    /// and replaces by `serverId`, so it cannot touch a local row.
    nonisolated var visibleServerIds: [String] { [serverId, LocalLibrary.serverId] }

    public func libraries() async throws -> [LibraryRecord] {
        try await database.writer.read { [visibleServerIds] db in
            try LibraryRecord
                .filter(visibleServerIds.contains(Column("serverId")))
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    /// A window of a library, joined with watch state.
    ///
    /// `limit` and `offset` are mandatory rather than optional on purpose — there
    /// is no API here for "give me everything", because that is the call that
    /// would blow the memory budget.
    public func entries(
        parentId: String? = nil,
        types: [JellyfinItem.ItemType] = [],
        sort: Sort = .title,
        descending: Bool? = nil,
        libraryId: String? = nil,
        /// Restricts to a set of libraries without turning the privacy filter off.
        ///
        /// Deliberately not `libraryId`, which means "you opened this library" and
        /// suppresses privacy for exactly that reason — naming a library is a
        /// deliberate visit, and a private one that could not be opened would be a
        /// deleted one with extra steps. This is the opposite case: a shelf that
        /// gathers from several libraries at once and must still not surface a
        /// private one. Empty means every library.
        libraryIds: [String] = [],
        limit: Int,
        offset: Int = 0,
        searchTerm: String? = nil,
        genre: String? = nil,
        studio: String? = nil,
        unwatchedOnly: Bool = false,
        /// Excludes anything released on or after this date, and keeps anything with
        /// no release date at all.
        ///
        /// For the rating sort, where it is the difference between a Top 10 and a
        /// list of last spring's releases: a community rating settles over months,
        /// so a title three weeks old sits at whatever its first few hundred voters
        /// thought. Jellyfin's payload carries no vote count — checked, it is the
        /// only rating-shaped field there is — so age is the one proxy for
        /// confidence the local data actually has.
        releasedBefore: Date? = nil,
        projection: Projection = .full
    ) async throws -> [LibraryEntry] {
        let isDescending = descending ?? sort.defaultDescending

        // Applied only when no particular library was named. Naming one is a
        // deliberate visit, and a private library that could not be opened would
        // be a deleted library with extra steps.
        let privacy = (parentId == nil && libraryId == nil) ? privacyFilter() : nil

        return try await database.writer.read { [visibleServerIds] db in
            var request = ItemRecord
                .filter(visibleServerIds.contains(Column("serverId")))
                // Bonus material never belongs in a title grid — it is content
                // *about* a film, listed beside the films themselves. Reachable by
                // browsing into the folder it lives in, which is where someone
                // looking for it would go.
                .filter(Column("extraType") == nil)
                // Hidden collections, filtered here so every surface inherits it
                // from one place — grids, shelves, search and counts alike. The
                // server keeps re-creating TMDB's film collections on each scan, so
                // this is the only thing that makes one stay gone.
                .filter(sql: HiddenCollections.filterSQL)
                .including(optional: ItemRecord.userDataAssociation)

            // Narrowed for surfaces that hold thousands of rows at once. See
            // `Projection`.
            if case .tile = projection {
                request = request.select(Projection.tileColumns.map { Column($0) })
            }

            if let parentId {
                request = request.filter(Column("parentId") == parentId)
            }
            if let libraryId {
                request = request.filter(Column("libraryId") == libraryId)
            }
            if !libraryIds.isEmpty {
                request = request.filter(libraryIds.contains(Column("libraryId")))
            }
            if let privacy { request = request.filter(sql: privacy) }
            if let releasedBefore {
                request = request.filter(
                    Column("premiereDate") == nil || Column("premiereDate") < releasedBefore
                )
            }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            if let searchTerm, !searchTerm.isEmpty {
                // Every word must appear, in any order and anywhere in the key.
                //
                // The old query was one contiguous `LIKE` on `name`, which failed
                // three ways at once: "fate zero" could not match Fate/Zero because
                // the slash is not a space, "academy sky" could not match Sky
                // Wizards Academy because a substring has to be in order, and an
                // episode could not be found by its show. All three are the same
                // fix — match tokens against a normalised key.
                //
                // AND rather than OR: any two-word query under OR returns most of
                // the library, which is a different kind of unhelpful.
                for token in SearchKey.tokens(in: searchTerm) {
                    request = request.filter(Column("searchKey").like("%\(token)%"))
                }
            }
            if let genre {
                // Whole-genre, not substring — see `LibraryRepository.genreMatchSQL`.
                request = request.filter(
                    sql: Self.genreMatchSQL, arguments: [Self.genrePattern(genre)]
                )
            }
            if let studio {
                request = request.filter(
                    sql: Self.studioMatchSQL, arguments: [Self.studioPattern(studio)]
                )
            }

            request = Self.order(request, by: sort, descending: isDescending)

            if unwatchedOnly {
                // Filtered in SQL, before LIMIT — not in Swift afterwards.
                //
                // Filtering the page after it came back meant a window of 60 rows
                // could yield 12 entries, and the grid advanced its offset by 12.
                // The next window started at 12 and re-emitted everything unwatched
                // between 12 and 59: duplicate tiles, duplicate ids inside a
                // ForEach, and a grid that never reconciled with the header count —
                // which was right, because `count(_:)` below always did this in SQL.
                //
                // Same predicate as the count, deliberately: two spellings of one
                // filter is how they drift apart.
                request = request.filter(
                    sql: "NOT EXISTS (SELECT 1 FROM userData "
                       + "WHERE userData.itemId = item.id AND userData.played = 1)"
                )
            }

            return try LibraryEntry.fetchAll(db, request.limit(limit, offset: offset))
        }
    }
}

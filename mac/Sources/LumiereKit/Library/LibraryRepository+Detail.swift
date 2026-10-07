import Foundation
import GRDB

extension LibraryRepository {

    /// How long a cached detail payload is trusted before refetching. Metadata
    /// barely changes; watch state comes from the separate `userData` table and
    /// is refreshed independently, so a day is safe.
    static let detailFreshness: TimeInterval = 86_400
    /// How long a payload with no cast is trusted. A title opened the minute
    /// it arrived is cached before the server's naming pass has credited it,
    /// and a day of an empty Cast & Crew row is a day of looking broken. See
    /// `DetailFreshness`.
    static let uncreditedFreshness: TimeInterval = 15 * 60

    /// The full item — media sources, streams, cast, chapters.
    ///
    /// Cache first, server second, cache-again-on-failure last. That last step is
    /// the point: a detail page you have opened before still works with the
    /// server asleep, showing what it knew rather than an error.
    public func detail(id: String, forceRefresh: Bool = false) async throws -> JellyfinItem {
        if !forceRefresh, let (cached, fetchedAt) = try await cachedDetailRow(id: id, maxAge: Self.detailFreshness),
           !DetailFreshness.isStaleWithoutCredits(cached, fetchedAt: fetchedAt, now: Date()) {
            return cached
        }

        do {
            let item = try await client.item(id: id)
            try await storeDetail(item)
            return item
        } catch {
            // Any age will do now — stale beats nothing.
            if let stale = try await cachedDetail(id: id, maxAge: .infinity) {
                return stale
            }
            throw error
        }
    }

    /// Whether a detail page can be opened without the network.
    public func hasCachedDetail(id: String) async -> Bool {
        (try? await cachedDetail(id: id, maxAge: .infinity)) != nil
    }

    func cachedDetail(id: String, maxAge: TimeInterval) async throws -> JellyfinItem? {
        try await cachedDetailRow(id: id, maxAge: maxAge)?.0
    }

    /// The payload and when it was fetched.
    func cachedDetailRow(id: String, maxAge: TimeInterval) async throws -> (JellyfinItem, Date)? {
        // Annotated because GRDB's `read` has overloads that otherwise infer Void
        // here, silently discarding the row.
        let row: Row? = try database.writer.read { db -> Row? in
            try Row.fetchOne(
                db,
                sql: "SELECT json, fetchedAt FROM itemDetail WHERE itemId = ?",
                arguments: [id]
            )
        }
        guard let row,
              let json: String = row["json"],
              let fetchedAt: Date = row["fetchedAt"] else { return nil }

        guard maxAge.isInfinite || Date().timeIntervalSince(fetchedAt) < maxAge else { return nil }
        guard let item = try? JellyfinClient.decoder.decode(JellyfinItem.self, from: Data(json.utf8))
        else { return nil }
        return (item, fetchedAt)
    }

    func storeDetail(_ item: JellyfinItem) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let json = String(data: try encoder.encode(item), encoding: .utf8) else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO itemDetail (itemId, json, fetchedAt) VALUES (?, ?, ?) "
                   + "ON CONFLICT(itemId) DO UPDATE SET json = excluded.json, fetchedAt = excluded.fetchedAt",
                arguments: [item.id, json, Date()]
            )
        }
    }

    /// Writes a detail payload directly. Used by `DemoFixtures` so the demo
    /// library carries real technical metadata through the same path the server
    /// would use.
    public func seedDetail(_ item: JellyfinItem) async throws {
        try await storeDetail(item)
    }

    /// "More like this". Server-derived, cached on the way through so a revisit
    /// works offline.
    public func similarEntries(to itemId: String, limit: Int = 12) async throws -> [LibraryEntry] {
        // Over-fetched, because the filter below throws some away. Jellyfin's
        // `/Similar` takes no library, so scoping has to happen here.
        let fetched = try await client.similar(to: itemId, limit: limit * 4)
        try await cache(items: fetched)

        // One query, not one per item. `entriesById` already preserves the
        // server's order, which is the only reason the loop existed.
        let entries = await visible(try await entriesById(fetched.map(\.id)))
        let scoped = await sameLibrary(as: itemId, entries: entries)
        return Array(scoped.prefix(limit))
    }

    /// Keeps only the titles from the same library as the one being viewed.
    ///
    /// The server's similarity is computed across everything it holds, so a row
    /// labelled "Related" under one title could be filled with things from a
    /// completely different part of the library — most obviously on the libraries
    /// whose contents have nothing to do with the rest of the collection. Related
    /// means "more of this", and "this" is bounded by the shelf it came from.
    ///
    /// Applied everywhere rather than to named libraries: a film's related row has
    /// no business holding an anime episode either. If the source row has no library
    /// — an item the sync has not stamped — nothing is filtered, since there is
    /// nothing to filter against and an empty row would be worse.
    private func sameLibrary(
        as itemId: String, entries: [LibraryEntry]
    ) async -> [LibraryEntry] {
        guard let source = try? await entry(id: itemId),
              let libraryId = source.item.libraryId else { return entries }
        let scoped = entries.filter { $0.item.libraryId == libraryId }
        // A library too small to fill the row keeps what it has rather than
        // borrowing from elsewhere; the row simply gets shorter.
        return scoped
    }

    /// The next unwatched episode of each series in progress, or of one series when
    /// `seriesId` is given — how a series page decides which season and episode to
    /// open to.
    ///
    /// Server-derived by necessity: it depends on watch state across every
    /// device. Cached on the way through so a second visit is instant and an
    /// unreachable server degrades to the last known answer.
    public func nextUpEntries(seriesId: String? = nil, limit: Int = 14) async throws -> [LibraryEntry] {
        guard let fetched = try? await client.nextUp(seriesId: seriesId, limit: limit),
              !fetched.isEmpty
        else {
            return []
        }
        try await cache(items: fetched)

        // Server-derived, so no query filtered it. See `visible(_:)`.
        return await visible(try await entriesById(fetched.map(\.id)))
    }

    /// Server-side search, cached on the way through.
    ///
    /// The local cache holds titles, so typing gives instant results from it.
    /// This is for what the cache does not hold — cast, overview text, taglines —
    /// and arrives a moment later to fill in behind them.
    public func searchServer(term: String, limit: Int = 40) async throws -> [LibraryEntry] {
        guard term.count >= 2 else { return [] }

        let response = try await client.items(
            types: [.movie, .series, .episode],
            recursive: true,
            limit: limit,
            searchTerm: term
        )
        try await cache(items: response.items)

        // One query rather than forty. Each `entry(id:)` opened its own reader —
        // a pool checkout and an actor hop apiece — so a remote search cost forty
        // sequential round trips to answer one question.
        // Server-derived, so no query filtered it. See `visible(_:)`.
        return await visible(try await entriesById(response.items.map(\.id)))
    }

    // MARK: - Series structure

    /// Seasons of a series, from the cache. Falls back to the server when the
    /// cache has none, which happens if the sync has not reached this series yet.
    /// Drops seasons holding no episodes.
    ///
    /// A real library is full of them: 297 seasons here are named "Season Unknown"
    /// and 320 hold nothing at all — artefacts of Jellyfin filing loose folders
    /// (`Fonts`, `Artwork book`) as seasons. Each one is a picker entry that opens
    /// onto an empty strip.
    ///
    /// The guard matters more than the filter. If *nothing* under this series is
    /// cached yet — a sync that has reached the seasons but not the episodes — every
    /// season looks empty, and filtering would leave a series with no seasons at all.
    /// So the filter only applies when at least one season has episodes, which is
    /// exactly the case where an empty one is genuinely empty rather than pending.
    // Not private: the seasons and episodes queries live in
    // LibraryRepository+Episodes.swift to keep this file under the line limit.
    func withEpisodes(_ seasons: [LibraryEntry]) async throws -> [LibraryEntry] {
        guard !seasons.isEmpty else { return seasons }
        let ids = seasons.map(\.id)

        let populated: Set<String> = try await database.writer.read { db in
            let rows = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT parentId FROM item
                    WHERE type = 'Episode' AND parentId IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                    """,
                arguments: StatementArguments(ids)
            )
            return Set(rows)
        }

        guard !populated.isEmpty else { return seasons }
        return seasons.filter { populated.contains($0.id) }
    }

    /// Writes freshly fetched items into the cache so a second visit is instant.
    /// Caches items fetched outside the ordinary library sync — extras, similar
    /// titles, a collection's members.
    ///
    /// Preserves `parentId`/`libraryId` from whatever is already cached for each
    /// item. Neither ever comes from the item's own JSON — `libraryId` is stamped
    /// from the *request* during a real sync, and is not present here at all — so
    /// building a fresh `ItemRecord` and saving it were silently wiping both to nil
    /// on every call. That surfaced as collection members grouping under "Other"
    /// no matter which library they actually lived in: opening the collection page
    /// re-cached each member and erased the very column their shelf was grouped by.
    func cache(items: [JellyfinItem]) async throws {
        let now = Date()
        let serverId = self.serverId
        try await database.writer.write { db in
            for item in items {
                let existing = try ItemRecord.fetchOne(db, key: item.id)
                var record = ItemRecord(from: item, serverId: serverId, syncedAt: now)
                // parentId can arrive in this JSON, so a fresh value wins; libraryId
                // never does, so the cached one is the only one that ever exists.
                record.parentId = record.parentId ?? existing?.parentId
                record.libraryId = existing?.libraryId
                // The Latest shelf's ranking, which no server payload carries.
                record.carryContentDate(from: existing)
                try record.save(db)
                if let userData = item.userData {
                    try UserDataRecord(itemId: item.id, from: userData, updatedAt: now).save(db)
                }
            }
        }
    }
}

public extension LibraryRepository {
    /// A series' specials, whether or not the server gave them a season of their own.
    ///
    /// Jellyfin numbers a specials season 0, but not every library has one — specials
    /// dropped loose in a series folder end up as episodes with parentIndexNumber 0
    /// and no season row at all. Querying the flag rather than the season means they
    /// are grouped either way, which is the point of grouping them.
    func specials(seriesId: String) async throws -> [LibraryEntry] {
        try await database.writer.read { db in
            let request = ItemRecord
                .filter(Column("seriesId") == seriesId)
                .filter(Column("type") == "Episode")
                .filter(Column("parentIndexNumber") == 0)
                .including(optional: ItemRecord.userDataAssociation)
                .order(Column("sortName"))
            return try LibraryEntry.fetchAll(db, request)
        }
    }
}

import Foundation

/// Collection suggestions from the movie database's film series.
///
/// The server does the grouping — it holds each title's series id — and says
/// which series already has a collection here, so a suggestion can be "add
/// Predators to Predator Collection" rather than a second Predator collection.
extension LibraryRepository {

    /// Series with at least one title in `library`, as proposals. Existing
    /// collections that are already complete are left out; their missing
    /// films are shown on the collection page instead.
    func seriesSuggestions(within library: Set<String>) async -> [FranchiseGrouping.Group] {
        await client.collectionSuggestions().compactMap { s in
            let add = s.AddIds ?? []
            guard !add.isEmpty, add.contains(where: library.contains) else { return nil }
            let missing = (s.Missing ?? []).map { m in m.Year.map { "\(m.Title) (\($0))" } ?? m.Title }
            let reason: String
            if s.CollectionId != nil {
                reason = "adds \(add.count) to the existing collection — same film series on the movie database"
            } else {
                reason = "same film series on the movie database"
            }
            return FranchiseGrouping.Group(
                name: s.Name, itemIds: add, reason: reason,
                existingCollectionId: s.CollectionId, tmdbCollectionId: s.TmdbId,
                missing: missing, isStrong: true
            )
        }
    }
}

extension LibraryRepository {
    /// The films in a collection's series that this library does not have,
    /// "Alien³ (1992)". Empty where the collection is not a film series, or
    /// the server is not Lumiere's.
    public func missingFilms(collectionId: String) async -> [String] {
        let match = await client.collectionSuggestions().first { $0.CollectionId == collectionId }
        return (match?.Missing ?? []).map { m in m.Year.map { "\(m.Title) (\($0))" } ?? m.Title }
    }
}

/// The server's suggestions, held for a few minutes: every film page asks,
/// and the answer changes only when a collection does.
actor SeriesSuggestionCache {
    static let shared = SeriesSuggestionCache()
    private var held: (at: Date, value: [ServerCollectionSuggestion])?

    func fresh() -> [ServerCollectionSuggestion]? {
        guard let held, Date().timeIntervalSince(held.at) < 300 else { return nil }
        return held.value
    }

    func keep(_ value: [ServerCollectionSuggestion]) { held = (Date(), value) }

    func forget() { held = nil }
}

extension LibraryRepository {
    /// The collection this title could join, from its film series — offered on
    /// its own page, so collections grow as the library is browsed.
    public func seriesSuggestion(for itemId: String) async -> FranchiseGrouping.Group? {
        var all = await SeriesSuggestionCache.shared.fresh()
        if all == nil {
            all = await client.collectionSuggestions()
            await SeriesSuggestionCache.shared.keep(all ?? [])
        }
        guard let all else { return nil }
        guard let s = all.first(where: { ($0.AddIds ?? []).contains(itemId) }) else { return nil }
        return FranchiseGrouping.Group(
            name: s.Name, itemIds: s.AddIds ?? [], reason: "same film series on the movie database",
            existingCollectionId: s.CollectionId, tmdbCollectionId: s.TmdbId, isStrong: true
        )
    }

    /// Accepts one suggestion and drops the cached list, so the page offering
    /// it stops offering it.
    public func acceptSuggestion(_ group: FranchiseGrouping.Group) async throws {
        _ = try await createCollections([group])
        await SeriesSuggestionCache.shared.forget()
    }
}

extension LibraryRepository {
    /// The id of the collection with this name, for undoing one just made.
    public func collectionNamed(_ name: String) async throws -> String? {
        try await allCollections().first { $0.item.name == name }?.id
    }
}

extension LibraryRepository {
    /// The next film in each film series under way, as cached entries.
    public func seriesNextUp() async -> [LibraryEntry] {
        var out: [LibraryEntry] = []
        for item in await client.seriesNextUp() {
            if let entry = try? await entry(id: item.id) { out.append(entry) }
        }
        return out
    }
}

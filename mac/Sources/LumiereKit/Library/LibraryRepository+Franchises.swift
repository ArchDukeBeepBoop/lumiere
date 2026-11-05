import Foundation

/// Proposing collections from what the server already knows about a library.
///
/// The reason this exists at all: on an anime or adult library, collections are
/// the thing that makes it navigable, and building them by hand is hundreds of
/// decisions. Everything automatic that has been tried elsewhere matches on titles,
/// which finds numbered sequels and misses franchises entirely — the two cases are
/// almost disjoint on these libraries.
///
/// Nothing is created without being accepted. The scan reads; the sheet proposes;
/// `createCollections` is the only thing that writes, and it writes to the server so
/// every other Jellyfin client sees the same collections.
public extension LibraryRepository {

    /// Which credits count as relating two titles.
    ///
    /// The original creator is the franchise, for anime especially: every Monogatari
    /// is Nisio Isin, every Fate is Kinoko Nasu. Directors and writers are weaker
    /// but still real. The cast is excluded outright — a voice pool of thirty
    /// actors covers half a library and would relate everything to everything.
    private static let relatingRoles: Set<String> = ["writer", "creator", "producer"]

    /// Reads a library's metadata and returns the groups it suggests.
    ///
    /// One request per page rather than one per title: `Fields=Tags,Studios,People`
    /// on a list query is the difference between a scan that takes a second and one
    /// that makes 1,700 round trips.
    func franchiseSuggestions(
        libraryId: String,
        pageSize: Int = 200,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [FranchiseGrouping.Group] {
        var candidates: [RelationCandidate] = []
        var offset = 0
        var total = Int.max

        while offset < total {
            let response = try await client.items(
                parentId: libraryId,
                types: [.series, .movie],
                recursive: true,
                startIndex: offset,
                limit: pageSize,
                fields: .relations
            )
            total = response.totalRecordCount
            if response.items.isEmpty { break }
            candidates.append(contentsOf: response.items.map(Self.candidate(from:)))
            offset += response.items.count
            progress?(min(offset, total), total)
        }

        // The movie database's film series first: exact, and able to fill a
        // collection that already exists. See `seriesSuggestions`.
        let inLibrary = Set(candidates.map(\.id))
        let series = await seriesSuggestions(within: inLibrary)
        // Film series only. The metadata and title-word passes that followed
        // are retired: on a real library they proposed "Academy", "Adventure"
        // and 129 more collections of titles that shared a word, and the
        // anime franchises they were reaching for now come exactly from
        // AniList on the server, with smart collections for everything a rule
        // can say. See the server's api/collection_anilist.go.
        Diagnostics.log("[collections] suggestions for \(libraryId): \(series.count) film series")
        return series
    }

    /// Creates the accepted groups, skipping any name a collection already uses.
    ///
    /// Skipping rather than merging: a collection that already exists is one someone
    /// curated, and silently pouring a scan's guesses into it would be the kind of
    /// edit nobody asked for and nobody can find afterward.
    @discardableResult
    func createCollections(
        _ groups: [FranchiseGrouping.Group]
    ) async throws -> [String] {
        let existing = Set(
            (try? await allCollections())?.map { $0.item.name.lowercased() } ?? []
        )
        var created: [String] = []
        for group in groups {
            if let collectionId = group.existingCollectionId {
                try await addToCollection(collectionId: collectionId, itemIds: group.itemIds)
                created.append(collectionId)
                continue
            }
            guard !existing.contains(group.name.lowercased()) else { continue }
            // Not `try?`. A permissions failure or a dropped connection used to be
            // counted the same as a name collision, and the sheet then told the
            // user, confidently and wrongly, that the missing ones "already existed
            // by name" — a specific claim about a cause nobody had checked.
            // A nil entry means the server made it but did not hand it back, which
            // is not a failure — the id is unknown, the collection exists.
            if let entry = try await createCollection(
                name: group.name, itemIds: group.itemIds, tmdbCollectionId: group.tmdbCollectionId
            ) {
                created.append(entry.id)
            }
        }
        return created
    }

    private static func candidate(from item: JellyfinItem) -> RelationCandidate {
        RelationCandidate(
            id: item.id,
            name: item.name,
            tags: item.tags ?? [],
            creators: (item.people ?? []).compactMap { person in
                guard let name = person.name,
                      let type = person.type?.lowercased(),
                      relatingRoles.contains(type) else { return nil }
                return name
            },
            studios: (item.studios ?? []).compactMap(\.name),
            overview: item.overview ?? "",
            path: item.path
        )
    }
}

import Foundation

public extension LibraryRepository {
    /// People whose name matches, for search: (id, name, how many titles).
    func searchPeople(_ term: String) async -> [(id: String, name: String, detail: String)] {
        await client.searchPeople(term).map { ($0.id, $0.name, $0.overview ?? "") }
    }

    /// Studios whose name matches, from what the cache holds, biggest first.
    func studiosMatching(_ term: String, limit: Int = 4) async -> [(name: String, count: Int)] {
        let needle = SearchKey.normalize(term)
        guard needle.count >= 2 else { return [] }
        let tallies = (try? await studioTallies()) ?? []
        return tallies
            .filter { SearchKey.normalize($0.name).contains(needle) }
            .prefix(limit)
            .map { ($0.name, $0.count) }
    }
}

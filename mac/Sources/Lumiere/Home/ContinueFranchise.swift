import Foundation
import Observation
import LumiereKit

/// "Continue Monogatari": the franchise or film series you were last in, and
/// the next title in it you have not seen — in the order its collection's
/// page shows, release order or a watch order arranged by hand.
///
/// Continue Watching covers a show part-way through; this covers the step
/// after finishing one, when the next arc is a different show in another
/// library and nothing on Home pointed at it.
@MainActor
@Observable
final class ContinueFranchise {
    static let shared = ContinueFranchise()

    struct Banner: Identifiable {
        let collectionId: String?
        let collectionName: String
        /// The collection itself, for its key art. Nil when not cached.
        let collection: LibraryEntry?
        let next: LibraryEntry
        var id: String { next.id }
    }

    private(set) var banner: Banner?
    private var loading = false

    /// How many recently finished titles are asked about. Each is one
    /// request; the first with a next title wins.
    private let candidates = 8

    func load(repository: LibraryRepository) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let recent = (try? await repository.watchedRecently(limit: 120)) ?? []
        var seen = Set<String>()
        var titles: [LibraryEntry] = []
        for entry in recent where titles.count < candidates {
            // An episode stands for its show — but only once the show is done:
            // a show part-way through is Continue Watching's.
            let title: LibraryEntry?
            if entry.item.itemType == .episode, let seriesId = entry.item.seriesId {
                title = seen.contains(seriesId) ? nil : try? await repository.entry(id: seriesId)
            } else {
                title = entry
            }
            guard let title, seen.insert(title.id).inserted,
                  title.item.itemType == .movie || (title.item.itemType == .series && title.isPlayed) else { continue }
            titles.append(title)
        }
        for title in titles {
            guard let found = await repository.nextInCollection(after: title, unwatched: true) else { continue }
            var collection: LibraryEntry?
            if let id = found.collectionId { collection = try? await repository.entry(id: id) }
            banner = Banner(collectionId: found.collectionId, collectionName: found.collection,
                            collection: collection, next: found.entry)
            return
        }
        banner = nil
    }
}

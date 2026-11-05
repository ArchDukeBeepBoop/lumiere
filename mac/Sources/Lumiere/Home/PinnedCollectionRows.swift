import Foundation
import Observation
import LumiereKit

/// Collections pinned to Home with "Show on Home", each drawn as its own row.
///
/// Its own store rather than more state on `HomeModel`, which is at the
/// project's line limit; Home reads `rows` and the collection page toggles a
/// pin. Which collections are pinned is a preference on this Mac.
@MainActor
@Observable
final class PinnedCollectionRows {
    static let shared = PinnedCollectionRows()

    struct Row: Identifiable {
        let id: String
        let name: String
        let entries: [LibraryEntry]
    }

    private(set) var rows: [Row] = []

    static let storageKey = "homePinnedCollections"

    /// Pinned ids, in the order they were pinned, with their names.
    static var pinned: [(id: String, name: String)] {
        (UserDefaults.standard.array(forKey: storageKey) as? [[String]] ?? [])
            .compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }

    static func isPinned(_ id: String) -> Bool { pinned.contains { $0.id == id } }

    static func toggle(_ id: String, name: String) {
        var list = pinned
        if list.contains(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
        } else {
            list.append((id, name))
        }
        UserDefaults.standard.set(list.map { [$0.id, $0.name] }, forKey: storageKey)
    }

    /// Reads each pinned collection's titles, in the collection's own order.
    func load(repository: LibraryRepository) async {
        var built: [Row] = []
        for pin in Self.pinned {
            let entries = (try? await repository.collectionItems(collectionId: pin.id)) ?? []
            if !entries.isEmpty {
                built.append(Row(id: pin.id, name: pin.name, entries: Array(entries.prefix(40))))
            }
        }
        rows = built
    }
}

import Foundation

/// Splitting a flat list of titles into one group per library.
///
/// Favourites and a genre both gather from everywhere, and presented as one wall
/// they read as a pile: a starred film, an anime episode and a home video sit side
/// by side with nothing saying they came from different parts of the collection.
/// Grouping restores the one piece of context the gathering threw away.
///
/// Pure, so the rule can be tested without a database or a view.
public enum LibraryGrouping {

    public struct Section: Sendable, Identifiable {
        public let libraryId: String?
        public let name: String
        public let entries: [LibraryEntry]

        /// Nil ids are possible — an item the sync never stamped — and they group
        /// together under one heading rather than vanishing.
        public var id: String { libraryId ?? "__unfiled" }
    }

    /// Groups `entries`, ordering the sections the way the sidebar orders libraries.
    ///
    /// The order is taken from the caller rather than sorted here: the sidebar's
    /// order is a stored preference, and a grid that disagrees with the sidebar
    /// about which library comes first is a grid that looks shuffled.
    ///
    /// Within a section the incoming order is preserved, which is whatever the query
    /// sorted by — so a genre wall stays newest-first inside each library.
    public static func sections(
        entries: [LibraryEntry],
        order: [(id: String, name: String)],
        unfiledName: String = "Elsewhere"
    ) -> [Section] {
        guard !entries.isEmpty else { return [] }

        var byLibrary: [String: [LibraryEntry]] = [:]
        var unfiled: [LibraryEntry] = []
        for entry in entries {
            if let id = entry.item.libraryId {
                byLibrary[id, default: []].append(entry)
            } else {
                unfiled.append(entry)
            }
        }

        var sections = order.compactMap { library -> Section? in
            guard let rows = byLibrary[library.id], !rows.isEmpty else { return nil }
            return Section(libraryId: library.id, name: library.name, entries: rows)
        }

        // Anything whose library is not in the order — a library hidden from the
        // sidebar, or a row the sync never stamped — still gets shown, at the end.
        let named = Set(order.map(\.id))
        for (id, rows) in byLibrary where !named.contains(id) {
            sections.append(Section(libraryId: id, name: unfiledName, entries: rows))
        }
        if !unfiled.isEmpty {
            sections.append(Section(libraryId: nil, name: unfiledName, entries: unfiled))
        }
        return sections
    }
}

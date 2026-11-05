import Foundation
import GRDB

public extension LibraryRepository {
    /// Other files of the same film in the same library — the duplicates
    /// Library Health counts, which the server keeps as separate titles
    /// rather than as versions of one.
    func otherCopies(of entry: LibraryEntry) async -> [LibraryEntry] {
        guard entry.item.itemType == .movie else { return [] }
        let item = entry.item
        return (try? await database.writer.read { db in
            try LibraryEntry.fetchAll(db, ItemRecord
                .filter(Column("type") == "Movie")
                .filter(Column("name") == item.name)
                .filter(Column("productionYear") == item.productionYear)
                .filter(Column("libraryId") == item.libraryId)
                .filter(Column("id") != item.id)
                .filter(Column("extraType") == nil))
        }) ?? []
    }
}

public extension LibraryRepository {
    /// The film or show after this one in its collection, with the
    /// collection's name and id. The server says which collection (an anime
    /// franchise before a theme); the order is the one that collection's page
    /// is shown in — release order, or a watch order arranged by hand — so
    /// "next" agrees with the page. With `unwatched`, the first one after it
    /// not yet seen. Nil when there is none.
    func nextInCollection(after entry: LibraryEntry, unwatched: Bool = false) async
        -> (entry: LibraryEntry, collection: String, collectionId: String?)? {
        guard entry.item.itemType == .movie || entry.item.itemType == .series,
              let next = await client.nextInCollection(after: entry.id) else { return nil }
        if let collectionId = next.collectionId,
           let members = try? await collectionItems(collectionId: collectionId) {
            let ranks = (try? await collectionRanks(collectionId: collectionId)) ?? [:]
            let ordered = CollectionOrder.sorted(
                members.filter { $0.item.itemType == .movie || $0.item.itemType == .series },
                by: CollectionOrder.chosen(for: collectionId), ranks: ranks)
            if let at = ordered.firstIndex(where: { $0.id == entry.id }) {
                let after = ordered[(at + 1)...]
                guard let found = unwatched ? after.first(where: { !$0.isPlayed }) : after.first else { return nil }
                return (found, next.collection, collectionId)
            }
        }
        guard let found = try? await self.entry(id: next.id), !unwatched || !found.isPlayed else { return nil }
        return (found, next.collection, next.collectionId)
    }
}

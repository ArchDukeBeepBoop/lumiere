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
    /// The film after this one in its collection, from the cache, with the
    /// collection's name. Nil for anything not in a film series.
    func nextInCollection(after entry: LibraryEntry) async -> (entry: LibraryEntry, collection: String)? {
        guard entry.item.itemType == .movie,
              let next = await client.nextInCollection(after: entry.id),
              let found = try? await self.entry(id: next.id) else { return nil }
        return (found, next.collection)
    }
}

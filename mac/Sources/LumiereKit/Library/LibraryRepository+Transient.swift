import Foundation

public extension LibraryRepository {
    /// Builds a cache row for an item the cache has never seen.
    ///
    /// For a server search hit whose series was never synced: the detail page was
    /// gated on a cached row, so the id resolved on the server and the page sat on
    /// a spinner forever. Not stored — this is a row to *show*, not a claim that the
    /// item belongs to any library.
    func transientEntry(from item: JellyfinItem) -> LibraryEntry {
        LibraryEntry(
            item: ItemRecord(from: item, serverId: serverId, syncedAt: Date()),
            userData: item.userData.map { UserDataRecord(itemId: item.id, from: $0, updatedAt: Date()) }
        )
    }
}

import Foundation

public extension ItemRecord {

    /// A folder that exists on disk but that the server gave no item for.
    ///
    /// Jellyfin collapses a directory holding a single video into a Movie item, so
    /// the directory itself is never reported — and on the `3D` library that left a
    /// file whose path sits inside `Clips/Northwind` with no folder to appear
    /// in. Standing one in keeps the browser showing the folders on disk, which is
    /// the entire point of the mode.
    ///
    /// The id is the path. It is stable, unique, and lets `folderChildren` list the
    /// folder again without a row to look up — absolute paths begin with a separator
    /// and Jellyfin ids do not, so nothing can mistake one for the other.
    static func syntheticFolder(path: String, libraryId: String?) -> ItemRecord {
        let name = (path as NSString).lastPathComponent
        var record = ItemRecord(
            id: path,
            serverId: "",
            type: "Folder",
            name: name,
            sortName: name,
            searchKey: SearchKey.normalize(name),
            isFolder: true,
            syncedAt: Date()
        )
        record.path = path
        record.libraryId = libraryId
        return record
    }

    /// A file Jellyfin merged into a neighbour, standing on its own.
    ///
    /// See `ItemVersionRecord`. The id is the *source* id, which is what playback
    /// needs to pick this file out of the item it was folded into — an ordinary
    /// Jellyfin id, so nothing has to special-case it downstream.
    ///
    /// No watch state of its own, and that is honest rather than an omission: the
    /// server records progress against the item, not the source, so these files
    /// genuinely share one position between them. Showing a separate tick per file
    /// would be inventing a fact the server does not hold.
    static func mergedFile(version: ItemVersionRecord, libraryId: String?) -> ItemRecord {
        let name = version.name
            ?? version.path.map { ($0 as NSString).lastPathComponent }
            ?? version.sourceId
        var record = ItemRecord(
            id: version.sourceId,
            serverId: "",
            type: "Video",
            name: name,
            sortName: name,
            searchKey: SearchKey.normalize(name),
            isFolder: false,
            syncedAt: Date()
        )
        record.path = version.path
        record.libraryId = libraryId
        // The item this file was folded into. `parentId` is free on a row that is
        // built for a listing and never written — the folder hierarchy is keyed on
        // paths now — and it is the honest name for the relationship.
        record.parentId = version.itemId
        return record
    }
}

public extension ItemRecord {

    /// The item to play in order to reach this file, where it has none of its own.
    ///
    /// Nil for everything the server actually returned. The empty `serverId` is what
    /// marks a row this app constructed rather than synced — see `mergedFile` and
    /// `syntheticFolder` — and only a constructed *file* has an owner to name.
    var mergedOwnerId: String? {
        guard serverId.isEmpty, !isFolder else { return nil }
        return parentId
    }
}

import Foundation
import GRDB

public extension LibraryRepository {
    /// An item's extras, cached so a detail page seen once still shows them offline.
    ///
    /// Extras are not part of the library sync — a recursive /Items query does not
    /// return them at all — so they are fetched per item and written into the same
    /// cache as everything else. A network failure returns whatever was cached rather
    /// than nothing: an extras row that vanishes when the server hiccups is worse
    /// than a stale one.
    func extras(itemId: String) async throws -> [LibraryEntry] {
        let cachedIds: [String] = try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM item WHERE parentId = ? AND extraType IS NOT NULL ORDER BY sortName",
                arguments: [itemId]
            )
        }

        do {
            let fetched = try await client.specialFeatures(itemId: itemId)
            guard !fetched.isEmpty else { return try await entriesById(cachedIds) }

            let now = Date()
            let parentId = itemId
            try await database.writer.write { [serverId] db in
                for item in fetched {
                    var record = ItemRecord(from: item, serverId: serverId, syncedAt: now)
                    // Attached to the title they belong to. The server reports an
                    // extra's parent inconsistently, and without this they would be
                    // unfindable the next time the page opens.
                    record.parentId = parentId
                    // Marked as an extra even when the server omits ExtraType, since
                    // arriving from this endpoint is itself proof of what it is.
                    if record.extraType == nil { record.extraType = "Extra" }
                    try record.save(db)
                }
            }
            return try await entriesById(fetched.map(\.id))
        } catch {
            Diagnostics.log("[extras] \(itemId) failed, using cache: \(error)")
            return try await entriesById(cachedIds)
        }
    }

    // Not private: LibraryRepository+Collections.swift reuses this to turn a
    // server-ordered id list (a collection's own member order) back into entries.
    func entriesById(_ ids: [String]) async throws -> [LibraryEntry] {
        guard !ids.isEmpty else { return [] }
        let entries: [LibraryEntry] = try await database.writer.read { db in
            let request = ItemRecord
                .filter(ids.contains(Column("id")))
                .including(optional: ItemRecord.userDataAssociation)
            return try LibraryEntry.fetchAll(db, request)
        }
        // Restored to the server's order, which groups trailers with trailers.
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return entries.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }
}

public extension LibraryRepository {
    /// The immediate children of a folder, or of a library when `parentId` is its id.
    ///
    /// For libraries that hold loose files rather than matched titles — a "3D" or
    /// "My Videos" folder — where the metadata grid is the wrong shape entirely: it
    /// hides the folders the user organised things into and flattens 530 items into one
    /// alphabetical wall.
    ///
    /// Folders first, then files, each alphabetically. That is how every file browser
    /// on the platform behaves, and the point of this mode is to look like the folders
    /// on disk.
    /// Keyed on the *path* where the folder has one, and on `parentId` only where
    /// it does not.
    ///
    /// Jellyfin's ParentId is not always the folder the file is in — see `FolderTree`
    /// for the measurements. The path is what the user organised and what this mode
    /// exists to show, so it wins wherever it is known, and directories the server
    /// never gave an item for are synthesised rather than losing the files inside
    /// them.
    ///
    /// A synthetic folder's id *is* its path, which is how a second call can list it
    /// without a row to look up. Absolute paths start with a separator and Jellyfin
    /// ids do not, so the two can never be confused.
    func folderChildren(parentId: String) async throws -> [LibraryEntry] {
        let entries: [LibraryEntry] = try await database.writer.read { db in
            let folder: String
            if parentId.hasPrefix("/") {
                folder = parentId
            } else if let parent = try ItemRecord.fetchOne(db, key: parentId),
                      let path = parent.path, !path.isEmpty {
                folder = path
            } else {
                // No path to work from — a server that reports none, or a row synced
                // before the column existed. The old behaviour is still correct here.
                let request = ItemRecord
                    .filter(Column("parentId") == parentId)
                    .including(optional: ItemRecord.userDataAssociation)
                return try LibraryEntry.fetchAll(db, request)
            }

            let base = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
            let prefix = base + "/"
            // A range rather than a `LIKE`: these paths are full of brackets and
            // punctuation that a pattern would read as wildcards.
            //
            // The upper bound replaces the *separator*, not the character after it:
            // `/` is 0x2F and `0` is 0x30, so `base + "0"` is the first string that
            // sorts past everything under `base + "/"`. Putting the `0` after the
            // slash instead — which is what this did first — excluded every child
            // whose name begins with a letter, which is all of them.
            let request = ItemRecord
                .filter(Column("path") >= prefix && Column("path") < base + "0")
                .including(optional: ItemRecord.userDataAssociation)
            let below = try LibraryEntry.fetchAll(db, request)

            // The files Jellyfin merged into their neighbours, standing beside them
            // as the separate things they are on disk. See `ItemVersionRecord`.
            //
            // Only the ones this listing does not already hold: the item that
            // swallowed the others keeps its own row, and its own path is one of the
            // sources, so without this a merged folder would show its first file
            // twice.
            let owned = Set(below.map(\.item.id))
            let versions = try ItemVersionRecord
                .filter(owned.contains(Column("itemId")))
                .fetchAll(db)
            let cachedPaths = Set(below.compactMap(\.item.path))
            let extraPaths = versions.compactMap(\.path).filter { !cachedPaths.contains($0) }

            // The folders among them named as folders. See `FolderTree.listing`:
            // a cached sub-folder's own path is one level down and therefore looks
            // exactly like a file, which listed every one of them twice.
            let directories = Set(
                below.filter(\.item.isFolder).compactMap(\.item.path)
            )
            let listing = FolderTree.listing(
                of: folder, paths: below.compactMap(\.item.path) + extraPaths,
                directories: directories
            )
            let byPath = Dictionary(
                below.compactMap { entry in entry.item.path.map { ($0, entry) } },
                uniquingKeysWith: { first, _ in first }
            )

            let versionByPath = Dictionary(
                versions.compactMap { version in version.path.map { ($0, version) } },
                uniquingKeysWith: { first, _ in first }
            )
            let files = listing.files.compactMap { path -> LibraryEntry? in
                if let entry = byPath[path] { return entry }
                // A file with no row of its own. It plays through the item it was
                // merged into, which is why the version carries that item's id.
                guard let version = versionByPath[path] else { return nil }
                return LibraryEntry(
                    item: .mergedFile(
                        version: version,
                        libraryId: byPath[version.itemId]?.item.libraryId
                            ?? below.first?.item.libraryId
                    ),
                    userData: nil
                )
            }
            let folders = listing.folders.map { path in
                // A real row where the server gave one, so its artwork and watch
                // state survive; a stand-in only where it did not.
                byPath[path] ?? LibraryEntry(
                    item: .syntheticFolder(path: path, libraryId: byPath[path]?.item.libraryId),
                    userData: nil
                )
            }
            return folders + files
        }
        // Unique, whatever the listing produced. A duplicate id in a SwiftUI
        // `ForEach` does not draw twice — it draws once and leaves a blank cell
        // where the other should be, which is a layout bug to look at and a data bug
        // to fix. Cheap insurance that the wall can only ever be wrong in one place.
        var seen: Set<String> = []
        return Self.foldersFirst(entries.filter { seen.insert($0.id).inserted })
    }

    /// What sits at the top of a folder-browsed library.
    ///
    /// Not `folderChildren(parentId: libraryId)`, and that assumption is exactly what
    /// emptied 3D and My Videos. The id `/UserViews` reports is a *view* id, while
    /// every item's ParentId points at the physical folder behind that view — a
    /// different id, and one that is not itself cached. On My Videos all 1,755 rows
    /// had a parent and not one of them was the library, so a root listing keyed on
    /// the library id matched nothing, while the poster grid — which filters on
    /// `libraryId` — kept working. That difference is why it looked as though the
    /// folder browser alone had lost the files.
    ///
    /// The roots are therefore whatever this library holds whose parent is not also
    /// in this library. True whichever id the server hands back, so it survives
    /// Jellyfin changing its mind about view ids again.
    func libraryRootChildren(libraryId: String) async throws -> [LibraryEntry] {
        let entries: [LibraryEntry] = try await database.writer.read { db in
            let request = ItemRecord
                .filter(Column("libraryId") == libraryId)
                .filter(sql: """
                    (item.parentId IS NULL
                     OR item.parentId = ?
                     OR NOT EXISTS (
                         SELECT 1 FROM item AS parent
                         WHERE parent.id = item.parentId AND parent.libraryId = ?
                     ))
                    """, arguments: [libraryId, libraryId])
                .including(optional: ItemRecord.userDataAssociation)
            return try LibraryEntry.fetchAll(db, request)
        }
        return Self.foldersFirst(entries)
    }

    /// Folders first, then files, each alphabetically — how every file browser on
    /// this platform behaves, and the whole point of the mode.
    private static func foldersFirst(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { left, right in
            let leftIsFolder = left.item.isFolder
            let rightIsFolder = right.item.isFolder
            if leftIsFolder != rightIsFolder { return leftIsFolder }
            return left.item.name.localizedStandardCompare(right.item.name) == .orderedAscending
        }
    }

    /// Whether anything is cached below this point, so the UI can tell "empty folder"
    /// from "not synced yet" — they look identical and need different messages.
    func hasFolderChildren(parentId: String) async throws -> Bool {
        try await database.writer.read { db in
            try ItemRecord.filter(Column("parentId") == parentId).fetchCount(db) > 0
        }
    }
}

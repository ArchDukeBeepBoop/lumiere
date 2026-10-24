import Foundation
import GRDB

/// Files opened directly — from Finder, the Dock, File › Open or a drop — rather
/// than through a folder added in Settings.
///
/// Written as ordinary local rows, for the reason `LocalLibrary` gives: resume,
/// watch state, subtitle offsets and the player's next and previous all work
/// because the file is a row like any other. They live under one hidden library,
/// `LocalLibrary.openedLibraryId`, so opening a file never adds a sidebar entry.
///
/// A file's whole folder is written, not the file alone. Opening episode 3 is
/// opening the season: the folder's other files are what Next plays, and in VLC
/// the missing next episode was the thing everyone tripped on.
public extension LibraryRepository {

    /// Writes rows for what was opened and returns the ids to play, in order.
    ///
    /// A file gives its own id; a folder gives every playable file inside it,
    /// sorted as Finder sorts names. Rows already written by a folder added in
    /// Settings are left as they are — the id is the path's, so it is the same
    /// row either way, and that library keeps it.
    func openLocal(_ urls: [URL]) async throws -> [String] {
        var records: [ItemRecord] = []
        var play: [String] = []
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                let scan = LocalLibraryScanner(
                    root: url, libraryId: LocalLibrary.openedLibraryId,
                    fileLimit: 5_000, extensions: LocalLibrary.playableExtensions
                ).scan()
                records += scan.records
                play += scan.records.filter { !$0.isFolder }
                    .sorted { ($0.path ?? "").localizedStandardCompare($1.path ?? "") == .orderedAscending }
                    .map(\.id)
            } else if LocalLibrary.isPlayable(url) {
                records += Self.folderRecords(around: url)
                play.append(LocalLibrary.id(for: url.path))
            }
        }
        let rows = records
        try await database.writer.write { db in
            try LibraryRecord(
                id: LocalLibrary.openedLibraryId,
                serverId: LocalLibrary.serverId,
                name: "Opened Files",
                collectionType: nil,
                sortIndex: 2_000,
                itemCount: 0
            ).save(db)
            for record in rows where try !record.exists(db) { try record.insert(db) }
        }
        return play
    }

    /// The folder holding a file and the playable files beside it, not deeper.
    private static func folderRecords(around file: URL) -> [ItemRecord] {
        let folder = file.deletingLastPathComponent()
        let folderId = LocalLibrary.id(for: folder.path)
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [file]
        var records = [LocalLibraryScanner.record(
            url: folder, id: folderId, parentId: nil, isFolder: true,
            created: nil, libraryId: LocalLibrary.openedLibraryId
        )]
        for url in siblings where LocalLibrary.isPlayable(url) {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            records.append(LocalLibraryScanner.record(
                url: url, id: LocalLibrary.id(for: url.path), parentId: folderId,
                isFolder: false, created: created, libraryId: LocalLibrary.openedLibraryId
            ))
        }
        return records
    }

    /// The playable files in the same folder as a local item, in name order —
    /// what Next and Previous move through for a file with no season.
    func localSiblings(of itemId: String) async throws -> [LibraryEntry] {
        guard LocalLibrary.isLocal(itemId: itemId),
              let parent = try await entry(id: itemId)?.item.parentId
        else { return [] }
        return try await entries(parentId: parent, types: [.video, .audio], sort: .title, limit: 2_000)
            .filter { !$0.item.isFolder }
            .sorted { a, b in
                // A playlist's channels keep the list's order; files go by name.
                if let x = a.item.indexNumber, let y = b.item.indexNumber { return x < y }
                return (a.item.path ?? "").localizedStandardCompare(b.item.path ?? "") == .orderedAscending
            }
    }
}

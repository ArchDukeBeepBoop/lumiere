import Foundation

/// Walks a folder and turns it into cache rows.
///
/// Depth-first through real directories, one row per folder and one per playable
/// file, with `parentId` wired to the enclosing folder so the existing browser can
/// walk it exactly as it walks a Jellyfin folder library.
///
/// No probing. Nothing here opens a file, reads a header or asks ffprobe how long
/// anything is: a first scan of a few thousand files has to finish while somebody
/// is watching, and every fact worth having at browse time — the name, the folder
/// it is in, when it was added — is already in the directory entry. Runtime and
/// codecs are what the player reports once a file is actually opened, which is
/// both accurate and free.
public struct LocalLibraryScanner: Sendable {

    public struct Result: Sendable {
        public var records: [ItemRecord]
        /// Folders that could not be read, by path. Surfaced rather than swallowed:
        /// an unreadable folder is usually an unmounted volume, and "nothing here"
        /// is the wrong answer to that.
        public var unreadable: [String]
        public var fileCount: Int
    }

    public let root: URL
    public let libraryId: String
    /// A ceiling on how much one folder may contribute, so a mistaken choice —
    /// the whole home directory, a Time Machine volume — cannot spend an hour
    /// writing rows before anyone can stop it.
    public var fileLimit: Int = 50_000

    public init(root: URL, libraryId: String, fileLimit: Int = 50_000) {
        self.root = root
        self.libraryId = libraryId
        self.fileLimit = fileLimit
    }

    public func scan() -> Result {
        var records: [ItemRecord] = []
        var unreadable: [String] = []
        var files = 0
        var queue: [(url: URL, parentId: String?)] = [(root, nil)]

        while let next = queue.popLast(), files < fileLimit {
            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: next.url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .creationDateKey, .fileSizeKey
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            } catch {
                unreadable.append(next.url.path)
                continue
            }

            for url in contents {
                let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .creationDateKey]
                )
                let isDirectory = values?.isDirectory ?? false

                if isDirectory {
                    let id = LocalLibrary.id(for: url.path)
                    records.append(record(
                        url: url, id: id, parentId: next.parentId,
                        isFolder: true, created: values?.creationDate
                    ))
                    queue.append((url, id))
                } else if LocalLibrary.videoExtensions.contains(url.pathExtension.lowercased()) {
                    guard files < fileLimit else { break }
                    files += 1
                    records.append(record(
                        url: url, id: LocalLibrary.id(for: url.path),
                        parentId: next.parentId, isFolder: false,
                        created: values?.creationDate
                    ))
                }
            }
        }

        return Result(records: records, unreadable: unreadable, fileCount: files)
    }

    /// One row.
    ///
    /// `name` is the filename with its extension removed, which is what a person
    /// calls the thing — the extension is still shown, because the folder browser
    /// draws local files by their real filename. Type is `Video` rather than
    /// `Movie`: a loose file is not a matched title, and claiming otherwise puts it
    /// in grids and shelves that promise metadata it does not have.
    private func record(
        url: URL, id: String, parentId: String?, isFolder: Bool, created: Date?
    ) -> ItemRecord {
        let name = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var item = ItemRecord(
            id: id,
            serverId: LocalLibrary.serverId,
            type: isFolder ? "Folder" : "Video",
            name: name,
            sortName: ItemRecord.normalizedTitle(name),
            searchKey: SearchKey.normalize(name),
            isFolder: isFolder,
            syncedAt: Date()
        )
        item.parentId = parentId
        item.libraryId = libraryId
        // Canonical, so the row and the id agree and a later lookup by path finds
        // it whichever alias the file was reached through.
        item.path = LocalLibrary.canonicalPath(url.path)
        item.setDateCreated(created)
        return item
    }
}

import Foundation

/// Turning a flat list of paths into the folders they live in.
///
/// A pure function, because deciding what a directory listing contains is exactly
/// the kind of rule that should be readable and testable without a database behind
/// it — and because it got this wrong twice against a real library.
///
/// The problem it solves: Jellyfin's `ParentId` is not always the folder a file is
/// in. Measured on the `3D` library, fifteen rows had a parent whose own path was
/// not their containing directory — a folder holding a single video is collapsed
/// into a Movie item, so the video's parent becomes that item rather than the
/// folder on disk. And `Clips/Northwind` had no cached row at all while holding
/// a file, so keying purely on cached rows would have left that file with nowhere
/// to appear.
public enum FolderTree {

    /// What a directory listing holds, given every path beneath it.
    public struct Listing: Sendable, Equatable {
        /// Paths that sit directly in this folder.
        public var files: [String]
        /// Sub-directory paths, whether or not the server gave them an item.
        public var folders: [String]
    }

    /// Splits paths under `folder` into its immediate files and sub-directories.
    ///
    /// Anything deeper than one level contributes its *next* segment as a folder,
    /// which is what makes a directory appear even when nothing cached represents
    /// it. Deduplicated, because a folder with forty files inside it is still one
    /// folder.
    ///
    /// `directories` names the paths the caller already knows are folders, and
    /// without it this function cannot tell: a path one level down is a file *by
    /// shape*, and a directory the server did give a row for looks exactly like one.
    /// On the real `3D` library that put every cached sub-folder in the listing
    /// twice — once as a folder, synthesised from the files beneath it, and once as
    /// a "file", from its own row. The wall drew 37 tiles for 21 folders, and
    /// because both copies carry the same id, SwiftUI's `ForEach` drew the second of
    /// each pair as an empty cell: sixteen blanks scattered through the grid.
    public static func listing(
        of folder: String, paths: [String], directories: Set<String> = []
    ) -> Listing {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        var files: [String] = []
        var folders: Set<String> = []

        for path in paths where path.hasPrefix(prefix) && path != prefix {
            let rest = path.dropFirst(prefix.count)
            guard let separator = rest.firstIndex(of: "/") else {
                // One level down, so it is an immediate child — of whichever kind
                // the caller says it is.
                if directories.contains(path) {
                    folders.insert(path)
                } else {
                    files.append(path)
                }
                continue
            }
            folders.insert(prefix + rest[rest.startIndex..<separator])
        }

        return Listing(
            files: files,
            folders: folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        )
    }

    /// The last component of a path, for naming a folder that has no item to name it.
    public static func name(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

import Foundation

/// What a tile from a folder library is called.
///
/// A folder library has no scraper, so `item.name` is whatever Jellyfin made of the
/// filename — usually the filename with the extension off and the punctuation
/// tidied, sometimes something further from it. In a library of loose files that is
/// the wrong answer: the filename *is* the identity, and two rips of the same film
/// differ only in the part a tidied name throws away.
///
/// The folder browser already knew this and passed a `titleOverride` on every tile.
/// Nothing else did, so the same file was its filename inside the browser and its
/// metadata name on the home screen, in Continue Watching, in search and on its own
/// page — for `3D` and `My Videos`, which is exactly where it matters most.
///
/// So the rule follows the *library* rather than the surface. Any card can ask, and
/// a surface added later inherits it without having to know the rule exists.
public enum FolderTitle {

    /// The title for an entry, honouring the folder-library rule.
    ///
    /// Falls through to the ordinary `TitleStyle` for everything else, so a scraped
    /// library still shows whatever the Settings preference asks for.
    public static func title(
        for entry: LibraryEntry,
        style: TitleStyle,
        folderLibraryIds: Set<String>
    ) -> String {
        guard let libraryId = entry.item.libraryId,
              folderLibraryIds.contains(libraryId)
        else { return TitleFormatter.title(for: entry.item, style: style) }
        return filename(for: entry.item)
    }

    /// The filename without its extension.
    ///
    /// The extension goes because every tile in such a library ends in the same three
    /// or four letters — a column of repeated text stealing room from the part of the
    /// name that differs. It stays in the About block, where the question being asked
    /// is what the file is actually called.
    public static func filename(for item: ItemRecord) -> String {
        let name = TitleFormatter.title(for: item, style: .originalFilename)
        return (name as NSString).deletingPathExtension
    }
}

import Foundation

/// How a folder library is laid out: Finder's three, and remembered per library.
///
/// Per library rather than globally, because the answer genuinely differs between
/// them: a wall of 3D films is worth seeing as artwork, a deep tree of clips is
/// faster to walk as columns, and a folder of near-identically named files reads
/// better as a list where the name has room to be long.
public enum FolderViewMode: String, CaseIterable, Sendable, Identifiable {
    case icon, list, column

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .icon: return "Icons"
        case .list: return "List"
        case .column: return "Columns"
        }
    }

    /// SF Symbol for the segmented control. The same three macOS uses, so the
    /// control is recognisable before it is read.
    public var symbol: String {
        switch self {
        case .icon: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .column: return "rectangle.split.3x1"
        }
    }

    /// The stored preference is one string for every library — `"id=mode"` pairs,
    /// comma-separated — because `@AppStorage` holds a value, not a dictionary,
    /// and the existing shape control already encodes itself this way.
    public static let storageKey = "folderViewMode"

    /// Reads one library's mode out of the stored string.
    ///
    /// Anything unparseable is `.icon`: a preference that cannot be read is not a
    /// reason to show an empty screen, and icons are what this view has always
    /// been.
    public static func mode(for libraryId: String, in stored: String) -> FolderViewMode {
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == libraryId else { continue }
            return FolderViewMode(rawValue: String(parts[1])) ?? .icon
        }
        return .icon
    }

    /// Writes one library's mode back, leaving every other library's alone.
    public static func setting(
        _ mode: FolderViewMode, for libraryId: String, in stored: String
    ) -> String {
        var pairs = stored.split(separator: ",")
            .filter { !$0.hasPrefix(libraryId + "=") }
            .map(String.init)
        pairs.append("\(libraryId)=\(mode.rawValue)")
        // Sorted so the stored string is stable: an order that depended on which
        // library was touched last would rewrite the preference on every change.
        return pairs.sorted().joined(separator: ",")
    }
}

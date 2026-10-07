import Foundation

/// What a title reads as throughout the app.
///
/// Infuse offers a single "Show Filenames" switch, which conflates two different
/// things. A library renamed to a clean scheme and one still carrying
/// `The.Show.S01E01.1080p.WEB-DL.DDP5.1.H.264-GROUP.mkv` want different answers,
/// so this splits them.
public enum TitleStyle: String, CaseIterable, Identifiable, Sendable {
    /// What the item is called. "Pilot", "Blade Runner 2049".
    case metadataTitle
    /// A filename built from the metadata: "Rick and Morty - 1x01 - Pilot.mkv".
    /// Consistent regardless of how the file is actually named on disk.
    case metadataFilename
    /// The literal basename on disk, whatever it happens to be.
    case originalFilename

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .metadataTitle: return "Title"
        case .metadataFilename: return "Metadata filename"
        case .originalFilename: return "Original filename"
        }
    }

    public var explanation: String {
        switch self {
        case .metadataTitle:
            return "What the item is called. \"Pilot\"."
        case .metadataFilename:
            return "A filename built from the metadata, consistent whatever the file "
                 + "is really called. \"Rick and Morty - 1x01 - Pilot.mkv\"."
        case .originalFilename:
            return "Exactly what the file is named on disk, release tags and all."
        }
    }
}

/// Renders titles in the chosen style. Pure, so the rules are testable without a
/// library or a server.
public enum TitleFormatter {

    public static func title(for item: ItemRecord, style: TitleStyle) -> String {
        switch style {
        case .metadataTitle:
            return item.name

        case .metadataFilename:
            return metadataFilename(for: item)

        case .originalFilename:
            guard let path = item.path, !path.isEmpty else {
                // Falls back rather than showing nothing: an item synced before
                // the path column existed has no filename to show, and a blank
                // title is never the right answer.
                return metadataFilename(for: item)
            }
            return (path as NSString).lastPathComponent
        }
    }

    /// `Series - 1x01 - Episode.mkv` for episodes, `Title (Year).mkv` otherwise.
    ///
    /// Matches the scheme Jellyfin's own renamer produces, so on a tidied library
    /// this and the original filename agree — which is rather the point of
    /// offering both.
    public static func metadataFilename(for item: ItemRecord) -> String {
        let ext = fileExtension(for: item)

        if item.itemType == .episode {
            let series = item.seriesName ?? item.name
            guard let season = item.parentIndexNumber, let episode = item.indexNumber else {
                return "\(series) - \(item.name)\(ext)"
            }
            return String(format: "%@ - %dx%02d - %@%@", series, season, episode, item.name, ext)
        }

        guard let year = item.productionYear else { return item.name + ext }
        return "\(item.name) (\(year))\(ext)"
    }

    /// Taken from the real path where one is cached. Guessing a container would
    /// print `.mkv` beside an mp4 and undermine the whole feature.
    private static func fileExtension(for item: ItemRecord) -> String {
        guard let path = item.path, !path.isEmpty else { return "" }
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    /// The line beneath a title.
    ///
    /// Drops to the metadata title when the title itself is a filename, so the
    /// two lines never say the same thing twice.
    public static func subtitle(for item: ItemRecord, style: TitleStyle) -> String? {
        if style != .metadataTitle {
            guard item.itemType == .episode else { return item.name }
            return [seasonEpisode(for: item), item.name]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        switch item.itemType {
        case .episode:
            return seasonEpisode(for: item) ?? item.seriesName
        case .season:
            return item.seriesName
        case .series:
            guard let count = item.childCount, count > 0 else {
                return item.productionYear.map(String.init)
            }
            return "\(count) season\(count == 1 ? "" : "s")"
        default:
            return item.productionYear.map(String.init)
        }
    }

    static func seasonEpisode(for item: ItemRecord) -> String? {
        item.episodeCode()
    }
}

import Foundation

/// Which name a library's titles go by, and which sits under it — chosen per
/// library in Settings › Look › Title Order.
///
/// A scraped library is usually best by its metadata title. A library whose
/// folders are named the way their owner knows them, with romaji under them,
/// wants the opposite; one setting for every library could not serve both.
public enum LibraryTitleOrder: String, CaseIterable, Identifiable, Sendable {
    /// The metadata title, the original title under it. The default.
    case standard
    /// The folder's name, the romaji under it.
    case folderThenRomaji
    /// The romaji, the metadata title under it.
    case romajiThenTitle
    /// The folder's name alone.
    case folder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Title, then original title"
        case .folderThenRomaji: return "Folder name, then romaji"
        case .romajiThenTitle: return "Romaji, then title"
        case .folder: return "Folder name"
        }
    }

    public static let storageKey = "libraryTitleOrder"

    public static func order(for libraryId: String?, in defaults: UserDefaults = .standard) -> LibraryTitleOrder {
        guard let libraryId,
              let raw = defaults.dictionary(forKey: storageKey)?[libraryId] as? String
        else { return .standard }
        return LibraryTitleOrder(rawValue: raw) ?? .standard
    }

    /// How each library's franchises should be named on the server, from
    /// these orders: by folder name, or by romaji. Libraries on the standard
    /// order are left out and keep the English-first name.
    public static func franchiseNaming(in defaults: UserDefaults = .standard) -> [String: String] {
        var out: [String: String] = [:]
        for (id, raw) in defaults.dictionary(forKey: storageKey) ?? [:] {
            switch (raw as? String).flatMap(LibraryTitleOrder.init(rawValue:)) {
            case .folderThenRomaji, .folder: out[id] = "folder"
            case .romajiThenTitle: out[id] = "romaji"
            default: break
            }
        }
        return out
    }

    public static func set(_ order: LibraryTitleOrder, for libraryId: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        all[libraryId] = order == .standard ? nil : order.rawValue
        defaults.set(all, forKey: storageKey)
    }

    /// The name a title goes by under this order; nil keeps the usual rules.
    /// Shows, films and collections only — an episode keeps its own title.
    public func primary(for item: ItemRecord) -> String? {
        guard [.series, .movie, .video, .season].contains(item.itemType) else { return nil }
        switch self {
        case .standard: return nil
        case .folderThenRomaji, .folder: return Self.folderName(item) ?? item.romajiTitle
        case .romajiThenTitle: return item.romajiTitle
        }
    }

    /// The second name, under the first; nil when there is none worth showing.
    public func secondary(for item: ItemRecord) -> String? {
        switch self {
        case .standard: return item.originalTitle
        case .folderThenRomaji: return item.romajiTitle ?? item.originalTitle
        case .romajiThenTitle: return item.romajiTitle == nil ? item.originalTitle : item.name
        case .folder: return nil
        }
    }

    /// What a title sort orders by, as SQL over `item`: the name the tiles
    /// show, so a library read by folder name is also in folder-name order —
    /// and the A–Z rail lands where the names say. The folder is the last
    /// part of the stored path (a file keeps its extension, which only ever
    /// breaks a tie). Episodes keep their own key, as `primary` leaves them.
    public var titleSortSQL: String {
        let folder = "CASE WHEN item.type IN ('Series','Movie','Video','Season') AND COALESCE(item.path, '') <> '' "
            + "THEN lower(replace(item.path, rtrim(item.path, replace(item.path, '/', '')), '')) END"
        let romaji = "CASE WHEN item.type IN ('Series','Movie','Video','Season') THEN lower(NULLIF(item.romajiTitle, '')) END"
        switch self {
        case .standard: return "item.sortName"
        case .folderThenRomaji, .folder: return "COALESCE(\(folder), \(romaji), item.sortName)"
        case .romajiThenTitle: return "COALESCE(\(romaji), item.sortName)"
        }
    }

    /// A show's or a season's folder, a film's file name without extension.
    public static func folderName(_ item: ItemRecord) -> String? {
        guard let path = item.path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let name = item.isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }
}

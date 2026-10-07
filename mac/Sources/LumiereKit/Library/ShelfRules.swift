import Foundation

/// What a library's shelf is allowed to draw from.
///
/// A shelf on the home screen — a library's Latest row, and the mixed Recently
/// Added row — used to take whatever the query returned. Which is the right
/// default and the wrong rule: a folder library holds screen recordings beside
/// the things worth surfacing, a television library holds a `Samples` folder
/// somebody never deleted, and there was no way to say "not that" short of
/// deleting it.
///
/// One rule set per library, stored as JSON under `storageKey` keyed by library
/// id. A library with no stored rules gets `default`, which admits everything —
/// the rules exist to narrow, never to surprise.
///
/// Pure, so `qualifies` can be checked against the cases that matter.
public struct ShelfRules: Codable, Sendable, Equatable {

    public static let storageKey = "shelfRulesByLibrary"

    public var films = true
    public var series = true
    public var episodes = true
    public var collections = true
    /// Loose files the scanner could not place — everything in a folder
    /// library. Off here is the per-library form of `Preference.latestIncludesVideos`.
    public var videos = true
    /// Folder names, matched against every component of the item's path, case
    /// insensitively. `Samples`, `Extras`, `Behind the Scenes`. Names rather
    /// than paths, so a rule survives a library being moved.
    public var excludedFolders: [String] = []
    /// Shorter than this many minutes is not content. Zero is no rule.
    public var minimumMinutes = 0

    public init() {}

    public static let `default` = ShelfRules()

    /// Whether an item may sit on this library's shelf.
    public func qualifies(_ entry: LibraryEntry) -> Bool {
        switch entry.item.itemType {
        case .movie: if !films { return false }
        case .series, .season: if !series { return false }
        case .episode: if !episodes { return false }
        case .boxSet: if !collections { return false }
        case .video: if !videos { return false }
        default: break
        }
        if minimumMinutes > 0, let seconds = entry.item.runtimeSeconds,
           seconds > 0, seconds < Double(minimumMinutes) * 60 {
            return false
        }
        if !excludedFolders.isEmpty, let path = entry.item.path {
            let components = path.split(separator: "/").map { $0.lowercased() }
            for folder in excludedFolders {
                let needle = folder.trimmingCharacters(in: .whitespaces).lowercased()
                if !needle.isEmpty, components.dropLast().contains(needle) {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Storage

    public static func all(from stored: String?) -> [String: ShelfRules] {
        guard let stored, let data = stored.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ShelfRules].self, from: data)
        else { return [:] }
        return decoded
    }

    public static func encode(_ rules: [String: ShelfRules]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(rules)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func rules(for libraryId: String?, in all: [String: ShelfRules]) -> ShelfRules {
        guard let libraryId else { return .default }
        return all[libraryId] ?? .default
    }
}

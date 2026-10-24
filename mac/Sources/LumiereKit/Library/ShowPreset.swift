import Foundation

/// A show's own player settings, saved once and brought back every episode —
/// VLC's binge complaint: the subtitle delay, size and track set again for
/// each episode of the same release.
///
/// Keyed by the show (or, for a file on this Mac, its folder). Everything is
/// optional: a preset holds only what was set when it was saved, and anything
/// it leaves out follows the app-wide setting as before. Audio and subtitle
/// languages are not here: the player already remembers those per show.
public struct ShowPreset: Codable, Equatable, Sendable {
    public var subtitleDelay: Double?
    public var audioDelay: Double?
    public var subtitleScale: Double?
    public var subtitlePosition: Int?
    public var subtitleStyleId: String?
    public var subtitleSizeId: String?
    /// Encoded `PictureAdjustments`, kept opaque here so LumiereKit need not
    /// know the player's types.
    public var picture: Data?
    public var soundPreset: String?

    public init() {}

    public static let storageKey = "showPresets"

    public static func load(for titleId: String, in defaults: UserDefaults = .standard) -> ShowPreset? {
        guard let data = (defaults.dictionary(forKey: storageKey)?[titleId]) as? Data else { return nil }
        return try? JSONDecoder().decode(ShowPreset.self, from: data)
    }

    public static func save(_ preset: ShowPreset?, for titleId: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        all[titleId] = preset.flatMap { try? JSONEncoder().encode($0) }
        defaults.set(all, forKey: storageKey)
    }

    public static func count(in defaults: UserDefaults = .standard) -> Int {
        defaults.dictionary(forKey: storageKey)?.count ?? 0
    }

    public static func removeAll(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// Moments marked in a file with ⌘B, listed beside its chapters.
public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var seconds: Double
    public var label: String

    public init(id: UUID = UUID(), seconds: Double, label: String) {
        self.id = id
        self.seconds = seconds
        self.label = label
    }
}

public enum Bookmarks {
    public static let storageKey = "bookmarksByItem"

    public static func all(for itemId: String, in defaults: UserDefaults = .standard) -> [Bookmark] {
        guard let data = defaults.dictionary(forKey: storageKey)?[itemId] as? Data,
              let marks = try? JSONDecoder().decode([Bookmark].self, from: data) else { return [] }
        return marks.sorted { $0.seconds < $1.seconds }
    }

    public static func save(_ marks: [Bookmark], for itemId: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        all[itemId] = marks.isEmpty ? nil : try? JSONEncoder().encode(marks.sorted { $0.seconds < $1.seconds })
        defaults.set(all, forKey: storageKey)
    }
}

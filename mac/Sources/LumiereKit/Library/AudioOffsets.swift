import Foundation

/// Per-file audio offsets, in seconds. Kept in preferences rather than the
/// library cache: a handful of numbers, and they must survive a cache rebuild.
public enum AudioOffsets {
    static let key = "audioOffsets"

    public static func saved(itemId: String, defaults: UserDefaults = .standard) -> Double {
        (defaults.dictionary(forKey: key) as? [String: Double])?[itemId] ?? 0
    }

    public static func save(_ seconds: Double, itemId: String, defaults: UserDefaults = .standard) {
        var all = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        all[itemId] = abs(seconds) < 0.05 ? nil : seconds
        defaults.set(all, forKey: key)
    }
}

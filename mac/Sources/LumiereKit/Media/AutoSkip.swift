import Foundation

/// Skipping a season's intro without being asked, once you always do.
///
/// Three presses of Skip Intro in one season is a clear enough preference;
/// from then on the player skips it for you, says so, and offers the way back
/// — the same undo a manual skip has. Per season, because a new season
/// usually brings a new opening worth hearing once. Settings › Playback.
public enum AutoSkip {

    public static let storageKey = "autoSkipCounts"
    public static let threshold = 3

    public static func record(_ key: String, in defaults: UserDefaults = .standard) {
        var counts = defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: storageKey)
    }

    public static func isOn(for key: String, in defaults: UserDefaults = .standard) -> Bool {
        ((defaults.dictionary(forKey: storageKey) as? [String: Int])?[key] ?? 0) >= threshold
    }
}

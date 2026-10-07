import Foundation

/// The level the player opens at, remembered across launches.
///
/// QuickTime does this and it is what anyone expects: a player that starts at
/// full volume every time is one you reach for the slider on before every file.
///
/// Mute is deliberately not remembered. Opening silent with no explanation reads
/// as a broken player, and the fix is a control you have to find first.
///
/// In LumiereKit rather than beside the player so the reading and clamping are a
/// pure function with tests — the player itself needs a running engine to build.
public enum PlayerVolume {

    public static let storageKey = "playerVolume"

    /// What a fresh install opens at. Full, as every player does.
    public static let defaultLevel: Double = 1

    /// The remembered level, clamped.
    ///
    /// A preference file is editable by hand, and a stored 40 would be silence
    /// followed by clipping rather than "loud". Read through `object(forKey:)`
    /// rather than `double(forKey:)` because that returns 0 for a missing key,
    /// and 0 is a level someone can genuinely mean — the two have to stay
    /// distinguishable or muting the app once makes it silent for ever.
    public static func remembered(
        in defaults: UserDefaults = .standard
    ) -> Double {
        guard let stored = defaults.object(forKey: storageKey) as? Double else {
            return defaultLevel
        }
        return max(0, min(1, stored))
    }

    public static func remember(_ level: Double, in defaults: UserDefaults = .standard) {
        defaults.set(max(0, min(1, level)), forKey: storageKey)
    }
}

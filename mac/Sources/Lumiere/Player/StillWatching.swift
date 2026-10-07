import Foundation
import LumiereKit

/// "Are you still watching?" — Plex's guard against a season playing to an
/// empty room.
///
/// Counts episodes started by the countdown or by a file ending, with nobody
/// touching anything in between. Past the limit, the countdown does not run
/// and the next episode waits to be asked for. Any key, or pressing the offer
/// itself, starts the count again.
enum StillWatching {
    @MainActor private static var streak = 0

    /// Whether the next episode may start on its own, counting it if so.
    @MainActor static func mayAdvance() -> Bool {
        let limit = Preference.stillWatchingAfter.value
        guard limit == 0 || streak < limit else { return false }
        streak += 1
        return true
    }

    /// Whether the count has run out, without counting anything.
    @MainActor static var isAsking: Bool {
        let limit = Preference.stillWatchingAfter.value
        return limit > 0 && streak >= limit
    }

    @MainActor static func someoneIsHere() { streak = 0 }
}

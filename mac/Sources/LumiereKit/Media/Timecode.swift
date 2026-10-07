import Foundation

/// A duration, written the way a player writes one.
///
/// One implementation because there were five, and they had already diverged into
/// three behaviours: the three music copies were character-identical and dropped
/// hours entirely, the player's rounded, and the detail page's had no guard at all
/// — `Int(Double.nan)` traps in Swift, so a chapter with a non-finite start time
/// crashed there and read "0:00" everywhere else.
///
/// Hours appear only when there are hours, which is what every player does: a
/// 42-minute episode reading "0:42:11" is noise, and a 2-hour film reading "121:04"
/// is a puzzle.
public enum Timecode {

    /// `1:02:03` past an hour, `2:03` under it. Anything not finite reads `0:00`,
    /// because a clock that cannot say where it is should say nothing rather than
    /// take the process down.
    public static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

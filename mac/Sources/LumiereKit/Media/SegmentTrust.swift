import Foundation

/// Which server segments the player believes.
///
/// A segment is a claim, and the detector that made it was wrong often enough
/// to matter: of thirty-six thousand credits segments on this server, most
/// begin in the last two minutes of the file, and fourteen hundred begin four
/// to thirteen minutes before the end — a recurring musical cue mid-episode,
/// read as the ending theme. The player offered Skip Credits at every one of
/// them, five minutes before any credits.
///
/// So credits are trusted only where credits can be: near the end. The window
/// scales with the runtime — a film's credits run long — and never closes
/// tighter than a floor the viewer can set, because how early is "too early"
/// is a taste about their own library.
public enum SegmentTrust {

    /// Credits may begin this far before the end, as a share of the runtime.
    /// Fifteen per cent: three and a half minutes of a twenty-four minute
    /// episode, eighteen of a two-hour film.
    public static let outroShare = 0.15

    /// The floor on that window, in minutes. See `Preference.creditsWindowMinutes`.
    public static let defaultFloorMinutes = 4

    /// Whether a credits segment sits where credits could.
    ///
    /// - Parameters:
    ///   - duration: the file's length in seconds, as the player knows it.
    ///   - floorMinutes: the smallest window allowed, whatever the share says.
    public static func isPlausibleOutro(
        start: Double, end: Double, duration: Double, floorMinutes: Int = defaultFloorMinutes
    ) -> Bool {
        guard duration > 0, end > start else { return false }
        let window = max(duration * outroShare, Double(floorMinutes) * 60)
        // Beginning inside the window is what matters. Ending early is
        // allowed: an ending theme followed by a preview is the common shape,
        // and the segment legitimately stops where the theme does.
        return start >= duration - window
    }
}

/// Whether stopping at `position` counts as having watched the thing.
///
/// Waiting for the last frame left most episodes half-watched: people stop
/// when the credits roll, and Continue Watching then offered forty seconds of
/// end titles as the thing to get back to. Watched once a believable credits
/// segment has begun, or — where there is none — within the last 5% of the file.
public enum WatchedAtCredits {
    public static func counts(
        position: Double, duration: Double,
        outroStarts: [(start: Double, end: Double)], floorMinutes: Int
    ) -> Bool {
        guard duration > 0, position > 0 else { return false }
        let credits = outroStarts
            .filter { SegmentTrust.isPlausibleOutro(start: $0.start, end: $0.end,
                                                    duration: duration, floorMinutes: floorMinutes) }
            .map(\.start).min()
        if let credits { return position >= credits }
        return position >= duration * 0.95
    }
}

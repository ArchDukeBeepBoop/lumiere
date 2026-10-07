import Foundation

/// The one thing a detail page should say before anything else.
///
/// A partly-watched series opened on a synopsis you read before you started it.
/// The fact that matters by then is where you are — "You are on episode 7 of
/// 24" — and it was nowhere on the page: the number of unwatched episodes was a
/// clause in a metadata line, between the year and the genres.
///
/// Pure, and stated only when it is true. A page that shows a progress sentence
/// for something never started is worse than one that shows none, because the
/// sentence is then furniture rather than information.
public enum DominantFact {

    /// Where you are in a season.
    ///
    /// - Parameters:
    ///   - episodes: the season's episodes, in order.
    /// - Returns: nil for a season not started, or one finished — neither has a
    ///   "where you are" to report.
    public static func seasonProgress(episodes: [LibraryEntry]) -> String? {
        guard episodes.count > 1 else { return nil }
        let watched = episodes.filter { $0.isPlayed }.count
        guard watched > 0 else { return nil }
        guard watched < episodes.count else { return nil }

        // The next unwatched episode, which is the one being asked about — not
        // the count of watched ones, which is a different question with the same
        // arithmetic and the wrong answer whenever a season is watched out of
        // order.
        guard let nextIndex = episodes.firstIndex(where: { !$0.isPlayed }) else {
            return nil
        }
        return "You are on episode \(nextIndex + 1) of \(episodes.count)"
    }

    /// How much of a film is left, for one part way through.
    ///
    /// Minutes, not a percentage: "38 minutes left" answers whether it fits
    /// before bed, which is the question actually being asked.
    public static func filmRemaining(
        runtimeSeconds: Double?, resumeSeconds: Double
    ) -> String? {
        guard let runtimeSeconds, runtimeSeconds > 0, resumeSeconds > 60 else {
            return nil
        }
        let remaining = runtimeSeconds - resumeSeconds
        // Under two minutes is finished in every sense that matters.
        guard remaining > 120 else { return nil }
        let minutes = Int((remaining / 60).rounded())
        if minutes < 60 { return "\(minutes) minutes left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? "\(hours) hour\(hours == 1 ? "" : "s") left"
            : "\(hours) hr \(rest) min left"
    }
}

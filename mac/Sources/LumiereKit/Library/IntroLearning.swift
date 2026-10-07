import Foundation

/// One learned intro, for a series the server has no segments for.
public struct IntroSkip: Sendable, Equatable {
    public let start: Double
    public let end: Double
    /// How many times this has been seen. The offer waits for agreement rather
    /// than acting on one skip — see `minimumSamples`.
    public let samples: Int

    public init(start: Double, end: Double, samples: Int) {
        self.start = start
        self.end = end
        self.samples = samples
    }
}

/// Learning where a series' intro is from where you actually skip.
///
/// Most servers have no segment plugin, so "Skip Intro" never appears for the
/// shows that need it most — and the offset is the same in every episode of a
/// season, so skipping it by hand is the same drag, twelve times.
///
/// Pure, and the reason is that every rule here is a judgement about noisy input:
/// what counts as an intro skip rather than an ordinary seek, when two skips are
/// the same skip, and how much agreement is enough to act on. Those are testable
/// facts about numbers, and they should not need a player to check.
public enum IntroLearning {

    /// How far into a file an intro can begin.
    ///
    /// Five minutes. Long enough for a cold open — anime routinely runs two
    /// minutes of story before the OP — and short enough that skipping forward
    /// in the middle of an episode is never mistaken for one.
    public static let latestStart: Double = 300

    /// The shortest and longest a skip can be and still be an intro.
    ///
    /// An opening is 60 to 105 seconds almost universally; the bounds are wider
    /// than that on both sides for recaps and for shows that run the OP long.
    public static let shortestSkip: Double = 20
    public static let longestSkip: Double = 210

    /// How close two skips must be to count as the same one.
    ///
    /// Ten seconds. Nobody releases the scrubber in the same place twice, and
    /// two skips fifteen seconds apart are two guesses at one intro rather than
    /// two different intros.
    public static let tolerance: Double = 10

    /// How much agreement is needed before the offer appears.
    ///
    /// Two. One skip is an action; two in the same place is a pattern — and
    /// offering after a single one would put a wrong button on every show where
    /// somebody once jumped past a slow scene.
    public static let minimumSamples = 2

    /// Whether a seek looks like someone skipping an intro.
    public static func isIntroSkip(from: Double, to: Double) -> Bool {
        guard from >= 0, from <= latestStart, to > from else { return false }
        let length = to - from
        return length >= shortestSkip && length <= longestSkip
    }

    /// Folds a new observation into what is already known about a series.
    ///
    /// Returns what should be stored now. The rules, in order:
    ///
    /// - Nothing known yet: the sample becomes the estimate, with one sample.
    /// - It agrees with the estimate: average them and count it. Averaging
    ///   rather than replacing is what makes the window converge on the real
    ///   boundary instead of tracking the last place someone happened to let go.
    /// - It disagrees and the estimate is still a guess (one sample): replace
    ///   it. A single observation has no standing to outvote a fresh one.
    /// - It disagrees and the estimate is established: keep the estimate. One
    ///   odd skip in episode nine should not throw away what the first eight
    ///   agreed on.
    public static func merge(_ known: IntroSkip?, from: Double, to: Double) -> IntroSkip {
        guard let known else { return IntroSkip(start: from, end: to, samples: 1) }
        let agrees = abs(known.start - from) <= tolerance && abs(known.end - to) <= tolerance
        if agrees {
            let weight = Double(known.samples)
            return IntroSkip(
                start: (known.start * weight + from) / (weight + 1),
                end: (known.end * weight + to) / (weight + 1),
                samples: known.samples + 1
            )
        }
        if known.samples < minimumSamples {
            return IntroSkip(start: from, end: to, samples: 1)
        }
        return known
    }

    /// Whether a learned intro should be offered at this position.
    ///
    /// Offered from a little before its start, because the estimate is an
    /// average and the real boundary moves by a second or two between episodes —
    /// and never once you are past the end of it, when the offer would skip
    /// forward out of the episode you are already watching.
    public static func shouldOffer(_ intro: IntroSkip?, at position: Double) -> Bool {
        guard let intro, intro.samples >= minimumSamples else { return false }
        return position >= intro.start - tolerance && position < intro.end - 1
    }
}

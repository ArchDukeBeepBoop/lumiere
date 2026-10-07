import Foundation

/// Why *this* title is the one on the hero.
///
/// The home screen's shelves all answer "what is in the database". A hero that
/// rotates through recent additions answers the same question in a larger
/// typeface. What turns a picture into a recommendation is a sentence saying why
/// it is there — and a sentence you can only write if the choice was made for a
/// reason in the first place.
///
/// So the reason is not decoration added after the pick: it *is* the pick. The
/// ranking below is the editorial judgement, and the copy is derived from it.
///
/// Pure, and it has to be. Every rule here is a claim about somebody's evening —
/// "you abandoned this", "you are nearly through this season" — and a claim that
/// is wrong is worse than no claim at all. These are facts about numbers and can
/// be checked without a library.
public enum SpotlightReason {

    /// The kinds of case worth featuring, best first.
    ///
    /// Ordered by how much the viewer already has invested. Something you
    /// started and left is a stronger offer than something you have never seen,
    /// however good — you have already decided you wanted it once.
    public enum Kind: Int, Sendable, Comparable {
        /// Started, left unfinished, and long enough ago to have been forgotten.
        case abandoned = 0
        /// A season with only a few episodes to go.
        case nearlyDone = 1
        /// Never opened, and rated higher than anything else that fits.
        case bestUnseen = 2
        /// Nothing to say about it. The rotation's old behaviour, and the
        /// fallback when a library is too new to have a history.
        case none = 3

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Verdict: Sendable, Equatable {
        public let kind: Kind
        /// The line under the title, or nil where there is nothing honest to say.
        public let sentence: String?
    }

    /// How long before an unfinished title counts as abandoned.
    ///
    /// Ten days. Long enough that "I am watching this" has stopped being true,
    /// short enough that the thing is still worth being reminded of.
    public static let forgottenAfter: TimeInterval = 10 * 24 * 60 * 60
    /// The same number, for a sentence.
    public static let forgottenAfterDays = Int(forgottenAfter / 86_400)

    /// How far in counts as started rather than sampled, and how far is too far
    /// to call abandoned rather than nearly finished.
    public static let startedAbove = 0.05
    public static let abandonedBelow = 0.85

    /// The most episodes remaining that still reads as "nearly done".
    public static let nearlyDoneRemaining = 3

    /// The rating below which "best unseen" is not a claim worth making.
    public static let notableRating = 7.5

    /// Judges one candidate.
    public static func verdict(for entry: LibraryEntry, now: Date = Date()) -> Verdict {
        if let sentence = abandonedSentence(entry, now: now) {
            return Verdict(kind: .abandoned, sentence: sentence)
        }
        if let sentence = nearlyDoneSentence(entry) {
            return Verdict(kind: .nearlyDone, sentence: sentence)
        }
        if let sentence = bestUnseenSentence(entry) {
            return Verdict(kind: .bestUnseen, sentence: sentence)
        }
        return Verdict(kind: .none, sentence: nil)
    }

    /// Picks the hero from a pool.
    ///
    /// Best kind first, then — within a kind — the most recently touched for the
    /// two that are about history, and the highest rated for the one that is
    /// not. `tiebreak` rotates between equals so the same title is not featured
    /// every day of the week.
    public static func choose(
        from pool: [LibraryEntry], now: Date = Date(), tiebreak: Int = 0
    ) -> (entry: LibraryEntry, verdict: Verdict)? {
        guard !pool.isEmpty else { return nil }

        let judged = pool.map { (entry: $0, verdict: verdict(for: $0, now: now)) }
        guard let best = judged.map(\.verdict.kind).min() else { return nil }

        let tier = judged.filter { $0.verdict.kind == best }
        let ordered: [(entry: LibraryEntry, verdict: Verdict)]
        switch best {
        case .abandoned, .nearlyDone:
            ordered = tier.sorted {
                ($0.entry.userData?.lastPlayedDate ?? .distantPast)
                    > ($1.entry.userData?.lastPlayedDate ?? .distantPast)
            }
        case .bestUnseen, .none:
            ordered = tier.sorted {
                ($0.entry.item.communityRating ?? 0) > ($1.entry.item.communityRating ?? 0)
            }
        }

        // Rotation applies only among equals. Rotating across kinds would trade
        // the reason away for variety, which is the trade this exists to refuse.
        let width = min(ordered.count, best == .none ? ordered.count : 3)
        guard width > 0 else { return ordered.first }
        return ordered[abs(tiebreak) % width]
    }

    // MARK: - The individual claims

    public static func abandonedSentence(_ entry: LibraryEntry, now: Date) -> String? {
        guard let userData = entry.userData, userData.played != true else { return nil }
        let seconds = userData.resumeSeconds
        guard seconds > 0, let runtime = entry.item.runtimeSeconds, runtime > 0 else { return nil }

        let fraction = seconds / runtime
        guard fraction > startedAbove, fraction < abandonedBelow else { return nil }
        guard let last = userData.lastPlayedDate,
              now.timeIntervalSince(last) > forgottenAfter
        else { return nil }

        return "You stopped \(minutesPhrase(seconds)) in, \(agoPhrase(last, now: now))"
    }

    public static func nearlyDoneSentence(_ entry: LibraryEntry) -> String? {
        guard entry.item.itemType == .series else { return nil }
        guard let remaining = entry.userData?.unplayedItemCount,
              remaining > 0, remaining <= nearlyDoneRemaining
        else { return nil }
        // Only where something has actually been watched. A series with three
        // episodes total and none seen is not "nearly done".
        guard entry.userData?.lastPlayedDate != nil else { return nil }

        return remaining == 1
            ? "One episode left"
            : "\(spelled(remaining)) episodes left"
    }

    public static func bestUnseenSentence(_ entry: LibraryEntry) -> String? {
        guard entry.userData?.lastPlayedDate == nil,
              entry.userData?.played != true,
              let rating = entry.item.communityRating,
              rating >= notableRating
        else { return nil }
        return "Rated \(Rating.text(rating) ?? ""), and you have never opened it"
    }

    // MARK: - Phrasing

    /// "42 minutes", "an hour and 10 minutes". Never "0 minutes".
    public static func minutesPhrase(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourWord = hours == 1 ? "an hour" : "\(hours) hours"
        if rest == 0 { return hourWord }
        return "\(hourWord) and \(rest) minutes"
    }

    /// "three weeks ago", "last month". Vague on purpose: the point is that it
    /// was a while, and a precise date invites arithmetic nobody wants to do.
    public static func agoPhrase(_ date: Date, now: Date) -> String {
        let days = Int(now.timeIntervalSince(date) / (24 * 60 * 60))
        switch days {
        case ..<14: return "\(days) days ago"
        case ..<31: return "\(spelled(days / 7)) weeks ago"
        case ..<62: return "last month"
        case ..<365: return "\(spelled(days / 30)) months ago"
        default: return "over a year ago"
        }
    }

    /// Small numbers read better as words in a sentence.
    public static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten", "eleven"]
        return n < words.count ? words[n] : String(n)
    }
}

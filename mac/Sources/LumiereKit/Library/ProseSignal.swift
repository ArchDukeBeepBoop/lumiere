import Foundation

/// Relating titles by what their synopses are about.
///
/// Split from FranchiseGrouping.swift, which owns the clustering; this owns the one
/// signal that reads English rather than fields. It exists because the strongest
/// link between *Fate/Zero* and *Unlimited Blade Works*, on a server whose tags are
/// empty, is that both synopses are about the Holy Grail War — and the Monogatari
/// entries all describe Koyomi Araragi. The prose says what the metadata does not.
public extension FranchiseGrouping {

    /// Distinctive proper nouns lifted out of a synopsis.
    ///
    /// The signal for franchises the metadata never labelled. *Fate/Zero* and
    /// *Unlimited Blade Works* share no tag on many servers and no word in their
    /// titles, but both synopses are about the Holy Grail War; the Monogatari
    /// entries all describe Koyomi Araragi. The prose says what the fields do not.
    ///
    /// Only multi-word capitalised phrases count. A single capitalised word is
    /// usually a sentence opening or a common noun the scraper capitalised, and
    /// two-word phrases are specific enough to be worth something: "Holy Grail",
    /// "Koyomi Araragi", "Britannian Empire".
    static func proseKeys(in overview: String) -> Set<String> {
        guard overview.count > 40 else { return [] }
        var keys: Set<String> = []
        // Sentence by sentence, so a phrase can never be assembled across a full
        // stop — "…the war. Koyomi returned" must not yield "War Koyomi".
        for sentence in overview.split(whereSeparator: { ".!?\n".contains($0) }) {
            let words = sentence
                .split(whereSeparator: { !$0.isLetter && $0 != "'" })
                .map(String.init)
            var run: [String] = []
            // The first word is *not* skipped, though it is capitalised by grammar:
            // synopses open with the protagonist's name constantly, and dropping it
            // lost "Koyomi Araragi" from every Monogatari entry. The stop-list plus
            // the two-word minimum handle the grammar case instead — "The story…"
            // yields nothing because "The" is filtered and "story" is lowercase.
            for word in words {
                if word.count > 2, word.first?.isUppercase == true, !stopWords.contains(word) {
                    run.append(word)
                } else {
                    if run.count >= 2 { keys.insert(run.joined(separator: " ").lowercased()) }
                    run = []
                }
            }
            if run.count >= 2 { keys.insert(run.joined(separator: " ").lowercased()) }
        }
        return keys
    }

    /// Capitalised words that are grammar rather than names.
    internal static let stopWords: Set<String> = [
        "The", "A", "An", "In", "On", "At", "But", "And", "Or", "However",
        "When", "After", "Before", "While", "Now", "Then", "This", "That",
        "He", "She", "They", "It", "His", "Her", "Their", "One", "Two",
    ]

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}

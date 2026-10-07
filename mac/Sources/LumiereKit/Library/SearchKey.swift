import Foundation

/// How a title is reduced for searching, and how a typed term is matched against it.
///
/// Written after watching real searches fail on a real library. Case was never the
/// problem — SQLite's `LIKE` is already case-insensitive — but three other things
/// were, and each of them looks like the app simply not finding something that is
/// plainly there:
///
/// - **Punctuation.** `Fate/Zero` is one word to a substring match, so typing
///   "fate zero" returns nothing. Nobody types the slash.
/// - **Contiguity.** `LIKE '%term%'` needs the whole phrase in order and adjacent,
///   so "academy sky" misses *Sky Wizards Academy* and "gundam wing" misses
///   *Mobile Suit Gundam Wing*.
/// - **Scope.** Only the item's own name was searched, so an episode could not be
///   found by the show it belongs to.
///
/// Pure and string-only, so the rules are testable without a database.
public enum SearchKey {

    /// Reduces text to lowercase words separated by single spaces.
    ///
    /// Every punctuation mark becomes a space rather than being deleted: removing
    /// them would fuse `Fate/Zero` into "fatezero", which then fails to match the
    /// two words anyone would actually type.
    public static func normalize(_ text: String) -> String {
        let scalars = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// The searchable form of an item: its own name, plus the show it belongs to.
    ///
    /// Both in one string so a single column can answer both questions. An episode
    /// called "The Strongest Traitor" is findable by typing the series name, which
    /// is how people look for episodes.
    /// `alternative` is any other name the same thing goes by — an album for a
    /// track, and for a show the original title. Anime is the case that forces
    /// this: half a library is better known by a romaji or Japanese name that
    /// appears nowhere in the display title.
    public static func key(
        name: String, seriesName: String?, alternative: String? = nil
    ) -> String {
        [name, seriesName, alternative]
            .compactMap { $0 }
            .map(normalize)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The words a term is looking for, in no particular order.
    ///
    /// Every one must appear, which is what makes "academy sky" find *Sky Wizards
    /// Academy* while "sky dog" still finds nothing. An OR would return most of the
    /// library for any two-word query.
    public static func tokens(in term: String) -> [String] {
        normalize(term).split(separator: " ").map(String.init)
    }

    /// Whether a key satisfies a term. The same rule the SQL applies, kept here so
    /// it can be tested directly.
    public static func matches(term: String, key: String) -> Bool {
        let tokens = tokens(in: term)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { key.contains($0) }
    }
}

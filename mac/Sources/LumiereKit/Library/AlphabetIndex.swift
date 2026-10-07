import Foundation

/// Which letter a title files under, and where each letter starts in a list.
///
/// Pulled out of the music browser, where it started, because every long list in
/// the app has the same problem: a library of four thousand titles cannot be
/// scrolled to "S" in reasonable time, and the alternative — typing a filter — only
/// works when you already know what you are looking for. A rail answers "take me to
/// roughly here", which is a different question.
///
/// Pure and string-only, so the letter rules are testable without a view.
public enum AlphabetIndex {

    /// "#" first, then A–Z.
    ///
    /// The bucket for digits and everything outside the Latin alphabet, and on a
    /// real anime library it is not a rounding error: titles beginning with a
    /// number, with a bracket, or in Japanese all land there, and without it they
    /// would be unreachable from the rail entirely.
    public static let letters: [String] = ["#"] + (65...90).map { String(UnicodeScalar($0)!) }

    /// The letter a sort key belongs under.
    ///
    /// Takes the *sort* key rather than the display name deliberately. The sort key
    /// has leading articles stripped, so "The Beatles" files under B — and jumping
    /// to T for a row that sits under B is worse than having no rail at all.
    public static func letter(forSortKey key: String, fallback name: String = "") -> String {
        let source = key.isEmpty ? name : key
        guard let first = source.uppercased().unicodeScalars.first else { return "#" }
        guard CharacterSet.uppercaseLetters.contains(first) else { return "#" }
        return String(first)
    }

    /// The first id filed under each letter, for a list already in sort order.
    ///
    /// Built in one pass and handed back as a map, rather than searched per letter:
    /// a rail asks twenty-seven questions every time it draws, and on a list of
    /// 4,000 that is 108,000 comparisons a frame for an answer that does not change
    /// until the list does.
    public static func firstIds<Item>(
        in items: [Item],
        id: (Item) -> String,
        sortKey: (Item) -> String,
        name: (Item) -> String = { _ in "" }
    ) -> [String: String] {
        var found: [String: String] = [:]
        for item in items {
            let key = letter(forSortKey: sortKey(item), fallback: name(item))
            if found[key] == nil { found[key] = id(item) }
        }
        return found
    }
}

import Foundation

/// Which libraries feed the whole-library Recently Added row.
///
/// Three kinds are kept out by default, for three reasons. A *folder* library —
/// one the server was never told is films or shows, so it holds files rather
/// than titles — because a row of untitled clips is not what "recently added"
/// is for. A *private* library, whether or not it is currently revealed — the
/// same rule the Top 10 rows apply: revealing means "let me browse it", never
/// "put it on the front page". And an *adult* library, by name, because that is
/// the content people least want surfacing on a home screen that is glanced at
/// from across the room, and marking it private is not something everyone has
/// done.
///
/// The user's own choice wins over all of this. Once a library has been
/// explicitly included or excluded in Settings, that is the answer; the
/// defaults only decide the ones nobody has decided.
///
/// Pure, so the merge of defaults and choices can be tested.
public enum RecentlyAddedPolicy {

    public static let storageKey = "recentlyAddedLibraryChoices"

    /// Names that mark a library as adult without anyone having said so in
    /// Settings. Substring and case-insensitive, like `LibraryKinds.isAnime`.
    static let adultMarkers = ["adult", "xxx", "nsfw"]

    public static func isAdult(_ name: String) -> Bool {
        adultMarkers.contains { name.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// The stored form: `id=1` included, `id=0` excluded, comma-separated.
    /// Anything not mentioned falls to the defaults.
    public static func choices(from stored: String?) -> [String: Bool] {
        guard let stored, !stored.isEmpty else { return [:] }
        var out: [String: Bool] = [:]
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            out[String(parts[0])] = parts[1] == "1"
        }
        return out
    }

    public static func store(_ choices: [String: Bool]) -> String {
        choices.keys.sorted().map { "\($0)=\(choices[$0] == true ? "1" : "0")" }
            .joined(separator: ",")
    }

    /// Whether a library would be left out with nothing said about it.
    public static func excludedByDefault(
        _ library: LibraryRecord, privateIds: Set<String>
    ) -> Bool {
        library.collectionType == nil
            || privateIds.contains(library.id)
            || isAdult(library.name)
    }

    /// The libraries to leave out, given everything.
    public static func excluded(
        libraries: [LibraryRecord], privateIds: Set<String>, stored: String?
    ) -> Set<String> {
        let chosen = choices(from: stored)
        return Set(libraries.filter { library in
            if let choice = chosen[library.id] { return !choice }
            return excludedByDefault(library, privateIds: privateIds)
        }.map(\.id))
    }
}

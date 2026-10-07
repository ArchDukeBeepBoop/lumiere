import Foundation

/// Finds franchises in the names of things, for the libraries where the metadata
/// simply is not there.
///
/// The companion to `FranchiseGrouping`, which deliberately ignores titles because
/// *Code Geass* and *Akito the Exiled* share no word. This is the opposite half of
/// the same problem and just as real: on a library the scraper never matched, there
/// are no tags, no credits and no synopses to relate anything by — but the folders
/// say `Bakemonogatari`, `Nisemonogatari`, `Owarimonogatari`, and a person reading
/// that list has no doubt at all what belongs together.
///
/// So this looks for a distinctive *stem* shared across names. Not a prefix, which
/// is what most title matchers use and which finds nothing here — `Bake` and `Nise`
/// share no prefix. The stem "monogatari" sits at the end of one, the end of
/// another, and the middle of `Monogatari Series Second Season`.
///
/// Pure and string-only, so it is testable without a server or a database.
public enum FilenameFranchise {

    /// A franchise found in a set of names.
    public struct Group: Sendable, Identifiable, Hashable {
        /// The stem, title-cased — "Monogatari", "Fate", "Tenchi Muyo".
        public let name: String
        public let itemIds: [String]
        public let reason: String

        public var id: String { name + "|" + itemIds.joined(separator: ",") }
    }

    /// One title as this needs to see it.
    public struct Candidate: Sendable, Hashable {
        public let id: String
        public let name: String
        /// The file's path, whose folder names are often cleaner than the title the
        /// scraper settled on — a mismatched series keeps its folder.
        public let path: String?

        public init(id: String, name: String, path: String? = nil) {
            self.id = id
            self.name = name
            self.path = path
        }
    }

    /// A stem must be at least this long to count.
    ///
    /// Six characters, which is high on purpose. "Fate" is four and is handled as a
    /// whole word below; the long-stem path exists for the compound-word case —
    /// "monogatari", "gundam", "precure" — where a short stem would match noise.
    private static let minimumStemLength = 6

    /// A franchise of more than this many titles is a genre in disguise.
    public static let maximumGroupSize = 20

    /// Words that appear across half a library and relate nothing.
    private static let noise: Set<String> = [
        "season", "series", "movie", "movies", "film", "the", "and", "special",
        "specials", "complete", "collection", "batch", "bluray", "bd", "web",
        "dvd", "1080p", "720p", "480p", "2160p", "hevc", "x264", "x265", "aac",
        "flac", "dual", "audio", "subs", "eng", "jpn", "part", "vol", "ova",
        "anime", "uncensored", "remux", "repack",
    ]

    /// Groups candidates by the strongest name they share.
    public static func groups(
        from candidates: [Candidate],
        maximumGroupSize: Int = maximumGroupSize
    ) -> [Group] {
        guard candidates.count > 1 else { return [] }

        // key → ids. Two kinds of key, gathered together and filtered the same way.
        var byKey: [String: Set<String>] = [:]
        for candidate in candidates {
            for word in words(in: candidate) where !noise.contains(word) && word.count >= 3 {
                byKey[word, default: []].insert(candidate.id)
            }
            for stem in stems(in: candidate) {
                byKey[stem, default: []].insert(candidate.id)
            }
        }

        let usable = byKey.filter { $0.value.count >= 2 && $0.value.count <= maximumGroupSize }
        guard !usable.isEmpty else { return [] }

        // Each title joins the largest franchise that claims it, so an entry that
        // matches both "fate" and "stay" lands in Fate rather than splitting the
        // franchise across two half-groups.
        var claimed: [String: String] = [:]
        for (key, ids) in usable.sorted(by: { larger($0, $1) }) {
            for id in ids where claimed[id] == nil {
                claimed[id] = key
            }
        }

        var members: [String: [String]] = [:]
        for (id, key) in claimed { members[key, default: []].append(id) }

        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return members
            .filter { $0.value.count >= 2 }
            .map { key, ids in
                let titles = ids.compactMap { byId[$0] }.sorted { $0.name < $1.name }
                return Group(
                    name: titleCased(key),
                    itemIds: titles.map(\.id),
                    reason: "\(titles.count) titles share \"\(key)\""
                )
            }
            .sorted { $0.itemIds.count == $1.itemIds.count
                ? $0.name < $1.name
                : $0.itemIds.count > $1.itemIds.count }
    }

    /// Bigger first, then longer key, then alphabetical — so the order is stable and
    /// the more specific key wins a tie.
    private static func larger(
        _ left: (key: String, value: Set<String>),
        _ right: (key: String, value: Set<String>)
    ) -> Bool {
        if left.value.count != right.value.count { return left.value.count > right.value.count }
        if left.key.count != right.key.count { return left.key.count > right.key.count }
        return left.key < right.key
    }

    /// Whole words from the title and from the folder above the file.
    ///
    /// The folder matters: a series the scraper mismatched keeps its own directory
    /// name, which is very often the only correct name anywhere in the system.
    static func words(in candidate: Candidate) -> Set<String> {
        var sources = [candidate.name]
        if let path = candidate.path {
            let parts = path.split(separator: "/").map(String.init)
            // The containing folder and its parent, not the whole path — "Anime"
            // and "Volumes" are on every path and relate everything to everything.
            if parts.count >= 2 { sources.append(parts[parts.count - 2]) }
            if parts.count >= 3 { sources.append(parts[parts.count - 3]) }
        }
        return Set(
            sources
                .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }
                .map(String.init)
        )
    }

    /// Long stems shared inside compound words.
    ///
    /// The Monogatari case, and the reason a prefix matcher fails here: the shared
    /// part is a *suffix* of `Bakemonogatari` and a *prefix* of `Monogatari Series`.
    /// Every substring of six characters or more is offered as a key; the size cap
    /// and the noise list throw away the ones that mean nothing.
    static func stems(in candidate: Candidate) -> Set<String> {
        var found: Set<String> = []
        for word in words(in: candidate) where word.count > minimumStemLength {
            let characters = Array(word)
            // Only stems that reach the end of the word. A franchise name is a whole
            // morpheme — "monogatari", "gatari" — where an arbitrary interior slice
            // is noise, and offering every substring is O(n²) keys per title.
            for start in 0...(characters.count - minimumStemLength) {
                found.insert(String(characters[start...]))
            }
        }
        return found
    }

    private static func titleCased(_ value: String) -> String {
        value.split(separator: " ")
            .map { $0.count <= 2 ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

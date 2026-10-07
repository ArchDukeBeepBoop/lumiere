import Foundation

/// One title, reduced to the metadata that says what it is related to.
///
/// Built from a server query rather than the cache: tags, studios and credits are
/// not columns in `ItemRecord` — caching them for 44,000 rows would cost far more
/// than the one request per library this needs.
public struct RelationCandidate: Sendable, Hashable {
    public let id: String
    public let name: String
    /// Jellyfin/TMDB keyword tags. The strongest signal there is: a franchise
    /// keyword is exactly what a tag is for.
    public let tags: [String]
    /// Credits worth relating on — the original creator or writer. Not the whole
    /// cast, which for anime is a voice pool shared across half a library.
    public let creators: [String]
    public let studios: [String]
    /// The synopsis. Read for the proper nouns in it, never displayed from here.
    public let overview: String
    /// The file on disk, whose folder names survive a mismatched scrape.
    public let path: String?

    public init(
        id: String,
        name: String,
        tags: [String],
        creators: [String],
        studios: [String],
        overview: String = "",
        path: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tags = tags
        self.creators = creators
        self.studios = studios
        self.overview = overview
        self.path = path
    }
}

/// Finds titles that belong together, without looking at their titles.
///
/// The problem this exists for: an anime library's franchises are not discoverable
/// by name. *Code Geass* and *Akito the Exiled* share no words. Neither do *Gundam*
/// and *Iron-Blooded Orphans*' Japanese release titles, or the Fate entries, or
/// most of a adult library, where the same original work ships under a different
/// title every time. Anything matching on string similarity finds sequels and
/// misses franchises — the opposite of useful.
///
/// So nothing here reads a name except to label the result. Relation is a shared
/// *tag*, a shared *original creator*, and — only as corroboration, never alone —
/// a shared studio. That is the metadata Jellyfin already holds, so a group found
/// here is one the server could justify.
///
/// Pure: no repository, no network. The caller fetches the candidates.
public enum FranchiseGrouping {

    // `Group` lives in FranchiseGroup.swift.

    /// A key covering more than this many titles is describing a genre, not a
    /// franchise — "anime", "based on manga", "japan", or a studio's whole output.
    /// Twelve is generous for a franchise and far below what the noisy keys reach.
    public static let maximumGroupSize = 12

    /// Groups `candidates` by shared metadata.
    ///
    /// Every key that covers between 2 and `maximumGroupSize` titles is a candidate
    /// cluster; clusters that overlap merge, since two entries sharing a tag *and* a
    /// creator are the same franchise described twice. Studios never form a cluster
    /// on their own — one studio's catalogue is not a collection — but a studio
    /// shared across an already-related pair is left in the reason as corroboration.
    public static func groups(
        from candidates: [RelationCandidate],
        maximumGroupSize: Int = maximumGroupSize
    ) -> [Group] {
        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        // key → the titles carrying it, for the two signals allowed to form a group.
        var clusters: [Key: Set<String>] = [:]
        for candidate in candidates {
            for tag in candidate.tags where isMeaningful(tag) {
                clusters[Key(kind: .tag, value: normalized(tag)), default: []].insert(candidate.id)
            }
            for creator in candidate.creators where isMeaningful(creator) {
                clusters[Key(kind: .creator, value: normalized(creator)), default: []]
                    .insert(candidate.id)
            }
            for phrase in proseKeys(in: candidate.overview) {
                clusters[Key(kind: .prose, value: phrase), default: []].insert(candidate.id)
            }
        }

        let usable = clusters.filter { $0.value.count >= 2 && $0.value.count <= maximumGroupSize }
        guard !usable.isEmpty else { return [] }

        // Merge overlapping clusters: one franchise usually shows up as several keys.
        var merged = DisjointSet(elements: candidates.map(\.id))
        for (_, members) in usable {
            var iterator = members.makeIterator()
            guard let first = iterator.next() else { continue }
            while let next = iterator.next() { merged.union(first, next) }
        }

        // Rebuild groups from the merged sets, keeping only what a key vouched for.
        var byRoot: [String: Set<String>] = [:]
        for (_, members) in usable {
            for member in members {
                byRoot[merged.find(member), default: []].insert(member)
            }
        }

        return byRoot.values
            .filter { $0.count >= 2 && $0.count <= maximumGroupSize }
            .map { members in
                let titles = members.compactMap { byId[$0] }
                return Group(
                    name: label(for: members, usable: usable, candidates: byId),
                    // Sorted by name so the same library always proposes the same
                    // group in the same order — a suggestion list that reshuffles
                    // between runs is one nobody trusts.
                    itemIds: titles.sorted { $0.name < $1.name }.map(\.id),
                    reason: reason(for: members, usable: usable, candidates: byId)
                )
            }
            // Biggest first — the franchises worth making a collection of — with
            // ties broken by name so the order is stable across runs.
            .sorted { $0.itemIds.count == $1.itemIds.count
                ? $0.name < $1.name
                : $0.itemIds.count > $1.itemIds.count }
    }

    // MARK: - Keys

    private struct Key: Hashable {
        enum Kind { case tag, creator, prose }
        let kind: Kind
        let value: String
    }

    /// Filters the keys that describe everything and therefore relate nothing.
    ///
    /// Deliberately short: the size cap above does most of the work, and a long
    /// stop-list would be a second thing to keep correct per library. These are the
    /// ones that appear on almost every title in an anime library specifically, and
    /// would otherwise survive the cap on a small library.
    private static func isMeaningful(_ value: String) -> Bool {
        let key = normalized(value)
        guard key.count > 2 else { return false }
        return !Self.tooBroad.contains(key)
    }

    private static let tooBroad: Set<String> = [
        "anime", "animation", "based on manga", "based on a manga", "based on novel",
        "based on light novel", "based on video game", "japan", "japanese",
        "adult", "ova", "anime series",
    ]

    /// Names the group after the key that covers the most of it, which is the one
    /// most likely to be the franchise rather than an incidental overlap.
    private static func label(
        for members: Set<String>,
        usable: [Key: Set<String>],
        candidates: [String: RelationCandidate]
    ) -> String {
        let best = usable
            .filter { !$0.value.isDisjoint(with: members) }
            .max { lhs, rhs in
                let left = lhs.value.intersection(members).count
                let right = rhs.value.intersection(members).count
                // Tags beat credits at equal coverage: a tag names the franchise,
                // a creator names a person who happened to make all of it.
                if left == right { return rank(lhs.key.kind) < rank(rhs.key.kind) }
                return left < right
            }
        guard let best else { return "Related" }
        return displayName(for: best.key, members: members, candidates: candidates)
    }

    /// Which key gets to name a group when several cover it equally.
    ///
    /// A tag names the franchise outright. A phrase from the synopsis names what the
    /// entries are *about* — "Holy Grail War" — which is a better shelf title than
    /// the person who happened to write all of them.
    private static func rank(_ kind: Key.Kind) -> Int {
        switch kind {
        case .tag: return 2
        case .prose: return 1
        case .creator: return 0
        }
    }

    /// The original casing, recovered from whichever title carries it — the keys are
    /// lowercased for matching, and "fate" is not what anyone wants on a shelf.
    private static func displayName(
        for key: Key,
        members: Set<String>,
        candidates: [String: RelationCandidate]
    ) -> String {
        // A prose key exists only in lowercase — it was assembled from the synopsis
        // rather than lifted from a field — so there is no original casing to
        // recover and it goes straight to title case.
        guard key.kind != .prose else { return titleCased(key.value) }

        let values = members.compactMap { candidates[$0] }.flatMap {
            key.kind == .tag ? $0.tags : $0.creators
        }
        let original = values.first { normalized($0) == key.value } ?? key.value
        // TMDB keywords arrive entirely lowercase — "code geass" — and a collection
        // called that looks like a bug. A name the server capitalised itself, which
        // is every person's name, is left exactly as it came.
        return original == original.lowercased() ? titleCased(original) : original
    }

    private static func titleCased(_ value: String) -> String {
        value.split(separator: " ")
            .map { word in
                // Two letters or fewer stay down: "Fate stay night" reads better
                // than "Fate Stay Night" only by accident, but "of" and "no" as
                // "Of" and "No" is wrong every time.
                word.count <= 2 ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func reason(
        for members: Set<String>,
        usable: [Key: Set<String>],
        candidates: [String: RelationCandidate]
    ) -> String {
        let shared = usable
            .filter { $0.value.isSuperset(of: members) }
            .map { displayName(for: $0.key, members: members, candidates: candidates) }
            .sorted()

        let titles = members.compactMap { candidates[$0] }
        let studioKeys = titles
            .map { Set($0.studios.map(normalized)) }
            .reduce(nil as Set<String>?) { $0?.intersection($1) ?? $1 } ?? []
        // Back to the casing the server sent, so a reason reads "Shaft" and not
        // the lowercased key matching happens to use.
        let studio = studioKeys.sorted().first.flatMap { key in
            titles.flatMap(\.studios).first { normalized($0) == key }
        }

        var parts: [String] = []
        if !shared.isEmpty { parts.append(shared.joined(separator: ", ")) }
        // Corroboration only — a shared studio never formed this group, it just
        // makes a proposal easier to believe or to reject at a glance.
        if let studio { parts.append("same studio (\(studio))") }
        return parts.isEmpty ? "related metadata" : parts.joined(separator: " · ")
    }
}

/// Union-find, so overlapping clusters merge in near-linear time rather than by
/// repeatedly re-scanning the whole set.
private struct DisjointSet {
    private var parent: [String: String]

    init(elements: [String]) {
        parent = Dictionary(uniqueKeysWithValues: elements.map { ($0, $0) })
    }

    mutating func find(_ element: String) -> String {
        var root = element
        while let next = parent[root], next != root { root = next }
        // Path compression, so a long chain costs its length once rather than
        // every time it is walked.
        var current = element
        while let next = parent[current], next != root {
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ lhs: String, _ rhs: String) {
        let left = find(lhs), right = find(rhs)
        if left != right { parent[left] = right }
    }
}

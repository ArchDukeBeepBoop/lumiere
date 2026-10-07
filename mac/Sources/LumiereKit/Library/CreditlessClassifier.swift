import Foundation

/// Recognises creditless openings and endings — NCOP, NCED, textless, clean —
/// and decides where they sit in a season.
///
/// These are the files a BD rip carries alongside the episodes: the opening and
/// ending without the credits burned over them. Two things go wrong with them here,
/// and both were confirmed against the real library rather than guessed at:
///
/// 1. **They sort to the front.** A creditless file has no season or episode number,
///    and the episode sort key is season-then-episode, so a null pair collates as
///    `00000000` — ahead of episode 1. Opening a season played the creditless
///    opening first and Next Episode walked through all of them before reaching the
///    show. 85 files sit under a season like this.
/// 2. **Or they are unreachable entirely.** 38 more, across 17 series, are filed at
///    the series root with no season at all. Nothing in the app lists them: the
///    season view reads a season's children, and these are children of nothing.
///
/// So this puts them where they belong — at the end of the run they came with, in
/// the order they were made — and lets the ones with no season join the first one.
/// A season then plays through and finishes with its creditless versions, which is
/// what opening the folder in VLC does.
///
/// Pure and string-only, so it is testable without a server or a database.
public enum CreditlessClassifier {

    /// What kind of creditless material a file is, which is also its running order:
    /// the opening comes before the ending, as it does in an episode.
    public enum Kind: Int, Sendable, Comparable {
        case opening = 0
        case ending = 1
        /// Creditless by folder or phrase, without saying which. Sorts last.
        case other = 2

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The token prefixes that name creditless material outright.
    ///
    /// Only the two that are actually conventions. Shorter stems — "nco", "nce" —
    /// were considered and dropped: they buy nothing on a real library and every
    /// character removed from a prefix widens what it can collide with.
    private static let openingTokens = ["ncop"]
    private static let endingTokens = ["nced"]

    /// Phrases that mean the same thing spelled out, matched anywhere in the name or
    /// in a folder along the path.
    private static let phrases = [
        "creditless", "textless", "non-credit", "noncredit",
        "clean opening", "clean ending", "clean op", "clean ed",
    ]

    /// Folder names whose contents are creditless regardless of what the files are
    /// called — a `Creditless/` directory of `OP1.mkv`, `ED1.mkv`.
    private static let folders: Set<String> = ["creditless", "textless", "nc", "ncopnced"]

    /// Whether this is a creditless opening or ending.
    ///
    /// Token-matched, never substring-matched, and that distinction is the whole
    /// reason this is a function rather than a `LIKE '%nced%'`: the real library
    /// contains *Minced Meat Cutlet*, *While Visions of Safta Danced*, *The
    /// Silenced Children* and *Sentenced to Be a Hero*. Every one of them contains
    /// "nced". None of them is an ending.
    public static func isCreditless(name: String, path: String? = nil) -> Bool {
        kind(name: name, path: path) != nil
    }

    /// The kind, or nil when this is ordinary content.
    public static func kind(name: String, path: String? = nil) -> Kind? {
        let lowered = name.lowercased()
        if phrases.contains(where: lowered.contains) {
            return spelledOutKind(lowered) ?? .other
        }

        for token in tokens(in: name) {
            if matches(token, anyOf: openingTokens) { return .opening }
            if matches(token, anyOf: endingTokens) { return .ending }
        }

        if let path, inCreditlessFolder(path) {
            return spelledOutKind(lowered) ?? .other
        }
        return nil
    }

    /// A number where the file carries one — NCOP2, "NCED 01" — so several openings
    /// of one show keep their own order rather than falling back to the title.
    public static func number(in name: String) -> Int {
        let parts = tokens(in: name)
        for (index, token) in parts.enumerated() {
            guard matches(token, anyOf: openingTokens) || matches(token, anyOf: endingTokens)
            else { continue }
            // Attached first — "NCOP2" — then the next token, which is how a space
            // separated "NCOP 01" arrives.
            let trailing = token.drop { !$0.isNumber }
            if !trailing.isEmpty, let value = Int(trailing) { return value }
            if index + 1 < parts.count, let value = Int(parts[index + 1]) { return value }
            return 0
        }
        return 0
    }

    /// Moves a season's creditless files to the end, in opening-then-ending order,
    /// and leaves everything else exactly as it was.
    ///
    /// A stable partition rather than a sort: the episodes arrive in the order the
    /// caller established, and re-sorting them here would silently take that
    /// decision away from whoever made it.
    public static func ordered(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        ordered(entries, framing: Preference.framesEpisodes.value)
    }

    /// - Parameter framing: openings *before* the episodes and endings *after*,
    ///   so a season's run — and the player's previous/next chain, which walks
    ///   this same list — plays the way the show did: OP, the episodes, ED.
    ///   Off, every creditless file goes to the end together, which is where
    ///   supplements went before anyone asked.
    public static func ordered(_ entries: [LibraryEntry], framing: Bool) -> [LibraryEntry] {
        var episodes: [LibraryEntry] = []
        var creditless: [(entry: LibraryEntry, kind: Kind, number: Int)] = []

        for entry in entries {
            if let kind = kind(name: entry.item.name, path: entry.item.path) {
                creditless.append((entry, kind, number(in: entry.item.name)))
            } else {
                episodes.append(entry)
            }
        }
        guard !creditless.isEmpty else { return entries }

        creditless.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.entry.item.name < rhs.entry.item.name
        }
        guard framing else { return episodes + creditless.map(\.entry) }
        let openings = creditless.filter { $0.kind == .opening }.map(\.entry)
        let rest = creditless.filter { $0.kind != .opening }.map(\.entry)
        return openings + episodes + rest
    }

    // MARK: - Matching

    /// Splits on everything that is not a letter or a digit, so bracketed release
    /// tags and underscore-separated fansub names both break into real words.
    private static func tokens(in name: String) -> [String] {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// A token matches when it *begins* with the marker and the rest is digits.
    /// "ncop", "ncop2", "nced01" match; "minced", "silenced", "sentenced" do not,
    /// because the marker is in the middle of them rather than at the start.
    private static func matches(_ token: String, anyOf markers: [String]) -> Bool {
        for marker in markers where token.hasPrefix(marker) {
            let rest = token.dropFirst(marker.count)
            if rest.isEmpty || rest.allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    private static func spelledOutKind(_ lowered: String) -> Kind? {
        // Checked in this order because "opening" and "ending" both appear in
        // "opening and ending" reels; the first named wins, which matches how such
        // a file plays.
        let openingAt = lowered.range(of: "opening")?.lowerBound
            ?? lowered.range(of: " op")?.lowerBound
        let endingAt = lowered.range(of: "ending")?.lowerBound
            ?? lowered.range(of: " ed")?.lowerBound

        switch (openingAt, endingAt) {
        case let (open?, end?): return open <= end ? .opening : .ending
        case (_?, nil): return .opening
        case (nil, _?): return .ending
        case (nil, nil): return nil
        }
    }

    /// Directory components only. A show genuinely called "Textless" would otherwise
    /// classify every one of its episodes.
    private static func inCreditlessFolder(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else { return false }
        return components.dropLast().contains { component in
            let name = component.lowercased()
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
            return folders.contains(name)
        }
    }
}

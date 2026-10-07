import Foundation

/// The title a file's own folder claims, for seeding a metadata search.
///
/// Identify used to open with the *scraped* name in its search box, which is the
/// one name that is certainly wrong when the scrape is what you are there to fix:
/// `Hataraku Maou-sama!` had been matched as "The Devil Is a Part-Timer!", so
/// searching for it found the same wrong show again. The folder said the right
/// thing the whole time.
///
/// The cleaning rules are the ones `FilenameEpisodeRepair` and `FilenameFranchise`
/// already learned from this library — a year in brackets after the name, fansub
/// groups in square brackets, `Season 2` and `Extras` sitting between the file and
/// the folder that names it. They are gathered here rather than reused from those
/// types because those two answer different questions: `arcName` deliberately
/// keeps a whole folder name including its release tags, since it only ever
/// compares folders with each other, and a search box needs the opposite.
///
/// Pure and string-only, so it is testable against real paths without a server.
public enum PathTitleGuess {

    /// What to type into a metadata search for this item.
    ///
    /// Falls back to the name the caller already had. A path that cleans down to
    /// nothing — a file loose at the root of a volume — must not leave the search
    /// box empty, which would be strictly worse than a wrong name.
    public static func query(path: String?, isFolder: Bool, fallback: String) -> String {
        title(path: path, isFolder: isFolder) ?? fallback
    }

    /// The cleaned folder name, or nil when the path offers nothing usable.
    public static func title(path: String?, isFolder: Bool) -> String? {
        guard let raw = path, !raw.isEmpty else { return nil }
        let components = raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { return nil }

        // A folder item — a Series, a Season, a BoxSet — *is* its last component.
        // A file is named by the directory above it.
        var index = isFolder ? components.count - 1 : components.count - 2

        // Walk up past the folders that describe a position rather than a title.
        // `Sky Wizards Academy/Extras/[Judas] NCOP #01.mkv` and `FBI (2018)/Season
        // 4/FBI - 4x01 - ….mkv` both name the show one level further up, and an
        // Identify seeded with "Extras" or "Season 4" is no better than one seeded
        // with the wrong title.
        //
        // Never past index 1: index 0 is the volume ("Volumes") and 1 is the disk
        // name, and neither is anybody's title.
        while index > 1, isStructural(components[index]) {
            index -= 1
        }
        guard index >= 0, index < components.count else { return nil }

        let cleaned = clean(components[index])
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Structural folders

    /// Folder names that place a file rather than name it.
    ///
    /// The extras list is `ExtrasClassifier`'s, which was already narrowed against
    /// this library — `specials` is deliberately absent from it because 519 rows
    /// there are real episodes, and that reasoning holds just as well here: a
    /// folder called `Specials` sits beside `Season 1` under a show whose name is
    /// what we are after either way, so it is added back only in the season family
    /// below, where the walk-up is the right answer regardless.
    private static let structuralNames: Set<String> = [
        "extras", "extra", "bonus", "bonus disc", "bonusdisc",
        "featurettes", "featurette", "behind the scenes", "behindthescenes",
        "deleted scenes", "deletedscenes", "interviews", "interview",
        "trailers", "trailer", "samples", "sample",
        "special features", "specialfeatures", "making of", "makingof",
        "specials", "season 0", "subs", "subtitles",
    ]

    /// Whether a folder places rather than names — `Season 4`, `S02`, `Extras`,
    /// `Disc 2`, `Part 1`.
    static func isStructural(_ component: String) -> Bool {
        let lowered = component.lowercased().trimmingCharacters(in: .whitespaces)
        if structuralNames.contains(lowered) { return true }

        // "season 4", "season 4 2nd-cour", "disc 2", "part 1", "cd1", "vol 3".
        for prefix in ["season", "disc", "disk", "cd", "part", "vol", "volume"] {
            guard lowered.hasPrefix(prefix) else { continue }
            let rest = lowered.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
            if let first = rest.first, first.isNumber { return true }
        }

        // "s01", "s2" — but not "s.p.e.c.i.a.l." or a show whose name starts with s.
        if lowered.hasPrefix("s"), lowered.count <= 4,
           lowered.dropFirst().allSatisfy(\.isNumber), lowered.count > 1 {
            return true
        }
        return false
    }

    // MARK: - Cleaning

    /// Release tags that are never part of a title, matched as whole words.
    ///
    /// Deliberately short. `FilenameFranchise.noise` is longer because it is
    /// throwing away words that *relate* nothing; this is throwing away words that
    /// would make a provider search miss, and "complete", "movie" and "collection"
    /// are all genuinely in real titles — `Star Trek Complete Set` and
    /// `Lupin III - Movie Collection` are both folders in this library.
    private static let releaseTags: Set<String> = [
        "1080p", "720p", "480p", "2160p", "4k", "8bit", "10bit",
        "bluray", "blu-ray", "bdrip", "bdremux", "brrip", "webrip", "web-dl",
        "hdtv", "dvdrip", "x264", "x265", "h264", "h265", "hevc", "avc",
        "aac", "ac3", "flac", "opus", "dts", "remux", "repack", "uncensored",
    ]

    /// Strips what a search must not see, and nothing else.
    static func clean(_ folder: String) -> String {
        var value = stripBracketed(folder)
        value = stripParenthesisedYear(value)

        // A name with no spaces at all is machine-written, so its dots, dashes and
        // underscores are the word breaks: `creampies-compilation_1080p`. A name
        // that already has spaces keeps its punctuation, or `Detective Conan - The
        // Culprit Hanzawa` would lose the dash it needs.
        //
        // Except when the pieces are all one or two characters, which is an
        // initialism rather than a filename — `Media` and `S.W.A.T.` both
        // come apart into single letters, and "M E D I A" is not a search term.
        if !value.contains(" ") {
            let pieces = value.split(whereSeparator: { "._-".contains($0) })
            if pieces.contains(where: { $0.count > 2 }) {
                value = String(value.map { "._-".contains($0) ? " " : $0 })
            }
        }

        let words = value
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !releaseTags.contains($0.lowercased()) }

        return words
            .joined(separator: " ")
            // Whatever a removed bracket left dangling: `Detective Conan - ` and
            // `Nisemonogatari -`.
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—_.,·"))
    }

    /// Removes every `[…]` and `{…}` group: fansub groups, quality tags and the
    /// notes a folder collects — `[Judas]`, `[1080p]`, `[Rewatch Guide]`.
    ///
    /// Square brackets are safe to take wholesale in a way parentheses are not:
    /// no title in this library carries them, while `Rinne no Lagrange (The Flower
    /// of Rin-ne)` needs its parentheses kept.
    private static func stripBracketed(_ value: String) -> String {
        var result = ""
        var depth = 0
        for character in value {
            switch character {
            case "[", "{":
                depth += 1
            case "]", "}":
                depth = max(0, depth - 1)
            default:
                if depth == 0 { result.append(character) }
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Removes a trailing `(2012)` or `(1979-2016)`, and only those.
    ///
    /// A year is noise to a provider search — it is a separate field there — while
    /// anything else in parentheses is part of the name someone chose.
    private static func stripParenthesisedYear(_ value: String) -> String {
        guard let open = value.lastIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else { return value }

        let inner = value[value.index(after: open)..<close]
            .trimmingCharacters(in: .whitespaces)
        guard isYearOrRange(inner) else { return value }

        let head = value[value.startIndex..<open]
        let tail = value[value.index(after: close)...]
        return (head + tail).trimmingCharacters(in: .whitespaces)
    }

    private static func isYearOrRange(_ value: String) -> Bool {
        let parts = value.split(whereSeparator: { $0 == "-" || $0 == "–" })
        guard !parts.isEmpty, parts.count <= 2 else { return false }
        return parts.allSatisfy { part in
            part.count == 4 && part.allSatisfy(\.isNumber)
        }
    }
}

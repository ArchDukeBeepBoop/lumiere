import Foundation

/// Rebuilds a series' episode numbering and titles from the filenames.
///
/// For the case where the server's match is not merely wrong but collapsed. On a
/// real Monogatari folder Jellyfin merged sixteen separate arcs into one series and
/// stamped each arc's episode N with the same metadata: 118 files carrying 15
/// distinct names, sixteen of them all claiming to be season 1 episode 1. Nothing
/// in the app can present that sensibly, because the data says they are the same
/// episode.
///
/// The filenames were right the whole time — `Nisemonogatari - 1x11 - Tsukihi
/// Phoenix, Part 4.mkv` states the arc, the number and the title. So this reads
/// them and proposes what the metadata should have been.
///
/// It reads only files carrying an explicit `1x11` or `S01E11` marker, which is the
/// property that makes it safe to run across a whole library. A show numbered
/// absolutely — `One Piece - 101 - …` — has no marker, so it is never touched; nor
/// is `NCOP/01 - Wind.mkv`, which is an opening rather than episode one.
///
/// Pure and path-only: no repository, no network, so the parsing is testable
/// against real paths without a server.
public enum FilenameEpisodeRepair {

    /// One episode, as the filename describes it.
    public struct Proposal: Sendable, Hashable, Identifiable {
        public let id: String
        /// The folder the file sits in, minus its year — "Nisemonogatari".
        public let arc: String
        /// The year in the folder name, which is what orders unnumbered arcs.
        public let year: Int?
        public let season: Int
        public let episode: Int
        public let title: String

        public init(
            id: String, arc: String, year: Int?, season: Int, episode: Int, title: String
        ) {
            self.id = id
            self.arc = arc
            self.year = year
            self.season = season
            self.episode = episode
            self.title = title
        }
    }

    /// A file this cannot rebuild, and why.
    ///
    /// Reported rather than dropped. A tool whose job is to fix numbering must not
    /// quietly leave some files out: the real folder contains
    /// `Monogatari - Off & Monster Season - 1x06.5 - Special.mkv`, and a half
    /// number is not something Jellyfin can store. Taking the `6` from it would
    /// recreate the exact collision this exists to remove, and renumbering the
    /// real episode 7 to make room would change a number every viewer already
    /// knows. So it is left alone, and said so.
    public struct Skip: Sendable, Hashable, Identifiable {
        public let id: String
        public let filename: String
        public let reason: String
    }

    /// What a repair would do: the rebuilt episodes, and the files it will not touch.
    public struct Plan: Sendable {
        public var proposals: [Proposal]
        public var skipped: [Skip]

        /// Whether the seasons were rewritten rather than taken from the filenames.
        /// True only for a genuine merge — which is what a library-wide scan looks
        /// for, since a series whose titles merely differ from its filenames is not
        /// something to go fixing unasked.
        public var resolvedSeasons: Bool
    }

    public static func proposals(for files: [(id: String, path: String?)]) -> [Proposal] {
        plan(for: files).proposals
    }

    /// Reads every path, then decides each folder's season.
    ///
    /// Two passes rather than one, because a file's season cannot be known from
    /// that file alone: `Nisemonogatari - 1x11` says season 1 and so does every
    /// other arc, and only seeing all sixteen together shows that none of them can
    /// be. `resolveSeasons` is where that judgement lives.
    public static func plan(for files: [(id: String, path: String?)]) -> Plan {
        var parsed: [Parsed] = []
        var skipped: [Skip] = []

        for file in files {
            guard let path = file.path else {
                skipped.append(Skip(
                    id: file.id, filename: "—",
                    reason: "The server did not report a file for this episode."
                ))
                continue
            }
            let filename = (path as NSString).lastPathComponent
            guard let arc = arcName(from: path),
                  let numbering = numbering(from: path),
                  let title = episodeTitle(from: path)
            else {
                skipped.append(Skip(
                    id: file.id, filename: filename,
                    reason: fractionalMarker(in: filename)
                        ? "Numbered as a half episode, which the server cannot store. "
                        + "Left as it is rather than renumbering the episodes around it."
                        : "No season and episode marker like 1x04 in the filename."
                ))
                continue
            }
            parsed.append(Parsed(
                id: file.id,
                folder: (path as NSString).deletingLastPathComponent,
                folderName: arc.name,
                year: arc.year,
                markerSeason: numbering.season,
                episode: numbering.episode,
                title: title
            ))
        }
        guard !parsed.isEmpty else {
            return Plan(proposals: [], skipped: skipped, resolvedSeasons: false)
        }

        let resolution = resolveSeasons(parsed)
        var proposals: [Proposal] = []

        for file in parsed {
            var season = file.markerSeason
            if let resolution {
                switch resolution[file.folder] {
                case .season(let resolved):
                    season = resolved
                case .unresolved(let reason):
                    skipped.append(Skip(id: file.id, filename: file.title, reason: reason))
                    continue
                case nil:
                    break
                }
            }
            proposals.append(Proposal(
                id: file.id,
                arc: file.folderName,
                year: file.year,
                season: season,
                episode: file.episode,
                title: file.title
            ))
        }

        return Plan(
            proposals: proposals.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) },
            // One line per reason, not per file: a folder of 26 episodes refused
            // for one cause should say so once.
            skipped: deduplicated(skipped),
            resolvedSeasons: resolution != nil
        )
    }

    /// The containing folder, split into a name and the year in brackets.
    ///
    /// Public only so the tests can pin it down separately from `plan` — the parts
    /// of the parse fail in different ways, and a test that exercised them only
    /// together could not say which one was wrong.
    public static func arcName(from path: String) -> (name: String, year: Int?)? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let folder = parts[parts.count - 2]

        // "Nisemonogatari (2012)" → name and year. A folder with no year keeps its
        // whole name, since a missing year is not a reason to discard the arc.
        guard let open = folder.lastIndex(of: "("),
              let close = folder.lastIndex(of: ")"),
              open < close,
              let year = Int(folder[folder.index(after: open)..<close])
        else { return (folder, nil) }

        let name = folder[folder.startIndex..<open].trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? folder : name, year)
    }

    /// Everything after the `1x11` marker.
    ///
    /// Found by locating the marker rather than by counting separators, because an
    /// arc's own name contains them: "Monogatari - Off & Monster Season - 1x01 -
    /// Orokamonogatari" splits into four parts, and the title is the last one only
    /// by accident of that particular name.
    /// Public for the same reason as `arcName`.
    public static func episodeTitle(from path: String) -> String? {
        let file = (path as NSString).lastPathComponent
        let stem = (file as NSString).deletingPathExtension
        let parts = stem.components(separatedBy: " - ")

        guard let markerIndex = parts.firstIndex(where: isNumbering) else { return nil }
        let rest = parts[(markerIndex + 1)...].joined(separator: " - ")
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// The season and episode, read from the marker that names the title.
    ///
    /// Deliberately *not* `EpisodeNumbering.parse`, which scans the whole filename
    /// left to right for the first `NxNN` it can find. That is right when rescuing a
    /// number the server missed, and wrong here: `3x3 Eyes - 1x03 - Sacrifice.mkv`
    /// begins with a marker that is part of the show's name, so every one of its
    /// files parsed as episode 3 and the repair would have collapsed four episodes
    /// onto one number.
    ///
    /// Reading the same delimited component the title is taken from cannot make
    /// that mistake: "3x3 Eyes" is not a marker, because a marker is a whole part.
    static func numbering(from path: String) -> (season: Int, episode: Int)? {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return stem.components(separatedBy: " - ").lazy.compactMap(markerNumbers).first
    }

    /// "1x01", "01x11", "S01E11" — a whole part that is nothing but a season and an
    /// episode. Being a *whole* part is the point: it is what stops "3x3 Eyes" from
    /// reading as one.
    public static func markerNumbers(_ part: String) -> (season: Int, episode: Int)? {
        let lowered = part.lowercased()

        let halves = lowered.components(separatedBy: "x")
        if halves.count == 2, halves.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
           let season = Int(halves[0]), let episode = Int(halves[1]),
           // A resolution is the commonest number in a fansub filename, and
           // "1920x1080" standing alone between separators is otherwise a
           // perfectly well-formed marker for season 1920.
           season <= 99, episode <= 999 {
            return (season, episode)
        }

        guard lowered.hasPrefix("s") else { return nil }
        let sides = lowered.dropFirst().components(separatedBy: "e")
        guard sides.count == 2, sides.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let season = Int(sides[0]), let episode = Int(sides[1]),
              season <= 99, episode <= 999 else { return nil }
        return (season, episode)
    }

    private static func isNumbering(_ part: String) -> Bool { markerNumbers(part) != nil }

    /// "1x06.5" — a marker with a fraction in it, which `isNumbering` rejects.
    /// Only used to explain the rejection, never to accept one.
    private static func fractionalMarker(in filename: String) -> Bool {
        filename.components(separatedBy: " - ").contains { part in
            let halves = part.lowercased().components(separatedBy: "x")
            guard halves.count == 2, !halves[0].isEmpty,
                  halves[0].allSatisfy(\.isNumber) else { return false }
            let episode = halves[1].components(separatedBy: ".")
            return episode.count == 2
                && episode.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }
    }

    private static func deduplicated(_ skipped: [Skip]) -> [Skip] {
        var seen: Set<String> = []
        return skipped.filter { seen.insert($0.reason).inserted }
    }
}

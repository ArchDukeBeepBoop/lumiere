import Foundation

/// Deciding which season each folder of a series really is.
///
/// The hard half of the repair, and the half that has to be conservative: this
/// rewrites the season of every episode in a folder, on the server, for every
/// client. Across a real library the shapes it has to tell apart are
///
///   - **a genuine merge** — `Season 1 - Rurou no Senshi`, `Season 3 - Utsukushiki
///     Toushi-tachi` and `Season 5 - Rebellion` whose files *all* say `1x01`,
///     because each was numbered from episode one by whoever released it;
///   - **arcs with no season numbers at all** — sixteen Monogatari folders, same
///     shape, nothing but a year to order them by;
///   - **a season split into cours** — `Season 4` and `Season 4 2nd-cour`, which
///     are one season and must be left exactly as they are;
///   - **a season that is simply large** — `Season 2` holding episodes 63 to 136;
///   - **a folder nobody can fix** — `Season 2`, `Season 2 Part 1` and `Season 2
///     Part 2`, where two of them hold an episode 11 and no rule can say which.
///
/// The signals, in order: what the folder name says, then the year, then nothing.
/// Where they run out, the answer is to refuse rather than to guess.
extension FilenameEpisodeRepair {

    /// One file, after parsing, before its season is decided.
    struct Parsed {
        let id: String
        let folder: String
        let folderName: String
        let year: Int?
        let markerSeason: Int
        let episode: Int
        let title: String
    }

    /// A season and episode number, which only one episode may hold.
    struct Slot: Hashable {
        let season: Int
        let episode: Int
    }

    /// What a folder's season resolved to, or why it could not be.
    enum Resolution {
        case season(Int)
        case unresolved(String)
    }

    /// Assigns every folder a season.
    ///
    /// Returns nothing when the series has no collision at all, which is the
    /// overwhelmingly common case: 979 of the 1,009 series in a real library with
    /// readable filenames are already consistent, and the safest thing to do with
    /// them is to change no season at all.
    static func resolveSeasons(_ parsed: [Parsed]) -> [String: Resolution]? {
        let byFolder = Dictionary(grouping: parsed, by: \.folder)

        // A folder is coherent when every file in it agrees on the season. One that
        // does not — an `FBI/Season 4` holding a stray `5x01` — is a misfiled file,
        // not a merge, and taking the folder's word for it would stamp that file
        // with a number another episode already has.
        var coherent: [String: Int] = [:]
        for (folder, files) in byFolder {
            let seasons = Set(files.map(\.markerSeason))
            if seasons.count == 1, let season = seasons.first { coherent[folder] = season }
        }

        // The trigger is two *files* claiming one slot, not two folders. Asking the
        // folders first missed the case that proves it: an `FBI/Season 4` holding a
        // stray `5x01` is not coherent, so it took no part in a folder comparison,
        // and the duplicate 5x01 it collided with went unnoticed.
        var slots: Set<Slot> = []
        var collides = false
        for file in parsed where !slots.insert(Slot(season: file.markerSeason, episode: file.episode)).inserted {
            collides = true
        }
        guard collides else { return nil }

        var resolved: [String: Resolution] = [:]
        for (folder, files) in byFolder where coherent[folder] == nil {
            resolved[folder] = .unresolved(
                "\(folderLabel(files)) mixes episodes from more than one season, so its "
                + "files are left as they are."
            )
        }

        // Folders that name their season keep it. This is what separates a merge
        // from a mess: `Season 3 - Utsukushiki Toushi-tachi` is season 3 however
        // its files are numbered, and no amount of ordering is a better guess.
        var explicit: [String: Int] = [:]
        for folder in coherent.keys {
            if let season = statedSeason(in: byFolder[folder]?.first?.folderName ?? "") {
                explicit[folder] = season
            }
        }

        // The rest are arcs, OVAs and side stories with nothing but a year. They go
        // after the numbered seasons, in release order, so `Season 1…4` keep their
        // numbers and `OVAs [1993]`, `OVAs [2000]` land on 5 and 6.
        let unnumbered = coherent.keys.filter { explicit[$0] == nil }
            .sorted { left, right in
                let a = byFolder[left]?.first, b = byFolder[right]?.first
                if a?.year != b?.year { return (a?.year ?? .max) < (b?.year ?? .max) }
                return (a?.folderName ?? "").compare(b?.folderName ?? "", options: .numeric)
                    == .orderedAscending
            }
        var next = (explicit.values.max() ?? 0) + 1
        for folder in unnumbered {
            explicit[folder] = next
            next += 1
        }

        for (folder, season) in explicit { resolved[folder] = .season(season) }
        return refusingRemainingCollisions(resolved, byFolder: byFolder)
    }

    /// Folders that still land on the same season with the same episode numbers.
    ///
    /// The Devil Is a Part-Timer shape: `Season 2`, `Season 2 Part 1` and `Season 2
    /// Part 2`, two of which hold an episode 11. Every signal says season 2 and
    /// they are right — the problem is a duplicate file, not a number. Refusing is
    /// the only honest answer, and refusing loudly is better than half-applying.
    private static func refusingRemainingCollisions(
        _ resolved: [String: Resolution], byFolder: [String: [Parsed]]
    ) -> [String: Resolution] {
        var seasons: [String: Int] = [:]
        for (folder, resolution) in resolved {
            if case .season(let season) = resolution { seasons[folder] = season }
        }

        var output = resolved
        for folder in collisions(in: byFolder, seasons: seasons) {
            output[folder] = .unresolved(
                "\(folderLabel(byFolder[folder] ?? [])) still shares its season and episode "
                + "numbers with another folder. Nothing in the names says which is which."
            )
        }
        return output
    }

    /// Folders sharing a season *and* an episode number with another folder.
    ///
    /// Both halves matter. Sharing a season alone is ordinary — `Season 4` and
    /// `Season 4 2nd-cour` are one season split in two, holding episodes 1–13 and
    /// 14–25, and renumbering either would invent a season that never existed.
    /// It is the overlapping episode numbers that prove two folders are claiming
    /// to be the same episodes.
    private static func collisions(
        in byFolder: [String: [Parsed]], seasons: [String: Int]
    ) -> Set<String> {
        let folders = seasons.keys.sorted()
        var colliding: Set<String> = []

        for (offset, left) in folders.enumerated() {
            for right in folders[(offset + 1)...] where seasons[left] == seasons[right] {
                let leftEpisodes = Set((byFolder[left] ?? []).map(\.episode))
                let rightEpisodes = Set((byFolder[right] ?? []).map(\.episode))
                if !leftEpisodes.isDisjoint(with: rightEpisodes) {
                    colliding.insert(left)
                    colliding.insert(right)
                }
            }
        }
        return colliding
    }

    /// The number in "Season 4", when the folder states one.
    ///
    /// Requires digits, which is what keeps `Owarimonogatari Second Season` and
    /// `Monogatari - Off & Monster Season` from reading as season numbers — both
    /// are real folders in the library this was written against.
    /// Public so the tests can pin it directly: "Second Season" reading as a number
    /// is the kind of near-miss that would only show up as a wrong season, three
    /// layers away from the cause.
    public static func statedSeason(in folderName: String) -> Int? {
        let lowered = folderName.lowercased()
        guard let range = lowered.range(of: "season") else { return nil }

        var digits = ""
        for character in lowered[range.upperBound...] {
            if character.isNumber {
                digits.append(character)
            } else if character == " " && digits.isEmpty {
                continue
            } else {
                break
            }
        }
        guard let season = Int(digits), season > 0, season <= 99 else { return nil }
        return season
    }

    private static func folderLabel(_ files: [Parsed]) -> String {
        files.first.map { "\"\($0.folderName)\"" } ?? "This folder"
    }
}

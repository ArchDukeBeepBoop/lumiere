import Foundation

/// Recovers a season and episode number from a filename when the server's own
/// parse went wrong.
///
/// Jellyfin's scanner reads the *whole* name looking for a number, and on a title
/// that contains one it can take the wrong one. `Sky Wizards Academy - 1x01 -
/// Fireteam E601.mkv` became episode **601**, with no season at all, so it was not
/// a child of Season 1 and never appeared in the episode list — the first episode
/// of the show, missing, with the file sitting right there beside the others.
///
/// So this reads left to right and stops at the first *structural* marker — the
/// `S01E02` or `1x01` that names the position — rather than scanning for any number
/// anywhere. A number that appears later in an episode's actual title can then
/// never outrank the one that came before it.
///
/// Pure and string-only, so it is testable without a server or a database.
public enum EpisodeNumbering {

    public struct Numbering: Sendable, Equatable {
        public let season: Int
        public let episode: Int

        public init(season: Int, episode: Int) {
            self.season = season
            self.episode = episode
        }
    }

    /// Reads the first structural season/episode marker in a filename.
    ///
    /// Only the file's own name is examined, never the directories above it: a show
    /// living under `Season 1/` would otherwise lend its number to every file in it,
    /// including the specials that are deliberately season 0.
    public static func parse(path: String?) -> Numbering? {
        guard let path else { return nil }
        let name = (path as NSString).lastPathComponent
        return parse(name: name)
    }

    public static func parse(name: String) -> Numbering? {
        let scalars = Array(name.lowercased())
        var index = 0

        while index < scalars.count {
            // S01E02 / s1e2
            if scalars[index] == "s",
               let (season, afterSeason) = number(in: scalars, from: index + 1),
               afterSeason < scalars.count,
               scalars[afterSeason] == "e",
               let (episode, _) = number(in: scalars, from: afterSeason + 1) {
                return Numbering(season: season, episode: episode)
            }

            // 1x01 — the form that was on the file this exists for. Guarded so it
            // cannot fire mid-word: "1920x1080" in a release tag must not read as
            // season 1920, and a resolution is the single most common number in a
            // fansub filename.
            if scalars[index].isNumber, !isWordCharacter(at: index - 1, in: scalars),
               let (season, afterSeason) = number(in: scalars, from: index),
               afterSeason < scalars.count, scalars[afterSeason] == "x",
               let (episode, afterEpisode) = number(in: scalars, from: afterSeason + 1),
               season <= 99, episode <= 999,
               !isWordCharacter(at: afterEpisode, in: scalars) {
                return Numbering(season: season, episode: episode)
            }

            index += 1
        }
        return nil
    }

    /// Reads an integer starting at `start`, returning it and the index after it.
    private static func number(in scalars: [Character], from start: Int) -> (Int, Int)? {
        var index = start
        var digits = ""
        while index < scalars.count, scalars[index].isNumber, digits.count < 4 {
            digits.append(scalars[index])
            index += 1
        }
        guard let value = Int(digits) else { return nil }
        return (value, index)
    }

    private static func isWordCharacter(at index: Int, in scalars: [Character]) -> Bool {
        guard index >= 0, index < scalars.count else { return false }
        return scalars[index].isLetter || scalars[index].isNumber
    }
}

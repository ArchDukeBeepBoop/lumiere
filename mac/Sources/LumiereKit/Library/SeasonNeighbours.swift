import Foundation

/// The season before or after one, for an episode queue that runs out.
///
/// A season is watched in a sitting, and a show is watched season after
/// season: the player offered "Next" up to the last episode of a season and
/// then nothing, so InuYasha's first season ended in a dead end and the
/// second had to be found from the detail page. Specials sit outside that run
/// unless the owner asks for them — an OVA between seasons is a choice, not
/// the next episode.
public enum SeasonNeighbours {

    /// The season after `seasonId` in `seasons` (already in watching order),
    /// or nil at the end.
    public static func following(
        _ seasonId: String?, in seasons: [LibraryEntry], includesSpecials: Bool
    ) -> LibraryEntry? {
        neighbour(of: seasonId, in: seasons, includesSpecials: includesSpecials, step: 1)
    }

    /// The season before `seasonId`, or nil at the start.
    public static func preceding(
        _ seasonId: String?, in seasons: [LibraryEntry], includesSpecials: Bool
    ) -> LibraryEntry? {
        neighbour(of: seasonId, in: seasons, includesSpecials: includesSpecials, step: -1)
    }

    private static func neighbour(
        of seasonId: String?, in seasons: [LibraryEntry], includesSpecials: Bool, step: Int
    ) -> LibraryEntry? {
        guard let seasonId else { return nil }
        let run = seasons.filter { includesSpecials || !$0.isSpecialsSeason || $0.id == seasonId }
        guard let index = run.firstIndex(where: { $0.id == seasonId }) else { return nil }
        let target = index + step
        return run.indices.contains(target) ? run[target] : nil
    }
}

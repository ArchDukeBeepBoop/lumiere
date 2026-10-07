import Foundation

/// How an episode is numbered on screen: "S1 E2", or "Episode 2" where the
/// show has no seasons.
///
/// Eight places built "S\(season) E\(episode)" for themselves, each behind a
/// guard that needed both numbers — so an episode of a show filed with no
/// season folder (103 shows here) was numbered nowhere: not on its card, not
/// in the player, not in the queue. One rule, and the seasonless case says
/// what it can.
public enum EpisodeCode {
    public static func text(season: Int?, episode: Int?, compact: Bool = false) -> String? {
        guard let episode else { return nil }
        guard let season else { return "Episode \(episode)" }
        return compact ? "S\(season)E\(episode)" : "S\(season) E\(episode)"
    }
}

public extension ItemRecord {
    /// See `EpisodeCode`.
    func episodeCode(compact: Bool = false) -> String? {
        EpisodeCode.text(season: parentIndexNumber, episode: indexNumber, compact: compact)
    }
}

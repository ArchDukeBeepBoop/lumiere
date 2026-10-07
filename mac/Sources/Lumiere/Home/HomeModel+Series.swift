import Foundation
import LumiereKit

/// "Continue the Series": after Alien, Aliens. The next film in each film
/// series you have started, from the server's collections — Next Up's
/// question asked of films, which Next Up only asks of shows.
extension HomeModel {
    /// Whether the three "what next" rows are drawn as one. See `upNext`.
    var mergesUpNext: Bool { Preference.mergesUpNext.value }

    /// Next Up, then the next film of each series under way, then the shows
    /// nearly finished — each title once, a show counted by its series so an
    /// episode on Next Up and its show on Finish the Season are not both drawn.
    var upNext: [LibraryEntry] {
        var seen = Set<String>()
        var out: [LibraryEntry] = []
        for entry in nextUp + continueSeries + finishSeason {
            let key = entry.item.seriesId ?? entry.id
            if seen.insert(key).inserted { out.append(entry) }
        }
        return out
    }

    /// One sentence of news under the hero, or nil when there is none: new
    /// episodes of what you are following, and the next film of a series under
    /// way. Said only when true; most days, nothing is drawn.
    var newsLine: String? {
        var parts: [String] = []
        let fresh = newEpisodeIds.count
        if fresh > 0 {
            parts.append("\(fresh) new episode\(fresh == 1 ? "" : "s") of shows you are watching")
        }
        if let film = continueSeries.first {
            parts.append("next in its series: \(film.item.name)")
        }
        guard !parts.isEmpty else { return nil }
        let sentence = parts.joined(separator: " · ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// The title of the "what next" row: merged, it answers for all three.
    var nextUpTitle: String { mergesUpNext ? "Up Next" : "Next Up" }
    /// What the Next Up row draws: everything, when the rows are merged —
    /// less what Continue Watching already shows. A show half-way through an
    /// episode was also on Up Next with that same episode; the higher row
    /// keeps it, and each title appears on Home once.
    var nextUpEntries: [LibraryEntry] {
        let resumed = Set(resume.flatMap { [$0.id, $0.item.seriesId].compactMap { $0 } })
        return (mergesUpNext ? upNext : nextUp).filter {
            !resumed.contains($0.id) && !resumed.contains($0.item.seriesId ?? "")
        }
    }

    /// Recently Added, less what the hero is already showing above it.
    var recentlyAddedShown: [LibraryEntry] {
        let featured = Set(heroEntries.map(\.id))
        return recentlyAdded.filter { !featured.contains($0.id) }
    }

    func loadContinueSeries(hidden: Set<String>, generation: Int) async {
        let fresh = await repository.seriesNextUp().filter { !hidden.contains($0.id) }
        let news = await repository.newEpisodeIds(among: nextUp + fresh)
        guard isCurrent(generation) else { return }
        if news != newEpisodeIds { newEpisodeIds = news }
        guard fresh != continueSeries else { return }
        continueSeries = fresh
    }
}

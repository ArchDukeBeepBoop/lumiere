import Foundation
import LumiereKit

/// Fills the hero with things worth starting, rather than with the thing you were
/// half-way through.
///
/// The rule itself — highest-rated unwatched title per library, round-robined —
/// lives in `Spotlight` beside the query it needs, because it is the part that can
/// be tested. This half is only the plumbing: which libraries to ask, and the
/// dismissals that are a purely presentational choice and so never reach SQL.
extension HomeModel {

    /// Loads the hero's rotation.
    ///
    /// Asked of the video libraries only. A music or photo library has no backdrop
    /// worth 460 points of screen, and a folder library — "3D", "My Videos" — has no
    /// scraped metadata at all, so its rows carry neither a rating to rank by nor
    /// artwork to show. Both are excluded here rather than in SQL because the
    /// distinction is about what a library *is*, which only `LibraryRecord` knows.
    func loadSpotlight(
        libraries: [LibraryRecord], hidden: Set<String>, generation: Int
    ) async {
        let eligible = libraries.filter { $0.holdsPlayableVideo && !$0.prefersFolderBrowsing }

        var groups: [[LibraryEntry]] = []
        for library in eligible {
            // Over-fetched by the shelf's own factor rather than exactly: the
            // dismissals below are applied after the query, and asking for six
            // when two are hidden would leave a library contributing four.
            // A day's worth of pool, not a shelf's worth: `mix` rotates into this by
            // the date, so how deep it goes is how long it takes before a title can
            // be featured twice. The dismissals below are applied after the query,
            // so it is also over-fetched for them.
            let candidates = (try? await repository.spotlightCandidates(
                libraryId: library.id, limit: Spotlight.poolDepth
            )) ?? []
            let visible = candidates.filter { !hidden.contains($0.id) }
            if !visible.isEmpty { groups.append(visible) }
        }

        // The session number, fixed at launch by AppModel rather than read here:
        // `loadSpotlight` runs again whenever the home screen reloads — a sync, a
        // library change, revealing a private library — and taking a fresh number
        // each time would reshuffle the hero underneath somebody mid-sentence.
        guard isCurrent(generation) else { return }

        // The rotation still decides the *order* — it is what keeps a large
        // library from featuring the same six titles all week. What changed is
        // the front of it: the one title with the best reason to be there leads,
        // and carries that reason as a sentence.
        var mixed = Spotlight.mix(groups, day: Spotlight.session)
        var reasons: [String: String] = [:]
        if let lead = SpotlightReason.choose(
            from: mixed, tiebreak: Spotlight.session
        ), lead.verdict.kind != .none {
            mixed.removeAll { $0.id == lead.entry.id }
            mixed.insert(lead.entry, at: 0)
            reasons[lead.entry.id] = lead.verdict.sentence
        }
        // Every other slide gets its own verdict too, so moving through the
        // spotlight does not silently drop the one thing that made it editorial.
        for entry in mixed where reasons[entry.id] == nil {
            let verdict = SpotlightReason.verdict(for: entry)
            if let sentence = verdict.sentence { reasons[entry.id] = sentence }
        }

        spotlight = mixed
        spotlightReasons = reasons
        didLoadSpotlight = true
    }
}

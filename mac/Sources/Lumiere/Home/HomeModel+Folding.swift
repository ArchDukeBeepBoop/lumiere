import Foundation
import LumiereKit

/// Turning a run of episodes back into the series it belongs to.
///
/// Split from HomeModel.swift for the project's 300-line limit. The rule itself is
/// in `LatestShelf`, which is pure and tested; this is the half that needs a
/// database to resolve the series rows the rule asked for.
@MainActor
extension HomeModel {

    /// Swaps in the real series record for the slots that asked for one.
    ///
    /// The half of the fold that needs a database — the rule itself is in
    /// `LatestShelf`, which is pure. One query for the whole shelf rather than one
    /// per tile. Not private: `latestTiles` in HomeModel+Latest.swift calls it, and
    /// Swift's `private` is file-scoped.
    static func resolveSeries(
        repository: LibraryRepository, slots: [LatestShelf.Slot]
    ) async -> [LibraryEntry] {
        let seriesIds = slots.compactMap(\.seriesId)

        var series: [String: LibraryEntry] = [:]
        if !seriesIds.isEmpty {
            let fetched = (try? await repository.entriesById(Array(Set(seriesIds)))) ?? []
            series = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }

        // The representative episode is the fallback rather than a gap: a series the
        // cache has not seen — the episode arrived before its parent synced — should
        // still show something playable.
        let resolved = slots.map { slot -> LibraryEntry in
            guard let seriesId = slot.seriesId else { return slot.representative }
            return series[seriesId] ?? slot.representative
        }

        // Belt and braces after the substitution. `LatestShelf` guarantees one slot
        // per series, but the fallback above can still land two slots on the same
        // entry when a series is uncached, and a repeated tile is the one outcome
        // this whole mechanism exists to prevent.
        var seen: Set<String> = []
        return resolved.filter { seen.insert($0.id).inserted }
    }
}

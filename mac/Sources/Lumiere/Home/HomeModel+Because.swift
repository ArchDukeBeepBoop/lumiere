import Foundation
import LumiereKit

/// "Because you watched…": titles related to the last film or show watched,
/// as Apple TV's Home offers them. Those already watched are left out, and so
/// is anything in a private library.
extension HomeModel {
    func loadBecauseYouWatched(generation: Int) async {
        let recent = (try? await repository.watchedRecently(limit: 20)) ?? []
        guard let seed = recent.first(where: { [.movie, .series, .episode].contains($0.item.itemType) }) else {
            if isCurrent(generation) { becauseYouWatched = nil }
            return
        }
        let isEpisode = seed.item.itemType == .episode
        let id = isEpisode ? (seed.item.seriesId ?? seed.id) : seed.id
        let name = isEpisode ? (seed.item.seriesName ?? seed.item.name) : seed.item.name
        let related = ((try? await repository.similarEntries(to: id, limit: 20)) ?? []).filter {
            !$0.isPlayed && !privateLibraryIds.contains($0.item.libraryId ?? "")
        }
        guard isCurrent(generation) else { return }
        becauseYouWatched = related.isEmpty ? nil : ("Because you watched \(name)", related)
    }
}

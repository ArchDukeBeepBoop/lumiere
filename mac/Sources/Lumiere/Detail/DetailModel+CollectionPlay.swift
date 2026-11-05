import Foundation
import LumiereKit

/// Play from the Beginning: a collection watched straight through, in the
/// order its page shows — for an anime franchise, the order it came out —
/// with every show expanded to its episodes, season by season.
extension DetailModel {

    /// Everything to play, in order. Shows contribute their episodes; a
    /// Season 0 only where specials are counted in the order (Settings).
    func collectionPlayOrder() async -> [LibraryEntry] {
        let titles = collectionShelves.isEmpty ? collectionItems : collectionShelves.flatMap(\.entries)
        let specials = Preference.includesSpecialsInOrder.value
        var out: [LibraryEntry] = []
        for title in titles {
            switch title.item.itemType {
            case .series:
                let seasons = (try? await repository.seasons(seriesId: title.id)) ?? []
                let ordered = seasons
                    .filter { specials || ($0.item.indexNumber ?? 1) != 0 }
                    .sorted { ($0.item.indexNumber ?? 0) < ($1.item.indexNumber ?? 0) }
                if ordered.isEmpty {
                    out += (try? await repository.episodes(seriesId: title.id, seasonId: nil)) ?? []
                }
                for season in ordered {
                    out += (try? await repository.episodes(seriesId: title.id, seasonId: season.id)) ?? []
                }
            case .movie, .video, .episode:
                out.append(title)
            default:
                break
            }
        }
        return out
    }
}

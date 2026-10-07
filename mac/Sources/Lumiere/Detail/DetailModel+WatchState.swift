import Foundation
import LumiereKit

/// Marking things watched and starred from a detail page.
///
/// Split out of DetailModel.swift purely to stay under the project's 300-line
/// rule; these are the same model, and they read and write its state directly.
extension DetailModel {


    /// Optimistic: the UI updates immediately and the repository puts it back if
    /// the server refuses. A tick that waits for a round trip feels broken.
    func toggleWatched() async {
        guard let entry else { return }
        let newValue = !entry.isPlayed
        await repository.setPlayed(itemId: itemId, played: newValue)
        self.entry = try? await repository.entry(id: itemId)
    }

    /// Marks every title in this collection, then re-reads the members, whose
    /// state the server changed.
    func setCollectionWatched(_ played: Bool) async {
        await repository.setPlayed(itemId: itemId, played: played)
        await loadCollectionItems()
    }

    func toggleFavourite() async {
        guard let entry else { return }
        let newValue = !(entry.userData?.isFavorite ?? false)
        await repository.setFavorite(itemId: itemId, favorite: newValue)
        self.entry = try? await repository.entry(id: itemId)
    }

    /// Marks one member of a collection watched, from the shelf's own menu.
    ///
    /// Reloads the whole page rather than one row: the shelves are rebuilt from the
    /// collection's members, and a tile whose tick disagreed with the row it sits in
    /// is the bug this command exists to avoid.
    func setMemberWatched(_ entry: LibraryEntry) async {
        await repository.setPlayed(itemId: entry.id, played: !entry.isPlayed)
        await load()
    }

    func setEpisodeWatched(_ episodeId: String, played: Bool) async {
        await repository.setPlayed(itemId: episodeId, played: played)
        await loadEpisodes()
    }

    /// Toggles watched/favourite on whichever episode the hero is currently
    /// showing, rather than on the series — the action row's icons act on what is
    /// on screen, matching Infuse.
    func toggleHeroWatched() async {
        guard let hero = heroEntry else { return }
        let id = hero.id
        await repository.setPlayed(itemId: id, played: !hero.isPlayed)
        await loadEpisodes()
        heroEpisodeId = id
    }

    func toggleHeroFavourite() async {
        guard let hero = heroEntry else { return }
        let id = hero.id
        await repository.setFavorite(itemId: id, favorite: !(hero.userData?.isFavorite ?? false))
        await loadEpisodes()
        heroEpisodeId = id
    }

    func selectSeason(_ seasonId: String) async {
        guard seasonId != selectedSeasonId else { return }
        selectedSeasonId = seasonId
        episodes = []
        await loadEpisodes()
        // A season switch from the picker is a deliberate browse, not a resume —
        // lead with that season's first unwatched episode rather than leaving the
        // previous season's hero on screen with a now-empty strip around it.
        selectEpisode(episodes.first { !$0.isPlayed }?.id ?? episodes.first?.id)
    }
}

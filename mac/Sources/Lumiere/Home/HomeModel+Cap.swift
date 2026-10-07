import Foundation
import LumiereKit

/// Which shelves have anything in them, and therefore which ones the cap counts.
///
/// The seven-shelf cap has to skip empty rows rather than count them, or a home
/// screen with three empty shelves shows four full ones. That means the cap
/// needs to ask the model what is empty — which is what this answers, in one
/// place, so the cap and the rows below it can never disagree about whether a
/// shelf exists.
extension HomeModel {

    func isEmpty(_ section: HomeSection, layout: HomeLayout) -> Bool {
        switch section {
        // Furniture, never empty and never counted. See `HomeSection.isShelf`.
        case .spotlight, .quickLinks, .libraries:
            return false
        case .continueWatching: return resume.isEmpty
        case .genres: return genreCards.isEmpty
        case .nextUp: return nextUpEntries.isEmpty
        case .finishSeason: return mergesUpNext || finishSeason.isEmpty
        case .forgotten: return forgotten.isEmpty
        case .continueSeries: return mergesUpNext || continueSeries.isEmpty
        case .becauseYouWatched: return becauseYouWatched == nil
        case .recentlyAdded:
            // Classic draws nothing here whatever the data says.
            return layout != .hero || recentlyAdded.isEmpty
        case .topFilms: return topFilms.isEmpty
        case .topSeries: return topSeries.isEmpty
        case .topAnime: return topAnime.isEmpty
        case .latest(let libraryId):
            return libraryShelves
                .first { $0.library.id == libraryId }?
                .entries.isEmpty ?? true
        }
    }

    /// The running order, capped.
    ///
    /// - Returns: what to draw, and how many shelves were held back — the second
    ///   number is what the note at the foot of the page reports, because a page
    ///   that quietly drops four rows is worse than a long one.
    func capped(
        _ sections: [HomeSection], layout: HomeLayout, showAll: Bool
    ) -> (visible: [HomeSection], heldBack: Int) {
        // Switched-off rows are gone, not held back: they neither count nor
        // appear in the note at the foot. See `HomeOrder.hiddenKey`.
        let off = HomeOrder.hidden(from: UserDefaults.standard.string(forKey: HomeOrder.hiddenKey))
        let sections = sections.filter { !off.contains($0.id) }
        let shelves = sections.filter(\.isShelf)
        let result = HomeShelfCap.apply(
            to: shelves,
            isEmpty: { isEmpty($0, layout: layout) },
            showAll: showAll
        )
        let keep = Set(result.visible)
        // Rebuilt from the original order so the furniture stays where it was
        // rather than being gathered at the top.
        let visible = sections.filter { !$0.isShelf || keep.contains($0) }
        return (visible, result.heldBack.count)
    }
}

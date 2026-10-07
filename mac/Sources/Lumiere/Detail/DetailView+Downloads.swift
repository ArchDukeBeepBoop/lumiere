import SwiftUI
import LumiereKit

/// The detail page's download buttons.
///
/// Split out of DetailView.swift to stay under the project's 300-line rule. They
/// read the page's own state, so an extension rather than a separate view.
extension DetailView {

    /// Only for single files. A series is a container — there is no one file to
    /// fetch, and a button that silently does nothing is worse than no button.
    // Widened by the split, as elsewhere: `private` is file-scoped.
    func downloadAction(for model: DetailModel) -> DownloadAction? {
        guard let app, !model.isSeries else { return nil }
        let id = playableItemId(for: model)
        let record = app.downloadRecord(for: id)
        return DownloadAction(record: record) {
            if record?.isPlayableOffline == true {
                // Confirmed: the icon flips to a checkmark when a download
                // finishes, and one click on the same spot deleted it.
                deletingDownloadId = id
            } else {
                await app.download(itemId: id)
            }
        }
    }

    /// The hero episode's download state, not the series' — a series has no one
    /// file, but whichever episode is on screen does.
    func heroDownloadAction(for model: DetailModel, hero: LibraryEntry) -> DownloadAction? {
        guard let app else { return nil }
        let record = app.downloadRecord(for: hero.id)
        return DownloadAction(record: record) {
            if record?.isPlayableOffline == true {
                deletingDownloadId = hero.id
            } else {
                await app.download(itemId: hero.id)
            }
        }
    }

    /// The technical source to describe below — the hero episode's for a series,
    /// the item's own otherwise. Loaded lazily per episode, so it is nil until
    /// `selectEpisode` has had a moment to fetch it.
}

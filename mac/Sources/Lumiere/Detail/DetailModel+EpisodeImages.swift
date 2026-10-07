import Foundation
import LumiereKit

/// Filling in episode stills a library never had.
///
/// Freshly scanned shows arrive with no episode artwork at all — Jellyfin writes
/// the pictures when it identifies the episodes, which can be long after the
/// files appear, and on a show it never identifies it never writes them. The app
/// already holds a TMDB key for identify, and the server already knows which
/// episodes are bare, so between them the gap is fillable on demand.
extension DetailModel {

    /// Offered for any series, because whether it can work is a question only the
    /// server can answer — it knows which episodes are missing pictures and
    /// whether the show has a TMDB id. Asking costs one request, and the answer
    /// is a sentence rather than a disabled button with no explanation.
    var canFetchEpisodeImages: Bool {
        entry?.item.itemType == .series && MetadataCredentials.hasKey(for: .tmdb)
    }

    func fetchEpisodeImages() async {
        guard !isFetchingEpisodeImages else { return }
        isFetchingEpisodeImages = true
        episodeImageStatus = "Looking for missing artwork…"
        defer { isFetchingEpisodeImages = false }

        do {
            let result = try await repository.fetchEpisodeImages(seriesId: itemId)
            if let blocked = result.blocked {
                episodeImageStatus = blocked
            } else if result.considered == 0 {
                episodeImageStatus = "Every episode already has a picture."
            } else if result.fetched == 0 {
                // The distinction matters: TMDB genuinely has no stills for some
                // shows, and reporting that as a failure sends someone looking
                // for a fault that is not there.
                episodeImageStatus =
                    "TMDB has no pictures for the \(result.considered) missing."
            } else {
                episodeImageStatus =
                    "Fetched \(result.fetched) of \(result.considered) missing."
                await loadEpisodes()
            }
        } catch {
            episodeImageStatus = error.localizedDescription
        }
    }
}

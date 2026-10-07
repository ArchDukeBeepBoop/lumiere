import SwiftUI
import LumiereKit

extension DetailView {
    /// Replaces one episode's thumbnail with a frame out of its own file.
    ///
    /// Reported rather than silent, in both directions. A server without trickplay
    /// images cannot do this at all, and "nothing happened" is the worst possible
    /// way to say so — the failure names the setting to turn on.
    func generateThumbnail(for episodeId: String, model: DetailModel) async {
        guard let client = app?.client else { return }
        let runtime = model.episodes.first { $0.id == episodeId }?.item.runtimeSeconds
        do {
            try await GeneratedThumbnail.apply(
                itemId: episodeId, runtimeSeconds: runtime, client: client
            )
            try? await repository.refreshItem(itemId: episodeId)
            await model.load()
        } catch {
            Diagnostics.log("[thumbnail] \(episodeId): \(error)")
            app?.report(error.localizedDescription)
        }
    }

}

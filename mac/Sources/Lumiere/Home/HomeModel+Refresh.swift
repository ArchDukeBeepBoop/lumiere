import Foundation
import LumiereKit

/// Re-reading what is already on screen.
///
/// Split from HomeModel.swift for the project's 300-line limit. Both of these are
/// the same idea from different directions: something changed that the view's own
/// inputs cannot see, so the model is told rather than asked.
@MainActor
extension HomeModel {

    /// Rotates the hero to the next set and reloads it.
    ///
    /// Advancing the session is the same thing a launch does — see
    /// `Spotlight.advanceSession` — so a press moves through the pool exactly as
    /// reopening the app used to, without reopening the app.
    func refreshSpotlight(libraries: [LibraryRecord]) async {
        Spotlight.advanceSession()
        let hidden = (try? await repository.hiddenShelfIds()) ?? []
        await loadSpotlight(libraries: libraries, hidden: hidden, generation: generation)
    }
}

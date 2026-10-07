import Foundation
import LumiereKit

/// Reading the library list back out of the cache.
///
/// Split from AppModel.swift for the project's 300-line rule. Small on purpose:
/// it is the one path that has to work with the server asleep, which is why it
/// logs a failure rather than swallowing it into an empty list.
@MainActor
extension AppModel {

    /// Loads what is already cached, then reconciles with the server behind it.
    /// The UI is never blocked on the network after the first run.
    func loadCachedLibraries() async {
        guard let repository else {
            Diagnostics.log("[sync] no repository — cannot load cached libraries")
            return
        }
        do {
            libraries = inHomeOrder(try await repository.libraries())
            Diagnostics.log("[sync] loaded \(libraries.count) cached libraries")
        } catch {
            // Swallowed with `try?` before, which made an unreadable cache look
            // exactly like an empty one.
            Diagnostics.log("[sync] cached libraries failed: \(error)")
            libraries = []
        }
    }

    /// Re-sorts the libraries already loaded.
    ///
    /// For the moment the order changes in settings: `libraries` is otherwise
    /// only sorted when it is loaded, and the sidebar beside the pane would keep
    /// yesterday's order until the app was restarted.
    func reapplyLibraryOrder() {
        libraries = inHomeOrder(libraries)
    }

    /// The library list, ordered the way the home screen's shelves are.
    ///
    /// Applied here rather than in the repository, which has no business knowing
    /// about a home-screen preference — and applied at every point `libraries` is
    /// assigned, because it is read by the sidebar, the poster row, settings and
    /// the browse pages, and a list that is only sometimes in the user's order is
    /// worse than one that never is.
    func inHomeOrder(_ libraries: [LibraryRecord]) -> [LibraryRecord] {
        LibraryOrdering.sorted(libraries, id: \.id)
    }

    // Retrying the connection and the LUMIERE_FORCE_OFFLINE hook moved to
    // AppModel+Offline.swift, with the rest of offline mode — and because this file
    // had reached the project's 300-line limit.
}

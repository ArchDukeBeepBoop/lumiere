import SwiftUI
import LumiereKit

/// The environment hooks that open the app somewhere other than Home.
///
/// Split out of ShellView.swift, which had reached the project's 300-line limit
/// again once the sidebar's visibility state moved in. Nothing here is product
/// behaviour — it is the only way a headless build shell can reach a screen.
extension ShellView {

    /// `LUMIERE_OPEN=<itemId>` opens straight to an item.
    ///
    /// A verification hook: driving a click needs Accessibility permission, which
    /// a headless build shell does not have, so without this a detail page cannot
    /// be screenshotted at all.
    func openLaunchRoute() {
        let environment = ProcessInfo.processInfo.environment
        // LUMIERE_ROUTE=settings|search opens straight to a section, for the same
        // reason as the other hooks: driving a click needs Accessibility
        // permission a headless build shell does not have.
        switch environment["LUMIERE_ROUTE"] {
        case "settings": route = .settings
        case "search": route = .search
        case .some(let value) where value.hasPrefix("library:"):
            // LUMIERE_ROUTE=library:<id> opens a full grid, which is the view the
            // memory audit needs — the home shelves never hold a whole library.
            let id = String(value.dropFirst("library:".count))
            let name = app.libraries.first { $0.id == id }?.name ?? "Library"
            route = .library(id: id, name: name)
        case .some(let value) where value.hasPrefix("play:"):
            // LUMIERE_ROUTE=play:<id> starts playback at launch, for checking a
            // player path from a shell — a linked-chapter release, say — where
            // the evidence is a log line rather than a picture.
            let id = String(value.dropFirst("play:".count))
            Task {
                // After the repository is up; the player needs a client.
                for _ in 0..<50 where app.repository == nil {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                app.nowPlayingItemId = id
            }
        default: break
        }
        if let itemId = environment["LUMIERE_OPEN"], !itemId.isEmpty {
            path.append(DetailRoute(itemId: itemId))
        }
        // LUMIERE_PLAY=<itemId> opens the player, for the same reason.
        if let itemId = environment["LUMIERE_PLAY"], !itemId.isEmpty {
            app.nowPlayingItemId = itemId
        }
    }
}

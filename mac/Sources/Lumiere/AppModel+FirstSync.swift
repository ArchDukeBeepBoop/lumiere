import Foundation
import LumiereKit

/// A first sync that shows something at once.
///
/// A library never read is read in full, and on a big one — 24,000 items in
/// Anime here — that is minutes with nothing from it on screen. So before the
/// full reads, every such library gives its newest few hundred titles: Home
/// fills within seconds, as Photos shows a new library's latest pictures
/// first, and the full reads fill in the rest behind it.
@MainActor
extension AppModel {
    func previewUnreadLibraries(_ libraries: [LibraryRecord]) async {
        guard let repository else { return }
        for library in libraries {
            guard (try? await repository.lastFullSync(libraryId: library.id)) == nil,
                  !Task.isCancelled else { continue }
            guard (try? await repository.syncLibrary(id: library.id, mode: .preview, pageSize: 300)) != nil
            else { continue }
            Diagnostics.log("[sync] previewed \(library.name)")
            await homeModel?.refresh("after a first look at \(library.name)")
            LibraryChangeFeed.shared.note("library synced", libraryId: library.id)
        }
    }
}

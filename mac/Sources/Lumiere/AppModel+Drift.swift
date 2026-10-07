import Foundation
import LumiereKit

/// Catching what the change feed might have missed, cheaply.
///
/// The feed is exact while it runs, but a cache can still drift: a database
/// restored from a backup, a crash between a fetch and a write. The weekly
/// full read used to be the answer — every library walked whether anything
/// was wrong or not. This asks each library for one number instead.
///
/// Not "the two counts must match": a cache can hold a few rows the server's
/// count leaves out, or the reverse, for reasons that are not drift. So the
/// gap is remembered, and only a gap that *moves* means something was missed.
/// That library, and only that one, is read in full.
@MainActor
extension AppModel {
    @MainActor private enum Drift {
        static var task: Task<Void, Never>?
    }

    func startDriftCheck() {
        Drift.task?.cancel()
        Drift.task = Task { @MainActor [weak self] in
            // Well after launch, and then every six hours.
            try? await Task.sleep(for: .seconds(300))
            while !Task.isCancelled {
                await self?.checkDrift()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func cancelDriftCheck() {
        Drift.task?.cancel()
        Drift.task = nil
    }

    func checkDrift() async {
        guard let repository, feedIsLive, !isOffline, syncTask == nil,
              !isPresentingMedia else { return }
        for library in syncSelection.libraries(from: libraries) {
            guard !Task.isCancelled, let server = try? await repository.serverCount(libraryId: library.id)
            else { continue }
            let gap = server - (await repository.cachedCount(libraryId: library.id))
            let key = "driftGap.\(library.id)"
            guard let known = UserDefaults.standard.object(forKey: key) as? Int else {
                UserDefaults.standard.set(gap, forKey: key)
                continue
            }
            guard gap != known else { continue }
            Diagnostics.log("[drift] \(library.name): gap \(known) → \(gap) — reading it again")
            do {
                try await repository.rereadLibrary(library.id)
                let after = server - (await repository.cachedCount(libraryId: library.id))
                UserDefaults.standard.set(after, forKey: key)
                await homeModel?.refresh("after \(library.name) was read again")
                LibraryChangeFeed.shared.note("library synced", libraryId: library.id)
            } catch {
                Diagnostics.log("[drift] \(library.name) could not be read: \(error)")
            }
        }
    }
}

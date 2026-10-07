import Foundation
import LumiereKit
import LumierePlayer

/// Offline downloads and the locally-hidden shelf list.
///
/// Split out of AppModel.swift, which is well past the project's 300-line limit.
extension AppModel {
    // MARK: - Downloads

    func refreshDownloads() async {
        guard let downloads else { return }
        downloadRecords = (try? await downloads.records()) ?? []
    }

    func download(itemId: String) async {
        guard let downloads else {
            // Audible, not silent. The identical guard on the sync path hid a bug
            // for a dozen phases.
            Diagnostics.log("[download] no manager yet — request for \(itemId) dropped")
            return
        }
        // Downloading unambiguously needs the server, and it is exactly what someone
        // reaches for when the server is away — the button sits under a banner
        // saying so. Enqueuing anyway leaves a row stuck in `queued`, and the poll
        // below spins once a second waiting for bytes that cannot arrive.
        guard !isOffline else { return refuseOffline("Downloading") }
        try? await downloads.enqueue(itemId: itemId)
        await refreshDownloads()
        // Polls while anything is in flight. The manager keeps per-chunk progress in
        // memory rather than writing it thousands of times per file, so the UI has
        // to come and ask.
        Task { @MainActor in
            while downloadRecords.contains(where: { $0.state == .queued || $0.state == .downloading }) {
                try? await Task.sleep(for: .seconds(1))
                await refreshDownloads()
            }
        }
    }

    func removeDownload(itemId: String) async {
        guard let downloads else { return }
        try? await downloads.cancel(itemId: itemId)
        await refreshDownloads()
    }

    func downloadRecord(for itemId: String) -> DownloadRecord? {
        downloadRecords.first { $0.itemId == itemId }
    }

    // MARK: - Hidden shelf items

    func hideFromShelves(itemId: String) async {
        try? await repository?.hideFromShelves(itemId: itemId)
        await contentDidChange("after hide")
    }

    func unhideFromShelves(itemId: String) async {
        try? await repository?.unhideFromShelves(itemId: itemId)
        await contentDidChange("after unhide")
    }

    func clearHiddenFromShelves() async {
        try? await repository?.clearHiddenShelfItems()
        await contentDidChange()
    }

    /// Erases the watch history of everything on the hidden list, then empties it.
    func clearHiddenWatchHistory() async {
        try? await repository?.clearWatchHistoryForHiddenItems()
    }

    /// Erases one item's watch history — position and played state, server and cache.
    func clearWatchHistory(itemId: String) async {
        await repository?.clearWatchHistory(itemId: itemId)
    }

    func hiddenShelfEntries() async -> [LibraryEntry] {
        (try? await repository?.hiddenShelfEntries()) ?? []
    }
}

extension AppModel {

    /// `LUMIERE_DOWNLOAD=<itemId>` and `LUMIERE_PREFETCH=1`. Run here rather than
    /// from the shell's task, which races `attach` and lost — exactly the mistake
    /// that kept the sync from ever running.
    func applyLaunchJobs() async {
        // Nothing owns a `.downloading` row at launch, whatever the row says.
        try? await downloads?.requeueInterrupted()

        let environment = ProcessInfo.processInfo.environment
        if let id = environment["LUMIERE_DOWNLOAD"], !id.isEmpty {
            await download(itemId: id)
        }
        if environment["LUMIERE_PREFETCH"] == "1" {
            await prefetchArtwork(widths: ArtworkPrefetcher.uiWidths, scale: 2)
        }
        // `LUMIERE_FETCH_ARTWORK=missing` fills gaps; `=all` replaces every poster.
        //
        // Spelled out rather than a 1/0 flag, and the destructive variant needs its
        // own word: this writes to the *server*, applying a poster to each item, and
        // "replace all" discards artwork somebody picked by hand. A truthy flag that
        // could be set by accident is the wrong shape for that.
        if let mode = environment["LUMIERE_FETCH_ARTWORK"], mode == "missing" || mode == "all" {
            Diagnostics.log("[artwork] launch job: \(mode)")
            await fetchArtwork(missingOnly: mode == "missing")
        }
    }
}

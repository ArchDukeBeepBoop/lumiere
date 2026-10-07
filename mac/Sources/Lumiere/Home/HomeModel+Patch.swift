import Foundation
import LumiereKit

/// Updating one card at once, ahead of the full reload.
///
/// A tick on an episode rebuilt the whole home screen — every shelf, with
/// Next Up a server round trip of up to four seconds — after a settle delay,
/// and restarted that rebuild for each of the several announcements one tick
/// makes (the write, the database watcher, the server's confirmation). The card
/// you had just ticked changed only when the last rebuild landed. Now the card
/// is re-read from the cache and swapped in place the moment the write is
/// announced; the full reload still follows, for what really moves shelves —
/// an episode leaving Continue Watching, the next one entering Next Up.
@MainActor
extension HomeModel {

    /// Re-reads one item and replaces it wherever the home screen shows it.
    func patch(itemId: String, since: Date = Date()) async {
        guard let fresh = try? await repository.entry(id: itemId) else { return }
        defer {
            // The number the user feels: from the change being announced to
            // the card showing it. Read from ~/Library/Logs/Lumiere.
            Diagnostics.log(String(format: "[home] card updated %.0f ms after the change",
                                   Date().timeIntervalSince(since) * 1000))
        }
        func swap(_ list: inout [LibraryEntry]) {
            if let i = list.firstIndex(where: { $0.id == itemId }), list[i] != fresh { list[i] = fresh }
        }
        swap(&resume)
        swap(&recentlyAdded)
        swap(&nextUp)
        swap(&finishSeason)
        swap(&forgotten)
        swap(&continueSeries)
        swap(&spotlight)
        swap(&wallEntries)
        for i in libraryShelves.indices {
            swap(&libraryShelves[i].entries)
        }
    }

    // MARK: - Next Up, remembered

    /// Next Up is the one home row that waits on the server — up to four
    /// seconds — so on launch it was the row that arrived last, after the
    /// others had settled. The last answer is kept as ids and shown from the
    /// cache at once; the server's reply replaces it when it comes.
    private static let rememberedNextUpKey = "rememberedNextUp"

    func rememberNextUp() {
        guard !nextUp.isEmpty else { return }
        UserDefaults.standard.set(nextUp.map(\.id), forKey: Self.rememberedNextUpKey)
    }

    func showRememberedNextUp() {
        guard let ids = UserDefaults.standard.stringArray(forKey: Self.rememberedNextUpKey),
              !ids.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, self.nextUp.isEmpty,
                  let entries = try? await self.repository.entriesById(ids) else { return }
            // In the remembered order, and never over a real answer that
            // arrived while this was reading.
            let byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            let ordered = ids.compactMap { byId[$0] }.filter { !$0.isPlayed }
            if self.nextUp.isEmpty { self.nextUp = ordered }
        }
    }
}

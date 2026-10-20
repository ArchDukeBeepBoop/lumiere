import Foundation
import Observation
import LumiereKit

/// What you chose to watch next, in your order: films, episodes and videos
/// from anywhere in the library, played before the rest of the season.
///
/// Temporary by design — it lives as long as the app — and made permanent
/// by saving it as a playlist on the server, where the phone and the TV can
/// play it too. Playing a saved playlist loads it back into this.
@MainActor
@Observable
final class PlayQueue {
    static let shared = PlayQueue()

    private(set) var entries: [LibraryEntry] = []
    /// The saved playlist this queue came from, if any.
    private(set) var playlistName: String?

    var isEmpty: Bool { entries.isEmpty }

    /// Next, ahead of everything else queued.
    func playNext(_ entry: LibraryEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    /// At the end.
    func add(_ entries: [LibraryEntry]) {
        for entry in entries where !self.entries.contains(where: { $0.id == entry.id }) {
            self.entries.append(entry)
        }
    }

    func remove(_ id: String) { entries.removeAll { $0.id == id } }

    func move(from: IndexSet, to: Int) { entries.move(fromOffsets: from, toOffset: to) }

    func clear() {
        entries = []
        playlistName = nil
    }

    /// Replaces the queue with a saved playlist's contents.
    func load(_ entries: [LibraryEntry], playlist name: String) {
        self.entries = entries.filter { Self.isPlayable($0) }
        playlistName = name
    }

    /// Takes the next item off the front, skipping the one now playing.
    func takeNext(after playingId: String?) -> LibraryEntry? {
        entries.removeAll { $0.id == playingId }
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    /// Only things that play: a show or a collection is not a queue item.
    static func isPlayable(_ entry: LibraryEntry) -> Bool {
        switch entry.item.itemType {
        case .movie, .episode, .video: return true
        default: return false
        }
    }
}

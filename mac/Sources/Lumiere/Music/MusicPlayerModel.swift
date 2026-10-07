import Foundation
import Observation
import AVFoundation
import LumiereKit

/// The music player: a queue that outlives whatever screen you are on.
///
/// Deliberately not the video engine. `PlayerEngine` exists to answer questions
/// music never asks — which container, whether to burn in subtitles, whether the
/// GPU can take this HDR profile — and it owns the whole window while it plays.
/// Music is the opposite: one stream, no chrome, and it has to keep going while you
/// browse somewhere else entirely.
///
/// `AVQueuePlayer` holding every remaining track is what makes it gapless. Feeding
/// items one at a time on `didPlayToEndTime` cannot be: the next file only starts
/// buffering once the previous one has already stopped, which is audible between
/// tracks of a continuous album. The cost is that any jump, shuffle or reorder
/// rebuilds the queue, which is cheap and happens while nothing is playing anyway.
@MainActor
@Observable
final class MusicPlayerModel {

    enum RepeatMode: String, CaseIterable {
        case off, all, one

        var icon: String {
            switch self {
            case .off, .all: return "repeat"
            case .one: return "repeat.1"
            }
        }
    }

    private(set) var queue: [LibraryEntry] = []
    var currentIndex: Int = 0
    private(set) var isPlaying = false {
        didSet {
            guard oldValue != isPlaying else { return }
            // The same focus the video player takes. See AppModel+Playback.swift.
            onPlaybackStateChange?()
        }
    }

    /// Set by `AppModel` so music can join the app's playback focus. A closure
    /// rather than a back-reference, because this model is built before the
    /// AppModel that owns it and must not retain it.
    var onPlaybackStateChange: (() -> Void)?
    var position: Double = 0
    var duration: Double = 0
    /// The window-filling player. A third size rather than a second: the mini bar
    /// is for music you have stopped thinking about, the panel is for reaching the
    /// queue, and this is for when the music is what you are doing.
    var isFullscreen = false

    var repeatMode: RepeatMode = .off
    private(set) var isShuffled = false

    /// The order tracks were handed to us, so turning shuffle off restores it rather
    /// than leaving the shuffled order as the new truth.
    private var originalQueue: [LibraryEntry] = []

    /// 0…1, applied to the player and kept across track changes.
    var volume: Double = 1 {
        didSet { player?.volume = Float(volume) }
    }
    var isMuted = false {
        didSet { player?.volume = isMuted ? 0 : Float(volume) }
    }

    var player: AVQueuePlayer?
    var timeObserver: Any?
    var endObserver: NSObjectProtocol?
    var serverURL: URL?
    var deviceId: String?
    var token: String?
    /// The last queue index stocked into the player. The window is refilled from
    /// here rather than loading the whole queue up front.
    var loadedThrough: Int = -1
    /// Identifies our own player items, so the end-of-track notification can be told
    /// apart from the video player's.
    var ourItemIDs: Set<ObjectIdentifier> = []

    var current: LibraryEntry? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var hasQueue: Bool { !queue.isEmpty }

    var canGoBack: Bool { currentIndex > 0 || position > 3 }
    var canGoForward: Bool { currentIndex < queue.count - 1 || repeatMode == .all }

    // MARK: - Wiring

    func configure(serverURL: URL, deviceId: String, token: String) {
        self.serverURL = serverURL
        self.deviceId = deviceId
        self.token = token
    }

    // MARK: - Transport

    /// Starts a queue at `index`. The whole album is handed over, not one track, so
    /// "play this song" and "play this album from here" are the same call.
    func play(_ entries: [LibraryEntry], startingAt index: Int = 0) {
        guard !entries.isEmpty else { return }
        originalQueue = entries
        queue = isShuffled ? shuffled(entries, keepingFirst: index) : entries
        currentIndex = isShuffled ? 0 : min(index, entries.count - 1)
        rebuildPlayer(startingAt: currentIndex)
        resume()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Back within the first few seconds means "previous track"; later it means
    /// "start this one again" — the convention every music player shares, and the
    /// reason `canGoBack` is true even on the first track.
    func previous() {
        if position > 3 {
            seek(to: 0)
            return
        }
        guard currentIndex > 0 else {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        rebuildPlayer(startingAt: currentIndex)
        resume()
    }

    func next() {
        advance(automatic: false)
    }

    func seek(to seconds: Double) {
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
        position = seconds
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        rebuildPlayer(startingAt: index)
        resume()
    }

    /// Advances off → all → one → off.
    ///
    /// Was written inline in the mini bar; two players cycling the same setting
    /// need one definition of what "next" means or they drift apart.
    func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard hasQueue else { return }

        if isShuffled {
            queue = shuffled(originalQueue, keepingFirst: currentIndex)
            currentIndex = 0
        } else {
            // Land on wherever the currently playing track sits in the real order,
            // so unshuffling mid-album continues rather than jumping.
            let playing = current?.id
            queue = originalQueue
            currentIndex = queue.firstIndex { $0.id == playing } ?? 0
        }
        rebuildPlayer(startingAt: currentIndex)
        if isPlaying { resume() }
    }

    /// Drops a track from the queue without disturbing what is playing.
    ///
    /// Removing something *after* the current track only needs the lookahead window
    /// rebuilt; removing something before it just shifts the index. Neither should
    /// interrupt audio, which is why this does not simply call `rebuildPlayer` in
    /// every case — doing so would restart the current song.
    func remove(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removedId = queue[index].id
        originalQueue.removeAll { $0.id == removedId }

        if index == currentIndex {
            queue.remove(at: index)
            if queue.isEmpty { return clear() }
            currentIndex = min(currentIndex, queue.count - 1)
            rebuildPlayer(startingAt: currentIndex)
            resume()
            return
        }

        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
        // Anything already handed to the player has to be rebuilt, but only from the
        // *next* track — the current one keeps playing untouched.
        if index > currentIndex, index <= loadedThrough {
            restockAfterCurrent()
        }
    }

    /// Queues a track to play straight after the current one.
    func playNext(_ entry: LibraryEntry) {
        guard hasQueue else { return play([entry]) }
        let target = min(currentIndex + 1, queue.count)
        queue.insert(entry, at: target)
        originalQueue = queue
        restockAfterCurrent()
    }

    func toggleMute() { isMuted.toggle() }

    func clear() {
        teardown()
        ourItemIDs = []
        loadedThrough = -1
        queue = []
        originalQueue = []
        currentIndex = 0
        isPlaying = false
        position = 0
        duration = 0
    }

    private func shuffled(_ entries: [LibraryEntry], keepingFirst index: Int) -> [LibraryEntry] {
        guard entries.indices.contains(index) else { return entries.shuffled() }
        var rest = entries
        let chosen = rest.remove(at: index)
        return [chosen] + rest.shuffled()
    }
}

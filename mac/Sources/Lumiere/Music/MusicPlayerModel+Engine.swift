import Foundation
import AVFoundation
import LumiereKit

/// The AVFoundation half of the music player: building the queue, observing it, and
/// advancing at the end of a track.
///
/// Split from MusicPlayerModel.swift so the transport logic above stays readable as
/// transport logic, and to keep both files under the project's 300-line limit.
extension MusicPlayerModel {

    /// How far ahead the queue is stocked.
    ///
    /// Gapless needs the *next* item prepared while the current one plays; it does
    /// not need the whole album. Loading everything was what made pressing play on a
    /// track feel slow — a 500-song Tracks view built 500 `AVPlayerItem`s up front,
    /// each starting its own asset load, before a note came out. Four is enough to
    /// stay seamless across a track change with a slow refill.
    private static var lookahead: Int { 4 }

    /// Rebuilds the underlying player from `index`.
    ///
    /// `AVQueuePlayer` with a small window is what keeps playback gapless: it
    /// prepares the next item while the current one is still going. Handing it one
    /// item at a time and appending on `didPlayToEndTime` cannot be gapless by
    /// construction — the next file only begins buffering after the previous has
    /// ended, and on a continuous album that gap is audible.
    func rebuildPlayer(startingAt index: Int) {
        teardown()

        guard let items = makeItems(from: index, count: Self.lookahead), !items.isEmpty else {
            return
        }
        loadedThrough = index + items.count - 1

        let player = AVQueuePlayer(items: items)
        player.volume = isMuted ? 0 : Float(volume)
        // Start now rather than buffering ahead first. The default waits until it
        // believes it can play through without stalling, which on a LAN server adds
        // a beat of silence to every single track for a stall that was never going
        // to happen.
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player

        observe(player)
        position = 0
        duration = 0
    }

    /// Builds up to `count` player items starting at `index`.
    func makeItems(from index: Int, count: Int) -> [AVPlayerItem]? {
        guard let serverURL, let deviceId, let token else { return nil }
        guard queue.indices.contains(index) else { return [] }

        let upper = min(index + count, queue.count)
        let items: [AVPlayerItem] = queue[index..<upper].compactMap { entry in
            guard let url = StreamBuilder.audioStreamURL(
                serverURL: serverURL, itemId: entry.id, deviceId: deviceId
            ) else { return nil }
            // Header, not query string — the same way the video engine authenticates.
            // See `StreamBuilder.audioStreamURL`.
            let asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": ["X-Emby-Token": token]]
            )
            return AVPlayerItem(asset: asset)
        }
        // Recorded so the end-of-track observer can tell our items from the video
        // player's, which posts the same notification.
        ourItemIDs.formUnion(items.map(ObjectIdentifier.init))
        return items
    }

    /// Tops the window back up as playback moves through it, so the queue never runs
    /// dry mid-album without ever holding the whole thing.
    func refillLookahead() {
        guard let player, loadedThrough < queue.count - 1 else { return }
        let next = loadedThrough + 1
        guard let items = makeItems(from: next, count: Self.lookahead - player.items().count),
              !items.isEmpty
        else { return }

        for item in items where player.canInsert(item, after: player.items().last) {
            player.insert(item, after: player.items().last)
        }
        loadedThrough = next + items.count - 1
    }

    private func observe(_ player: AVQueuePlayer) {
        // Four times a second: enough for a scrubber to look continuous, few enough
        // that it is not redrawing the whole bar on every frame.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds
                if let item = player.currentItem {
                    let length = item.duration.seconds
                    if length.isFinite, length > 0 { self.duration = length }
                }
            }
        }

        // Scoped to our own items rather than to every AVPlayerItem in the process:
        // the video player posts this same notification, and without the filter
        // finishing a film would skip the music queue forward.
        //
        // Checked against a property rather than a captured snapshot, because the
        // lookahead window keeps inserting new items after this observer is
        // installed — a set captured here would stop recognising them by the second
        // track. The identifier is extracted outside the isolation block because a
        // Notification is not Sendable and Swift 6 will not let one cross into the
        // actor at all.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let finished = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            guard let finished else { return }
            MainActor.assumeIsolated {
                guard let self, self.ourItemIDs.contains(finished) else { return }
                self.advance(automatic: true)
            }
        }
    }

    /// Moves to the next track.
    ///
    /// `automatic` separates "the track ended" from "the user pressed next", which is
    /// the only place repeat-one is allowed to act — otherwise pressing next on a
    /// repeating track would refuse to go anywhere, which reads as a broken button.
    func advance(automatic: Bool) {
        if automatic, repeatMode == .one {
            // Rebuilt, not seeked. AVQueuePlayer dequeues the finished item and
            // advances `currentItem` before the end notification is delivered, so
            // seeking to zero rewound the *next* track — which then played from the
            // start while the mini bar still showed the previous title, and the
            // track that was supposed to repeat was already gone from the queue.
            rebuildPlayer(startingAt: currentIndex)
            resume()
            return
        }

        guard currentIndex < queue.count - 1 else {
            if repeatMode == .all, !queue.isEmpty {
                currentIndex = 0
                rebuildPlayer(startingAt: 0)
                resume()
            } else {
                pause()
                seek(to: 0)
            }
            return
        }

        currentIndex += 1
        if automatic {
            // The queue player has already moved itself along, so nothing needs
            // rebuilding — that is the point of keeping a window stocked ahead of it.
            position = 0
            duration = 0
            refillLookahead()
        } else {
            rebuildPlayer(startingAt: currentIndex)
            resume()
        }
    }

    /// Drops everything queued behind the current track and re-stocks the window.
    ///
    /// The point is that the *current* item is left alone: `AVQueuePlayer` lets its
    /// tail be removed without touching what is playing, so reordering the queue
    /// never interrupts audio.
    func restockAfterCurrent() {
        guard let player else { return }
        for item in player.items().dropFirst() { player.remove(item) }
        loadedThrough = currentIndex
        refillLookahead()
    }

    func teardown() {
        // Dropped with the player that owned them. An ObjectIdentifier is the
        // object's address and the allocator reuses addresses, so a set that only
        // ever grew would eventually match an AVPlayerItem belonging to the *video*
        // player at a recycled address — and finishing a film would skip the music
        // queue forward, which is the exact cross-contamination this set exists to
        // prevent. Cleared here rather than while restocking, because a track that
        // is finishing right now is already out of `player.items()` and pruning
        // against that would discard the id the end observer is about to look up.
        ourItemIDs.removeAll()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

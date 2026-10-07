import Foundation
import LumiereKit

/// Getting out of the player's way while it is playing.
///
/// A 45,000-item sync and a video decode want the same CPU, the same disk and the
/// same network, and the app was letting them fight: launching straight into a film
/// produced mpv's "Audio/Video desynchronisation detected — possible reasons include
/// too slow hardware, temporary CPU spikes" while a full library scan ran behind it.
/// Nothing here makes the machine faster; it stops Lumiere competing with itself.
extension AppModel {

    /// Whether libmpv loaded, waiting for the probe if it is still running.
    func mpvReady() async -> Bool {
        await mpvProbe?.value
        return mpvAvailable
    }

    /// Joins music to the app's playback focus. Called from `init`, so it holds for
    /// the demo library and for anything that plays before a server is reachable.
    /// `[weak self]` because the model is a stored property of this one.
    func adoptMusicPlayback() {
        music.onPlaybackStateChange = { [weak self] in self?.playbackStateChanged() }
    }

    /// Whether anything is playing that a person is watching or listening to.
    ///
    /// Music counts. A track skipping because a library scan chose that moment to
    /// decode two hundred posters is the same failure as a dropped frame, and the
    /// audio path has a smaller buffer to absorb it with.
    var isPresentingMedia: Bool { nowPlayingItemId != nil || music.isPlaying }

    /// Called whenever `nowPlayingItemId` changes, and whenever music starts or
    /// stops. Idempotent, because those two can overlap and each other's ends must
    /// not tear down focus the other still wants.
    func playbackStateChanged() {
        // Written while something plays and cleared when it stops, so a launch
        // that finds it knows the last session ended mid-episode.
        InterruptedPlayback.note(nowPlayingItemId)
        if isPresentingMedia {
            beginPlaybackFocus()
        } else {
            endPlaybackFocus()
        }
    }

    private func beginPlaybackFocus() {
        // Artwork prefetching is the worst offender: it decodes full-size JPEGs in
        // a loop, which is pure CPU and exactly what a software decode path is
        // short of. It resumes when the film ends — it is a cache warmer with no
        // deadline, and no part of it is worth a dropped frame.
        // `Task` because the prefetcher is an actor: this hop is the only way to
        // reach it from a synchronous `didSet`, and a cache warmer taking a moment
        // longer to stop costs nothing.
        if let prefetcher { Task { await prefetcher.cancel() } }

        // The artwork auto-fetcher too, for the same reason and more so: it is a
        // long server-side scrape that writes back as it goes, so it costs network,
        // disk and CPU at once. Unlike the prefetcher it does not resume by itself —
        // it is a job someone starts, and silently restarting a write-heavy pass
        // against their server is not a decision this should make on its own.
        // `Task` for the same reason as the prefetcher: it is an actor, and this is
        // a synchronous `didSet`.
        if let artworkFetcher {
            Task {
                guard await artworkFetcher.isRunning else { return }
                Diagnostics.log("[playback] stopping the artwork fetch while media plays")
                await artworkFetcher.cancel()
            }
        }

        // Tells macOS this process is doing something a person is watching.
        //
        // Without an assertion the app is subject to App Nap and, more to the point,
        // to timer coalescing — the kernel bunches timer fires together to save
        // power, which is precisely the wrong behaviour for a renderer trying to
        // hit a frame deadline, and a plausible contributor to the desync above.
        // `latencyCritical` opts out of that.
        //
        // `idleDisplaySleepDisabled` because a video player whose screen goes dark
        // forty minutes in is broken, and nothing else in this app was preventing it.
        guard playbackActivity == nil else { return }
        // The display is only kept awake for video. Music with the lid open should
        // not stop the screen sleeping — that is a battery cost with nothing to look
        // at, and the audio keeps playing across a display sleep regardless.
        var options: ProcessInfo.ActivityOptions = [.userInitiated, .latencyCritical]
        if nowPlayingItemId != nil { options.insert(.idleDisplaySleepDisabled) }
        playbackActivity = ProcessInfo.processInfo.beginActivity(
            options: options, reason: "Media playback"
        )
    }

    private func endPlaybackFocus() {
        if let playbackActivity {
            ProcessInfo.processInfo.endActivity(playbackActivity)
            self.playbackActivity = nil
        }

        // Whatever was held back while the film ran.
        guard deferredSyncIsFull != nil else { return }
        let full = deferredSyncIsFull == true
        deferredSyncIsFull = nil
        Diagnostics.log("[playback] finished — running the sync that was held back")
        startSync(full: full, userInitiated: false)
    }

    /// Whether an automatic sync should wait.
    ///
    /// Automatic only. A sync someone pressed a button for runs immediately and
    /// always has: they asked for it while a film was on screen, which is a clearer
    /// statement of intent than any rule this could apply.
    func deferSyncDuringPlayback(full: Bool) -> Bool {
        guard isPresentingMedia else { return false }
        // A full pass wins over an incremental one if both are held back.
        deferredSyncIsFull = (deferredSyncIsFull == true) || full
        Diagnostics.log("[playback] holding a sync back until the video ends")
        return true
    }

    /// Surfaces a failure to the user, and clears it after a while.
    ///
    /// Lives here only for AppModel.swift's line limit; it is general-purpose.
    func report(
        _ message: String, actionTitle: String = "Undo",
        undo: (@MainActor () async -> Void)? = nil
    ) {
        transientMessage = message
        transientUndo = undo
        Self.bannerActionTitle = actionTitle
        let shown = message
        Task {
            try? await Task.sleep(for: .seconds(6))
            // Only clears its own message: a later failure that arrived while this
            // was on screen must not be wiped by this one's timer.
            if transientMessage == shown {
                transientMessage = nil
                transientUndo = nil
            }
        }
    }

    /// The banner button's words — "Undo" unless a message says otherwise.
    static var bannerActionTitle = "Undo"
    private static var checkedInterruption = false

    /// On launch: if the last session quit mid-episode, say so and offer to
    /// carry on. The position is already saved — the player writes it every
    /// few seconds — so Resume simply opens the episode where it was left.
    func offerInterruptedPlayback() async {
        // Once per launch, and never over something already playing — which
        // would be this session's own episode, not the last one's.
        guard !Self.checkedInterruption, nowPlayingItemId == nil else { return }
        Self.checkedInterruption = true
        guard let id = InterruptedPlayback.pending() else { return }
        InterruptedPlayback.note(nil)
        guard let entry = try? await repository?.entry(id: id), !entry.isPlayed else { return }
        report("Lumiere closed while \(entry.item.name) was playing.", actionTitle: "Resume") { [weak self] in
            self?.nowPlayingItemId = id
        }
    }
}

/// The item that was playing, kept until playback ends cleanly.
enum InterruptedPlayback {
    private static let key = "interruptedPlayback"
    static func note(_ id: String?) { UserDefaults.standard.set(id, forKey: key) }
    static func pending() -> String? { UserDefaults.standard.string(forKey: key) }
}

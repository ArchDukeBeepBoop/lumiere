import Foundation
import LumiereKit
import LumierePlayer

/// Play, pause, seek and the rest of the transport.
///
/// Split from PlayerModel.swift for the project's 300-line limit. It is the half
/// that talks to the engine, where the rest is state the views read.
@MainActor
extension PlayerModel {

    // MARK: - Transport

    func togglePlayPause() async {
        guard let engine else { return }
        if state == .playing {
            await engine.pause()
            state = .paused
        } else if state == .paused {
            await engine.play()
            state = .playing
        }
        await report(force: true)
    }

    func seek(to seconds: Double, precise: Bool = true) async {
        guard let engine else { return }
        // Noted before the position moves, since learning is about the jump.
        let from = position
        position = seconds
        await engineSeek(engine, to: seconds, precise: precise)
        await noteSeekForIntroLearning(from: from, to: seconds)
        // Detached from the seek rather than awaited. The report is a network
        // round trip, and a caller that waits for it is a caller that has
        // finished moving the picture and is now holding everything up for the
        // server's benefit — on a slow one, for the length of its timeout.
        // Nothing here reads the result, and the local write inside it is a
        // single-row update that cannot fail that way.
        Task { await report(force: true) }
    }

    /// Watches forward seeks for the shape of an intro skip.
    ///
    /// Only where the server offered no segment for this moment: a show with
    /// real segment data does not need to be guessed at, and learning from a
    /// press of a button this app itself drew would teach it its own output.
    ///
    /// Every judgement about what counts lives in `IntroLearning`, which is pure
    /// and tested. This is only the part that needs a player: which series, and
    /// whether the server already knew.
    private func noteSeekForIntroLearning(from: Double, to: Double) async {
        guard let seriesId = introSeriesId,
              IntroLearning.isIntroSkip(from: from, to: to),
              !segments.contains(where: { $0.skipLabel != nil && from >= $0.start && from < $0.end })
        else { return }
        learnedIntro = try? await repository.recordIntroSkip(
            seriesId: seriesId, from: from, to: to
        )
    }

    /// One engine seek, counted, so ticks from before it landed are ignored.
    func engineSeek(_ engine: any PlayerEngine, to seconds: Double, precise: Bool) async {
        seeksInFlight += 1
        let started = ContinuousClock.now
        await engine.seek(to: seconds, precise: precise)
        seeksInFlight -= 1
        // Only the slow ones. "Seeking lags on 4K" is a report this line can
        // answer with a number, and a line per drag event would bury it.
        let cost = ContinuousClock.now - started
        if cost > .milliseconds(250) {
            Diagnostics.log("[seek] \(precise ? "exact" : "keyframe") to \(Int(seconds))s"
                            + " took \(cost.components.seconds * 1000 + cost.components.attoseconds / 1_000_000_000_000_000)ms"
                            + " (\(videoWidth ?? 0)px wide)")
        }
    }

    /// A quick seek from a key press, coalesced.
    ///
    /// The arrow keys used to call `seek(to:)`, and `seek(to:)` does three
    /// expensive things: a *precise* seek, which on a transcoded stream forces
    /// the decoder to rebuild from the nearest keyframe and walk forward; a
    /// database write, when the jump looks like an intro skip; and a playback
    /// report, which is a network round trip. One press paid all three. Holding
    /// the key paid them several times a second, and each precise seek queued
    /// behind the last — which is the lag.
    ///
    /// So a press now does the cheap thing: an imprecise seek, which lands
    /// within half a second and lets the picture keep up. The three expensive
    /// things happen once, after the seeking stops. This is the same division
    /// the scrubber already made between `scrub(to:)` and `seek(to:)`; the
    /// keyboard simply never got it.
    func nudge(by seconds: Double) async {
        guard engine != nil else { return }
        let target = max(0, min(duration, position + seconds))
        position = target
        await scrub(to: target)

        settleTask?.cancel()
        settleTask = Task { [weak self] in
            // Long enough that a run of presses is one settle, short enough that
            // a single press lands exactly where it said within a blink.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            // On a keyframe, not the exact second — mpv's own arrow keys do the
            // same. A step is "about ten seconds on", and decoding forward to
            // make it exactly ten was a second jump of the picture a moment
            // after the first, on a 4K file a long moment.
            await self.seek(to: self.position, precise: false)
        }
    }

    /// The menu's skip commands: one direction-aware step, as an arrow key.
    func skip(by seconds: Double) async {
        await keyStep(by: seconds, isRepeat: false)
    }

    /// Called on stop and on window close. This is what writes the resume
    /// position, so it must run even when the user just closes the window.
    func finish(markPlayed: Bool = false) async {
        guard didStart, let mediaSourceId else {
            await engine?.stop()
            return
        }

        let finalPosition = position
        await engine?.stop()

        // Stopped in the credits: watched, here and on the server. See
        // `WatchedAtCredits`.
        let markPlayed = markPlayed || (Preference.watchedAtCredits.value && WatchedAtCredits.counts(
            position: finalPosition, duration: duration,
            outroStarts: segments.filter { $0.isOutro && $0.isWellFormed }.map { ($0.start, $0.end) },
            floorMinutes: Preference.creditsWindowMinutes.value))
        if markPlayed { try? await client.markPlayed(itemId: itemId, played: true) }

        // Locally first, and that ordering is the whole point of this comment.
        //
        // The server call below can block for the full 60-second request timeout
        // when the server is asleep — and this runs from `onDisappear`, in a task
        // nothing waits for. Closing the window and quitting is an ordinary thing
        // to do, and with the network call first it took the local write down with
        // it: the app knew where you were up to and wrote it nowhere. A SQLite
        // update to one row cannot fail that way, so it goes first and the report
        // follows.
        try? await repository.applyLocalProgress(
            itemId: itemId,
            positionSeconds: markPlayed ? 0 : finalPosition,
            played: markPlayed ? true : nil
        )

        try? await client.reportPlaybackStopped(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionSeconds: finalPosition
        )
        didStart = false
    }
}

import Foundation
import CMPV
import LumiereKit

/// mpv's transport commands and property reads.
///
/// Split from MPVEngine.swift for the project's 300-line limit, and along the
/// seam that already existed: everything here is a command sent to a running
/// handle, where the rest of the engine is about getting one running at all.
extension MPVEngine {

    // MARK: - Transport

    public func play() async {
        setProperty("pause", "no")
        cachedPaused = false
        checkForPicture()
    }

    /// Three seconds after play, ask whether anything has actually been drawn.
    ///
    /// Three because a first frame on a network stream can take a couple of
    /// seconds and a false alarm in the log is worse than none — and detached
    /// because this must not hold up the transport.
    ///
    /// Reported rather than acted on. There is no honest automatic recovery here:
    /// the app cannot know whether the fix is a different hardware decoder, a
    /// different scaler or a file the machine simply cannot decode, and switching
    /// blindly would trade one silent failure for another.
    private func checkForPicture() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, await self.isPlaying else { return }
            let format = [
                self.stringProperty("video-codec") ?? "?",
                self.stringProperty("video-format") ?? "?",
                self.stringProperty("hwdec-current") ?? "no",
            ].joined(separator: "/")
            self.view.reportIfBlank(format: format)

            // The decode path, from the same read that built `format` above.
            //
            // Logged here and not at the first frame, which is where it was and why
            // it lied: `hwdec-current` is still "no" when the first tick arrives, so
            // a one-shot read there reported Software on files mpv was decoding in
            // hardware — and that false report is what sent a whole afternoon into
            // rewriting the video surface for a problem that did not exist. Three
            // seconds in, the property has settled.
            let decoder = self.stringProperty("hwdec-current")
            let path = (decoder == "no" || decoder?.isEmpty != false)
                ? "Software" : "Hardware (\(decoder!))"
            Diagnostics.log("[playback] decode: \(path)")

            // Half a minute in, how smooth it has been. Dropped is frames the
            // decoder never delivered in time; delayed is frames the display
            // showed late. "The video looks choppy" is answered by these two.
            try? await Task.sleep(for: .seconds(27))
            guard await self.isPlaying else { return }
            Diagnostics.log("[playback] after 30s: dropped "
                            + "\(self.intProperty("frame-drop-count") ?? -1), delayed "
                            + "\(self.intProperty("vo-delayed-frame-count") ?? -1), "
                            + "vf fps \(self.doubleProperty("estimated-vf-fps").map { String(format: "%.2f", $0) } ?? "?")")
        }
    }

    public func pause() async {
        setProperty("pause", "yes")
        cachedPaused = true
    }

    public func seek(to seconds: Double) async {
        await seek(to: seconds, precise: true)
    }

    /// Returns once mpv has shown the frame it landed on — or after a bounded
    /// wait, if it never says.
    ///
    /// Fire-and-forget is what made scrubbing lurch: a drag issued seeks faster
    /// than the decoder retired them, and every caller believed each one had
    /// happened. Waiting for `MPV_EVENT_PLAYBACK_RESTART` makes the call mean
    /// what it says, so a caller that wants to coalesce — issue the next seek
    /// only when the last has landed — can. The wait is capped because a seek
    /// into a stalled network stream may never restart, and a transport that
    /// hangs on that is worse than one that lies.
    /// Relative, which mpv lands in the direction of travel — its own arrow
    /// keys work this way. See `PlayerEngine.step`.
    public func step(by seconds: Double, from: Double) async {
        guard handle != nil else { return }
        commandAsync(["seek", String(seconds), "relative+keyframes"])
        cachedPosition = from + seconds
        await waitForSeek()
    }

    public func seek(to seconds: Double, precise: Bool) async {
        guard handle != nil else { return }
        // "keyframes" is mpv's fast path: it jumps to the nearest index point rather
        // than decoding forward to the exact frame, which is what lets the picture
        // track a drag instead of trailing behind it.
        commandAsync(["seek", String(seconds), "absolute", precise ? "exact" : "keyframes"])
        cachedPosition = seconds
        await waitForSeek()
    }

    /// Until the seek just sent has landed, or two seconds.
    private func waitForSeek() async {
        seekTicket += 1
        let ticket = seekTicket
        await withCheckedContinuation { continuation in
            seekWaiters[ticket] = continuation
            Task { [weak self] in
                // Two seconds: longer than any seek that is going to land at
                // all. A shorter cap looked reasonable and was not — a 4K
                // keyframe over HTTP takes half a second, and a cap under that
                // let the next seek go out while the last was still decoding,
                // which is the backlog the wait exists to prevent.
                try? await Task.sleep(for: .seconds(2))
                self?.seekWaiters.removeValue(forKey: ticket)?.resume()
            }
        }
    }

    /// Every seek issued before this restart has landed — mpv coalesces the
    /// backlog into one, so one restart answers them all.
    func settleSeeks() {
        let waiting = seekWaiters
        seekWaiters.removeAll()
        waiting.values.forEach { $0.resume() }
    }

    public func setRate(_ rate: Double) async {
        setProperty("speed", String(rate))
    }

    /// mpv's own loop, so the repeat happens inside the player rather than as a
    /// seek after the fact.
    ///
    /// The seam is what that avoids: a file that reports its end, gets seeked to
    /// zero and told to play again drops frames and re-buffers audibly at the
    /// join. `loop-file=inf` never reaches the end at all — and never emits
    /// `endReached`, so nothing downstream mistakes a repeat for a finished file
    /// and queues the next episode.
    /// mpv steps natively, and pauses itself doing it — which is the behaviour
    /// anyone wants: stepping is something you do while looking at one frame.
    public func step(frames: Int) async {
        guard frames != 0 else { return }
        let name = frames > 0 ? "frame-step" : "frame-back-step"
        for _ in 0..<abs(frames) { command([name]) }
    }

    public func setLooping(_ looping: Bool) async {
        setProperty("loop-file", looping ? "inf" : "no")
    }

    public func selectAudioTrack(id: Int?) async {
        setProperty("aid", id.map(String.init) ?? "no")
    }

    public func selectSubtitleTrack(id: Int?) async {
        setProperty("sid", id.map(String.init) ?? "no")
    }

    public func stop() async {
        guard let handle else { return }

        // Order matters twice over. The render context holds a reference to the
        // handle, so it goes first. Then mpv is asked to quit and the event pump
        // destroys the handle when it sees MPV_EVENT_SHUTDOWN — see the note
        // there for why this cannot be done from here.
        view.destroyRenderContext()
        command(["quit"], on: handle)

        self.handle = nil
        eventPump = nil
    }
}

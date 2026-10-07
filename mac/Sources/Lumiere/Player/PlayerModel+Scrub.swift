import Foundation
import LumiereKit
import LumierePlayer

/// Seeking while the hand is still on the control: the scrubber's drag, a held
/// arrow key, two fingers on the trackpad.
///
/// Split from PlayerModel+Transport.swift for the project's 300-line limit,
/// and along its own seam: everything here is about a seek that is not yet
/// the final one.
@MainActor
extension PlayerModel {

    /// A seek made while the scrubber is still under the cursor, or a key is
    /// still down.
    ///
    /// Imprecise so the picture can keep up, and coalesced: at most one seek
    /// is out at a time, and the newest target replaces any that is waiting.
    /// A drag emits events far faster than any decoder can seek, and the old
    /// timer throttle still let several queue behind one slow keyframe — the
    /// picture then played the backlog, lurching through places the cursor
    /// had already left. Now it goes where the hand is, and nowhere else.
    ///
    /// Deliberately silent: a drag across a two-hour film would otherwise post
    /// dozens of playback positions to the server, none of which is where the
    /// user ends up. The precise `seek(to:)` on release is the one that reports.
    func scrub(to seconds: Double) async {
        guard let engine else { return }
        pendingScrub = seconds
        position = seconds
        guard !isScrubSeekInFlight else { return }
        isScrubSeekInFlight = true
        defer { isScrubSeekInFlight = false }
        while let target = pendingScrub {
            pendingScrub = nil
            let started = ContinuousClock.now
            await engineSeek(engine, to: target, precise: false)
            // A slow seek — a 4K keyframe in software — is followed by a short
            // rest before the next. While the hand is moving, the target at the
            // end of the rest is newer than the one at its start, so the picture
            // lands where the hand is going rather than one stale place behind
            // it; and when the hand stops, one seek is issued rather than two.
            if ContinuousClock.now - started > .milliseconds(120), pendingScrub != nil {
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// The scrubber has been grabbed.
    ///
    /// By preference, the sound stops for the length of the drag: a picture
    /// that follows a hand across a film passes a keyframe every few frames,
    /// and audio decoded from each of them is a stutter, not a preview.
    func beginScrub() async {
        guard let engine, Preference.pausesWhileScrubbing.value else { return }
        resumesAfterScrub = state == .playing
        guard resumesAfterScrub else { return }
        await engine.pause()
    }

    /// The scrubber has been released here. Lands exactly, then starts the
    /// picture again if `beginScrub` stopped it.
    func endScrub(at seconds: Double) async {
        pendingScrub = nil
        let landing = SeekLanding(rawValue: Preference.seekLanding.value) ?? .auto
        await seek(to: seconds, precise: landing.landsExactly(width: videoWidth))
        guard resumesAfterScrub, let engine else { return }
        resumesAfterScrub = false
        // Only if nothing else paused it in between — a Space pressed mid-drag
        // is a request, not an accident.
        guard state == .playing else { return }
        await engine.play()
    }

    /// A step from a scroll gesture. See `ScrollSeek`.
    ///
    /// The same coalesced path as a held key, and the same settle after: the
    /// exact seek, the intro learning and the report happen once, when the
    /// fingers lift.
    func scrollSeek(by seconds: Double) async {
        await nudge(by: seconds)
    }
}

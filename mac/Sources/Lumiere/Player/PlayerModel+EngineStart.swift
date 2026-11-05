import Foundation
import LumiereKit
import LumierePlayer

/// Building the engine a decision chose and loading the file into it — and,
/// when AVFoundation cannot open a file it was handed, trying mpv instead.
///
/// The container the server reports can be wrong. A file named .mp4 that is
/// really an MPEG transport stream (as recordings and some downloads are) was
/// sent to AVPlayer on the strength of its name, failed to open, and showed an
/// error — while the same file opened from the Finder, which always uses mpv,
/// played. mpv reads anything AVFoundation can and much more, so a direct play
/// that AVFoundation refuses gets one more try there before anything is shown.
extension PlayerModel {

    func startEngine(_ kind: PlaybackDecision.Engine, request: PlaybackRequest,
                     decision: PlaybackDecision, mpvAvailable: Bool) async -> LoadOutcome? {
        let outcome = await load(kind, request: request)
        guard kind == .avPlayer, decision.route == .directPlay, mpvAvailable else { return outcome }
        switch outcome {
        case .ok, .unavailable: return outcome
        case .failed, nil: break
        }
        Diagnostics.log("[playback] \(itemId) AVFoundation could not open it; trying mpv")
        await avEngine?.stop()
        avEngine = nil
        return await load(.mpv, request: request)
    }

    private func load(_ kind: PlaybackDecision.Engine, request: PlaybackRequest) async -> LoadOutcome? {
        let engine: any PlayerEngine
        switch kind {
        case .avPlayer:
            let av = AVPlayerEngine()
            avEngine = av
            engine = av
        case .mpv:
            let mpv = MPVEngine()
            mpvEngine = mpv
            engine = mpv
        }
        self.engine = engine
        attachCallbacks(to: engine)

        // Bounded, like every other network call in a session. An unbounded
        // load against an unreachable server left the player on a bare spinner
        // forever — and until the Close button was drawn in that state too,
        // there was no way out of it.
        return await Timeout.run(seconds: 30, operation: { () -> LoadOutcome? in
            do {
                try await engine.load(request)
                return .ok
            } catch PlayerEngineError.engineUnavailable(let detail) {
                return .unavailable(detail)
            } catch {
                return .failed(
                    (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
                )
            }
        })
    }
}

import Foundation
import CMPV
import LumiereKit

/// The event pump: mpv's own thread, and what it reports back.
///
/// Split from MPVEngine.swift for the project's 300-line limit. Kept whole rather
/// than divided further — the handle's lifetime is decided in here, and separating
/// the shutdown from the loop that observes it is how the segfault this comments
/// on came back the first time.
extension MPVEngine {

    // MARK: - Event pump

    /// mpv's event queue must be drained by someone, and `mpv_wait_event` blocks.
    /// A dedicated thread does it and hops each event back to the main actor.
    func startEventPump(_ handle: OpaquePointer) {
        // libmpv documents every call as thread-safe except mpv_wait_event,
        // which must not be called concurrently on one handle. Only this pump
        // calls it, so sharing the pointer is safe — the box states that rather
        // than scattering the assumption.
        let shared = MPVHandleBox(raw: handle)
        // LUMIERE_MPV_TRACE=1 logs every raw event id. Kept because "the engine
        // initialised and then nothing happened" is otherwise undiagnosable.
        let trace = ProcessInfo.processInfo.environment["LUMIERE_MPV_TRACE"] == "1"
        Diagnostics.log("[mpv] event pump started")

        let thread = Thread { [weak self] in
            while true {
                guard let event = mpv_wait_event(shared.raw, 0.1) else { continue }
                if event.pointee.event_id == MPV_EVENT_SHUTDOWN {
                    // The handle is destroyed *here*, on the pump thread, once
                    // mpv has acknowledged the quit. Destroying it from stop()
                    // frees it out from under this very mpv_wait_event call —
                    // a segfault, every time, as soon as a player is closed.
                    Diagnostics.log("[mpv] shutdown")
                    mpv_terminate_destroy(shared.raw)
                    return
                }
                if event.pointee.event_id == MPV_EVENT_NONE { continue }
                if trace {
                    let name = mpv_event_name(event.pointee.event_id).map { String(cString: $0) }
                    Diagnostics.log("[mpv/trace] \(name ?? "?")")
                }

                let parsed = MPVEvent(event.pointee)
                Task { @MainActor [weak self] in
                    self?.handle(parsed)
                }
            }
        }
        thread.name = "com.lumiere.mpv-events"
        thread.qualityOfService = .userInitiated
        thread.start()
        eventPump = thread
    }

    private func handle(_ event: MPVEvent) {
        switch event {
        case .timePosition(let seconds):
            cachedPosition = seconds
            onTick?(seconds)
        case .duration(let seconds):
            // Logged once: for a linked release this is the stitched length,
            // which is the only evidence outside the picture that the borrowed
            // segments were followed.
            Diagnostics.log("[mpv] duration \(Int(seconds))s")
            cachedDuration = seconds
        case .paused(let paused):
            cachedPaused = paused
        case .endReached:
            onEnded?()
        case .tracksChanged:
            reloadTracks()
        case .fileLoaded:
            reloadTracks()
        case .playbackRestarted:
            settleSeeks()
        case .error(let message):
            Diagnostics.log("[mpv] playback error: \(message)")
            onError?(PlayerEngineError.engineUnavailable(message))
        case .logMessage(let text, let level):
            forwardLogMessages(text, level: level)
        case .ignored:
            break
        }
    }
}

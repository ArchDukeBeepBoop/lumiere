import Foundation
import AppKit
import CMPV
import LumiereKit

/// The libmpv engine — the one that plays most of a real library.
///
/// Renders through libmpv's OpenGL render API into an `NSOpenGLView`, which is
/// the only embedding path libmpv supports on macOS. See `MPVVideoView` for why
/// the simpler-looking `wid` approach silently produces no frames.
@MainActor
public final class MPVEngine: PlayerEngine {

    public let view: MPVVideoView

    // Internal rather than private so the C bridge in MPVBridge.swift can reach
    // them; the split is for readability, not encapsulation.
    var handle: OpaquePointer?
    var eventPump: Thread?

    var cachedDuration: Double = 0
    var cachedPosition: Double = 0
    var cachedPaused = true
    var cachedAudioTracks: [MediaTrack] = []
    var cachedSubtitleTracks: [MediaTrack] = []
    var cachedVolume: Double = 1
    /// The current `volume-max`. The slider is scaled by this, so both setters
    /// agree on what full volume means.
    var cachedBoost: Double = 100
    var cachedMuted = false
    /// Seeks waiting for mpv to report the frame they landed on, by ticket.
    /// See `seek(to:precise:)`.
    var seekWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    var seekTicket = 0
    var cachedAmbientMode = false

    public var onTick: ((Double) -> Void)?
    public var onEnded: (() -> Void)?
    public var onError: ((Error) -> Void)?

    public init() {
        view = MPVVideoView()
    }

    // MARK: - State

    public var duration: Double { get async { cachedDuration } }
    public var position: Double { get async { cachedPosition } }
    public var isPlaying: Bool { get async { handle != nil && !cachedPaused } }
    public var audioTracks: [MediaTrack] { get async { cachedAudioTracks } }
    public var subtitleTracks: [MediaTrack] { get async { cachedSubtitleTracks } }

    // MARK: - Loading

    public func load(_ request: PlaybackRequest) async throws {
        if handle == nil {
            // The render context is created against the view's GL context, so
            // the view must be in a window first.
            await waitForWindow()
            try createHandle(for: request)
        }

        // Headers go through mpv rather than the URL, so the token never lands
        // in a server log. Same rule as the AVPlayer path.
        //
        // `http-header-fields` is a comma-separated list, so no header value may
        // contain a comma. That is not a detail: the auth header used to be the full
        // `MediaBrowser Client="...", Device="...", ...` value, which split into four
        // fragments and made the server answer 400 — direct play never worked against
        // a real server because of it, and mpv reported only "loading failed".
        //
        // mpv's documented `%length%` escape does not save it either; an escaped item
        // goes out as a header literally named `%185%Authorization`, which is just as
        // invalid. So any comma-bearing value is dropped with a complaint rather than
        // silently corrupting the request — see `JellyfinClient.streamingHeaders`,
        // which sends a comma-free `X-Emby-Token` for exactly this reason.
        if !request.httpHeaders.isEmpty {
            let usable = request.httpHeaders.filter { field in
                guard !field.value.contains(","), !field.key.contains(",") else {
                    Diagnostics.log("[mpv] dropping header '\(field.key)': mpv cannot carry a comma")
                    return false
                }
                return true
            }
            if !usable.isEmpty {
                let fields = usable.map { "\($0.key): \($0.value)" }.joined(separator: ",")
                setOption("http-header-fields", fields)
            }
        }

        // Resume position goes through the `start` option, not as a loadfile
        // argument. mpv 0.41's signature is `loadfile <url> [<flags> [<index>
        // [<options>]]]`, so appending "start=77" landed it in the *index* slot and
        // the whole command failed with "argument index can't be parsed" — meaning
        // every partially-watched item refused to play, which is most of a real
        // library. Setting the option first works on every mpv version.
        if request.startAt > 1 {
            setOption("start", String(Int(request.startAt)))
        }
        // Ordered chapters that borrow from other files. mpv follows them
        // natively, the way VLC does; over HTTP it cannot scan a folder for
        // the segments, so it is handed a playlist of where they are. Opened
        // with the same headers as the episode, which were set above.
        if request.linkedFiles.isEmpty {
            setOption("ordered-chapters", "no")
        } else {
            let playlist = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumiere-linked-\(UUID().uuidString).m3u")
            let body = (["#EXTM3U"] + request.linkedFiles.map(\.absoluteString))
                .joined(separator: "\n") + "\n"
            if (try? body.write(to: playlist, atomically: true, encoding: .utf8)) != nil {
                setOption("ordered-chapters", "yes")
                setOption("ordered-chapters-files", playlist.path)
                Diagnostics.log("[mpv] following \(request.linkedFiles.count) linked segment(s)")
            }
        }
        command(["loadfile", request.url.absoluteString, "replace"])

        if let index = request.preferredAudioTrack {
            setProperty("aid", String(index))
        }
        if let index = request.preferredSubtitleTrack {
            setProperty("sid", String(index))
        }
    }

    /// Resolves once the video view is in a window, or after a short grace
    /// period — mpv can still be created without one, it simply will not render,
    /// and hanging forever would be worse.
    private func waitForWindow() async {
        guard !view.isReady else { return }

        await withCheckedContinuation { continuation in
            var resumed = false
            view.onReady = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !resumed else { return }
                resumed = true
                Diagnostics.log("[mpv] view never reached a window; rendering may fail")
                continuation.resume()
            }
        }
    }
}

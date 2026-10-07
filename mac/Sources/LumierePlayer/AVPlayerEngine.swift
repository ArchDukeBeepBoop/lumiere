import Foundation
@preconcurrency import AVFoundation
import LumiereKit

/// The AVFoundation engine.
///
/// Used for the subset of a library AVPlayer genuinely handles well — MP4 and
/// MOV with H.264 or HEVC and AAC/AC3/EAC3. It is preferred there because it is
/// cheaper on battery than mpv, integrates with the system's Now Playing and
/// output routing, and needs no bundled dylibs.
/// Main-actor isolated because AVFoundation is: `AVPlayer`, `AVPlayerItem` and
/// `AVAsset` carry no `Sendable` conformance and are documented as main-thread
/// types. Isolating the engine is the honest fix; `@preconcurrency` here would
/// only silence the compiler about a real threading contract.
@MainActor
public final class AVPlayerEngine: NSObject, PlayerEngine {

    public let player = AVPlayer()

    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// The speed to resume at. See `play()` and `setRate(_:)`.
    private var desiredRate: Double = 1
    private var statusObservation: NSKeyValueObservation?

    public var onTick: ((Double) -> Void)?
    public var onEnded: (() -> Void)?
    /// See `setLooping`. Read by the end-of-item observer.
    private var isLooping = false
    public var onError: ((Error) -> Void)?

    public override nonisolated init() {
        super.init()
        player.actionAtItemEnd = .pause
        // Playback should not stall waiting for a buffer target on a LAN.
        player.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - State

    public var duration: Double {
        get async {
            guard let item else { return 0 }
            let value = item.duration
            guard value.isNumeric else { return 0 }
            return CMTimeGetSeconds(value)
        }
    }

    public var position: Double {
        get async { CMTimeGetSeconds(player.currentTime()) }
    }

    public var isPlaying: Bool {
        get async { player.timeControlStatus == .playing }
    }

    public var audioTracks: [MediaTrack] {
        get async { await tracks(for: .audible) }
    }

    public var subtitleTracks: [MediaTrack] {
        get async { await tracks(for: .legible) }
    }

    private func tracks(for characteristic: AVMediaCharacteristic) async -> [MediaTrack] {
        guard let item,
              let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else {
            return []
        }
        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: index,
                title: option.displayName,
                language: option.locale?.identifier,
                codec: nil,
                channels: nil,
                isDefault: index == 0,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            )
        }
    }

    // MARK: - Loading

    public func load(_ request: PlaybackRequest) async throws {
        stopObserving()

        // Jellyfin needs the auth header, and a token in the query string would
        // leak into server logs. AVURLAsset accepts header fields through this
        // options key — long-standing and used by every media client on the
        // platform, though not in the public headers.
        let options: [String: Any] = request.httpHeaders.isEmpty
            ? [:]
            : ["AVURLAssetHTTPHeaderFieldsKey": request.httpHeaders]

        let asset = AVURLAsset(url: request.url, options: options)
        let item = AVPlayerItem(asset: asset)
        self.item = item
        player.replaceCurrentItem(with: item)

        observe(item)

        if request.startAt > 1 {
            await seek(to: request.startAt)
        }
    }

    private func observe(_ item: AVPlayerItem) {
        // 4 Hz: enough for a smooth scrubber, and the progress reporter throttles
        // this down to one server call every ten seconds.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            // The observer is registered on .main, so this is already the main
            // actor — assumeIsolated states that rather than hopping and
            // delivering ticks a frame late.
            MainActor.assumeIsolated {
                self?.onTick?(CMTimeGetSeconds(time))
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isLooping else {
                    self.onEnded?()
                    return
                }
                // Seeked here rather than by leaving `actionAtItemEnd = .none`
                // alone: AVPlayer's own `.none` leaves the item parked at its
                // end with the rate still nominally running, which reads as a
                // frozen last frame. An explicit seek to zero followed by a
                // play is the only combination that actually repeats.
                //
                // `onEnded` deliberately does not fire while looping — a repeat
                // is not a finished file, and firing it would queue the next
                // episode under a film someone asked to loop.
                self.player.seek(to: .zero) { [weak self] _ in
                    MainActor.assumeIsolated { self?.player.play() }
                }
            }
        }

        // KVO fires on whichever thread changed the property, so this one does
        // have to hop.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error ?? PlayerEngineError.unknownFailure
            Task { @MainActor in self?.onError?(error) }
        }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
    }

    // MARK: - Transport

    public func play() async {
        // Not `play()`, which resets rate to 1. Choosing 1.5×, pausing and resuming
        // used to come back at normal speed while the settings panel still showed a
        // checkmark against 1.5×.
        player.rate = Float(desiredRate)
    }

    public func pause() async { player.pause() }

    public func seek(to seconds: Double) async {
        await seek(to: seconds, precise: true)
    }

    /// AVPlayer has no filter chain to put these in. The switches say so.
    public nonisolated var supportsAudioFilters: Bool { false }
    public func setAudioFilters(enhanceDialogue: Bool, reduceLoud: Bool) async {}

    public func step(by seconds: Double, from: Double) async {
        let time = CMTime(seconds: max(0, from + seconds), preferredTimescale: 600)
        // One-sided: any keyframe on the far side of the target, none behind it.
        let open = CMTime.positiveInfinity
        await player.seek(to: time,
                          toleranceBefore: seconds >= 0 ? .zero : open,
                          toleranceAfter: seconds >= 0 ? open : .zero)
    }

    public func seek(to seconds: Double, precise: Bool) async {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard precise else {
            // Nearest keyframe within half a second. Landing slightly early is
            // invisible while the cursor is still moving, and it is the difference
            // between the picture tracking the drag and lurching along behind it.
            let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
            await player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
            return
        }
        // Exact rather than nearest keyframe: releasing on a chapter mark and
        // landing eight seconds early is the kind of imprecision people notice.
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// AVPlayer has no loop of its own, so this is two settings at once: stop it
    /// pausing at the end, and repeat from the observer above.
    /// AVPlayer steps through the item, not the player.
    ///
    /// `canStepBackward` is checked rather than assumed: it is false for a live
    /// stream and for some remote assets, and calling anyway simply does
    /// nothing, which would read as a dead key rather than an unsupported one.
    /// Pausing first because a step during playback is immediately overwritten
    /// by the next frame arriving.
    public func step(frames: Int) async {
        guard frames != 0, let item = player.currentItem else { return }
        if frames < 0 && !item.canStepBackward { return }
        if frames > 0 && !item.canStepForward { return }
        player.pause()
        item.step(byCount: frames)
    }

    public func setLooping(_ looping: Bool) async {
        isLooping = looping
        player.actionAtItemEnd = looping ? .none : .pause
    }

    public func setRate(_ rate: Double) async {
        desiredRate = rate
        // Only while actually playing. Writing `rate` directly also *starts* a
        // paused player, so picking a speed from the settings panel resumed
        // playback while the transport still showed a Play button.
        guard player.rate > 0 else { return }
        player.rate = Float(rate)
    }

    public func selectAudioTrack(id: Int?) async {
        await select(id: id, characteristic: .audible)
    }

    public func selectSubtitleTrack(id: Int?) async {
        await select(id: id, characteristic: .legible)
    }

    private func select(id: Int?, characteristic: AVMediaCharacteristic) async {
        guard let item,
              let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else {
            return
        }
        guard let id, id >= 0, id < group.options.count else {
            item.select(nil, in: group)
            return
        }
        item.select(group.options[id], in: group)
    }

    public func stop() async {
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
        item = nil
    }
}

public enum PlayerEngineError: LocalizedError {
    case unknownFailure
    case engineUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unknownFailure:
            return "Playback failed for an unknown reason."
        case .engineUnavailable(let detail):
            return "The player couldn't start. \(detail)"
        }
    }
}

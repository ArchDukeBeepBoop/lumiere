import Foundation
@preconcurrency import AVFoundation
import LumiereKit

/// What AVFoundation can and cannot do, stated rather than faked.
///
/// AVPlayer has no scaler selection, no aspect override beyond gravity, no pan,
/// and no over-unity gain. Rather than silently ignore those calls, the engine
/// reports `supportsVideoAdjustments == false` and the UI disables the controls —
/// a disabled control tells the truth; one that does nothing does not.
extension AVPlayerEngine {

    public nonisolated var supportsVideoAdjustments: Bool { false }
    /// AVFoundation renders captions on its own clock with no offset to set. The
    /// panel says so rather than offering a control that quietly does nothing.
    public nonisolated var supportsSubtitleDelay: Bool { false }

    public func setSubtitleDelay(_ seconds: Double) async {}
    /// No audio offset and no frame grab here; the menu greys both out.
    public func setAudioDelay(_ seconds: Double) async {}
    public func saveScreenshot(to url: URL) async -> Bool { false }
    public func setABLoop(a: Double?, b: Double?) async {}
    public func setAudioDevice(uid: String?) async {}
    /// AVFoundation sizes captions from the system's own accessibility settings,
    /// which the app must not override.
    public func setSubtitleSize(_ size: SubtitleSize) async {}
    /// Also nothing: AVFoundation renders subtitles with its own styling and
    /// exposes no equivalent knobs. The presets are an mpv feature, and the panel
    /// says so rather than offering a control that quietly does nothing.
    public func setSubtitleStyle(_ style: SubtitleStyle) async {}

    // MARK: - Volume

    public var volume: Double {
        get async { Double(player.volume) }
    }

    public var isMuted: Bool {
        get async { player.isMuted }
    }

    public func setVolume(_ volume: Double) async {
        player.volume = Float(max(0, min(1, volume)))
    }

    public func setMuted(_ muted: Bool) async {
        player.isMuted = muted
    }

    /// AVPlayer clamps gain at unity, so boost is not available on this path.
    /// Deliberately a no-op rather than a scaled-down approximation, which would
    /// make the control appear to work while doing nothing above 100%.
    public func setVolumeBoost(_ percent: Double) async {}

    // MARK: - Video geometry

    public func setAspectOverride(_ aspect: AspectOverride) async {}
    public func setVerticalShift(_ fraction: Double) async {}
    /// AVFoundation takes its subtitles from the asset's own tracks; a file
    /// added after the asset was built is not something it can be told about.
    @discardableResult
    public func addSubtitle(url: URL, title: String, language: String) async -> Bool { false }
    public func setFlip(horizontal: Bool, vertical: Bool) async {}
    public func setUpscaling(_ mode: UpscalingMode) async {}

    // MARK: - Statistics

    public var statistics: PlaybackStatistics {
        get async {
            var stats = PlaybackStatistics(engineName: "AVPlayer")

            guard let event = player.currentItem?.accessLog()?.events.last else {
                return stats
            }
            if event.indicatedBitrate > 0 {
                stats.videoBitrate = Int(event.indicatedBitrate)
            }
            if event.numberOfDroppedVideoFrames >= 0 {
                stats.droppedFrames = event.numberOfDroppedVideoFrames
            }

            if let track = player.currentItem?.tracks.first(where: {
                $0.assetTrack?.mediaType == .video
            }), let assetTrack = track.assetTrack {
                // `load(_:)` rather than the synchronous properties, deprecated since
                // macOS 13: reading those can block on a track that has not finished
                // loading, and this getter is already async so there is nothing to
                // work around.
                if let (size, frameRate) = try? await assetTrack.load(
                    .naturalSize, .nominalFrameRate
                ) {
                    if size.width > 0 {
                        stats.resolution = "\(Int(size.width)) × \(Int(size.height))"
                    }
                    stats.containerFPS = Double(frameRate)
                }
                stats.estimatedFPS = Double(track.currentVideoFrameRate)
            }

            // AVFoundation does not say which decoder it chose. It uses
            // VideoToolbox whenever it can, but "whenever it can" is not a fact
            // the API will confirm, so this stays nil rather than claiming it.
            return stats
        }
    }
}

import Foundation
import CMPV
import LumiereKit

/// The capabilities only mpv has: video geometry, scaler selection, volume
/// beyond unity, and honest playback statistics.
extension MPVEngine {

    public nonisolated var supportsVideoAdjustments: Bool { true }
    public nonisolated var supportsSubtitleDelay: Bool { true }

    // MARK: - Volume

    public var volume: Double {
        get async { cachedVolume }
    }

    public var isMuted: Bool {
        get async { cachedMuted }
    }

    public func setVolume(_ volume: Double) async {
        let clamped = max(0, min(1, volume))
        cachedVolume = clamped
        // Scaled by the *current ceiling*, not by a hard 100.
        //
        // The two setters used to disagree: boost wrote `cachedVolume * boost`
        // (200 at full slider) while this wrote `clamped * 100`. With a 200% boost
        // applied at startup, nudging the slider from 1.0 to 0.95 went from 200 to
        // 95 — a step of 5% on the control, and half the loudness.
        setProperty("volume", String(Int(clamped * cachedBoost)))
    }

    public func setMuted(_ muted: Bool) async {
        cachedMuted = muted
        setProperty("mute", muted ? "yes" : "no")
    }

    public func setVolumeBoost(_ percent: Double) async {
        let clamped = max(100, min(200, percent))
        cachedBoost = clamped
        setProperty("volume-max", String(Int(clamped)))
        // Re-apply the slider so the new ceiling takes effect immediately rather
        // than at the next volume change.
        setProperty("volume", String(Int(cachedVolume * clamped)))
    }

    public nonisolated var supportsAudioFilters: Bool { true }

    /// Labelled filters, so each switch adds or removes only its own.
    /// Dialogue: the rumble below 100 Hz trimmed and the speech band lifted.
    /// Loud sounds: a gentle compressor with make-up gain, so quiet lines rise
    /// and explosions do not jump.
    public func setAudioFilters(enhanceDialogue: Bool, reduceLoud: Bool) async {
        commandAsync(["af", "remove", "@dialogue"])
        commandAsync(["af", "remove", "@quieter"])
        if enhanceDialogue {
            commandAsync(["af", "add",
                          "@dialogue:lavfi=[highpass=f=100,equalizer=f=2200:t=q:w=1.2:g=5]"])
        }
        if reduceLoud {
            commandAsync(["af", "add",
                          "@quieter:lavfi=[acompressor=threshold=0.1:ratio=4:attack=20:release=250:makeup=3]"])
        }
    }

    // MARK: - Video geometry

    public func setAspectOverride(_ aspect: AspectOverride) async {
        // "-1" is mpv's "use the file's own aspect".
        setProperty("video-aspect-override", aspect.ratio.map { String($0) } ?? "-1")
    }

    /// mpv's own sub-add, which takes a path or a URL and selects it in the
    /// same command — so a subtitle fetched mid-film appears on the picture
    /// without reloading the file and losing the place.
    @discardableResult
    public func addSubtitle(url: URL, title: String, language: String) async -> Bool {
        guard handle != nil else { return false }
        let target = url.isFileURL ? url.path : url.absoluteString
        command(["sub-add", target, "select", title, language])
        reloadTracks()
        return true
    }

    public func setVerticalShift(_ fraction: Double) async {
        setProperty("video-pan-y", String(max(-1, min(1, fraction))))
    }

    /// mpv's own filters, set as the whole chain: nothing else here puts a
    /// filter on it, so replacing the chain is replacing the flip.
    public func setFlip(horizontal: Bool, vertical: Bool) async {
        var filters: [String] = []
        if horizontal { filters.append("hflip") }
        if vertical { filters.append("vflip") }
        setProperty("vf", filters.joined(separator: ","))
    }

    public func setUpscaling(_ mode: UpscalingMode) async {
        guard let scaler = mode.mpvScaler else {
            // Auto: hand control back to mpv's own defaults.
            setProperty("scale", "spline36")
            setProperty("cscale", "spline36")
            return
        }
        setProperty("scale", scaler)
        setProperty("cscale", scaler)
    }

    /// Shifts subtitle timing against the audio.
    ///
    /// Clamped to ten seconds either way. A real mismatch — a subtitle file cut for
    /// a different release, or a track that drifts a few frames behind the speech —
    /// is fractions of a second to a couple of seconds; anything past ten is a
    /// slip of the keyboard, and letting it through means subtitles that never
    /// appear again with nothing on screen explaining why.
    public func setSubtitleDelay(_ seconds: Double) async {
        setProperty("sub-delay", String(format: "%.3f", max(-10, min(10, seconds))))
    }

    /// Resizes subtitles mid-playback.
    ///
    /// Normal has to undo the others rather than simply setting nothing: the
    /// options are properties on a running engine, so going back from Large would
    /// otherwise leave the scale where it was. `sub-ass-override=no` is the value
    /// `SubtitleStyle` set at startup, which is what puts a typeset script back
    /// under its own control.
    public func setSubtitleSize(_ size: SubtitleSize) async {
        guard size != .normal else {
            setProperty("sub-scale", "1.0")
            setProperty("sub-ass-override", "no")
            return
        }
        for (key, value) in size.mpvOptions { setProperty(key, value) }
    }

    /// Restyles subtitles mid-playback.
    ///
    /// Every option the preset names is set, so switching between two presets can
    /// never leave one of them half-applied — the previous style's outline
    /// surviving under the new style's font is the failure this shape avoids.
    ///
    /// A size other than Normal re-applies afterwards, because the style sets
    /// `sub-ass-override=no` and the size needs `scale`; the later write wins, which
    /// is the same ordering `MPVEngine` uses at startup.
    public func setSubtitleStyle(_ style: SubtitleStyle) async {
        for (key, value) in style.mpvOptions { setProperty(key, value) }
        let size = SubtitleSize.size(id: UserDefaults.standard.string(forKey: "subtitleSize"))
        for (key, value) in size.mpvOptions { setProperty(key, value) }
    }

    /// Dims everything outside the picture, so a bright room does not fight the
    /// film. mpv has no such feature; this is drawn by the app, and the engine
    /// only needs to know it is on so the HUD can say so.
    public func setAmbientMode(_ enabled: Bool) async {
        cachedAmbientMode = enabled
    }

    // MARK: - Statistics

    public var statistics: PlaybackStatistics {
        get async {
            var stats = PlaybackStatistics(engineName: "mpv")

            stats.videoCodec = stringProperty("video-codec")
                ?? stringProperty("video-format").map { MediaSummary.normalise(codec: $0) }
            stats.audioCodec = stringProperty("audio-codec-name")
                .map { MediaSummary.normalise(codec: $0) }

            if let width = intProperty("width"), let height = intProperty("height") {
                stats.resolution = "\(width) × \(height)"
            }
            stats.containerFPS = doubleProperty("container-fps")
            stats.estimatedFPS = doubleProperty("estimated-vf-fps")
            stats.droppedFrames = intProperty("frame-drop-count").map(Int.init)
            stats.videoBitrate = intProperty("video-bitrate").map(Int.init)
            stats.audioBitrate = intProperty("audio-bitrate").map(Int.init)
            stats.cacheSeconds = doubleProperty("demuxer-cache-duration")

            // "no" is mpv's answer when it fell back to software, and reporting
            // that as a hardware decoder would hide the very problem the HUD
            // exists to reveal.
            let decoder = stringProperty("hwdec-current")
            stats.hardwareDecoder = (decoder == "no" || decoder?.isEmpty == true) ? nil : decoder

            return stats
        }
    }
}

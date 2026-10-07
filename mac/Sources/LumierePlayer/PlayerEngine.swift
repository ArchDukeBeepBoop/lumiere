import Foundation
import LumiereKit

/// The one interface the player UI talks to.
///
/// Two implementations back it: `AVPlayerEngine` for what AVFoundation accepts
/// natively, and `MPVEngine` for everything else — which on a real library is
/// most of it. The UI never branches on which engine is active; only
/// `PlaybackDecision` chooses, and it chooses once, before load.
/// Main-actor isolated: both engines wrap frameworks with main-thread contracts
/// (AVFoundation, and mpv's render API), and the player UI that drives them is
/// main-actor anyway. Isolating here means neither engine needs an unsafe opt-out.
@MainActor
public protocol PlayerEngine: AnyObject, Sendable {

    /// Seconds. Zero until the media is loaded.
    var duration: Double { get async }
    var position: Double { get async }
    var isPlaying: Bool { get async }

    var audioTracks: [MediaTrack] { get async }
    var subtitleTracks: [MediaTrack] { get async }

    /// 0…1. Independent of `volumeBoost`, which can push past unity.
    var volume: Double { get async }
    var isMuted: Bool { get async }

    /// What the engine can honestly report. Fields the engine cannot observe stay
    /// nil rather than being guessed at.
    var statistics: PlaybackStatistics { get async }

    /// True where the engine can actually apply video adjustments. AVPlayer
    /// cannot, and the UI disables rather than silently ignores.
    nonisolated var supportsVideoAdjustments: Bool { get }

    /// True where the engine can shift subtitle timing. mpv can; AVPlayer renders
    /// its own captions on its own clock and offers no hook, so the UI disables the
    /// control there rather than showing one that does nothing.
    nonisolated var supportsSubtitleDelay: Bool { get }

    func load(_ request: PlaybackRequest) async throws
    func play() async
    func pause() async
    func seek(to seconds: Double) async
    /// Seeks, optionally trading accuracy for speed.
    ///
    /// An exact seek decodes forward from the preceding keyframe, which on a
    /// long-GOP 4K file is tens of milliseconds — fine once, far too slow to drag
    /// against. Dragging the scrubber asks for imprecise seeks and releases with a
    /// precise one, which is what lets the picture follow the cursor at all.
    func seek(to seconds: Double, precise: Bool) async
    /// A keyboard step: `by` seconds from `from`, landing on a keyframe in the
    /// direction of travel — at or after the target going forward, at or before
    /// it going back. An absolute keyframe seek lands on the keyframe *before*
    /// its target whichever way it went, so on a file with keyframes ten
    /// seconds apart → could land where it started, or behind it.
    func step(by seconds: Double, from: Double) async
    /// Apple TV's two audio switches: lift speech, and even out the loud
    /// moments. Whether this engine can do them at all — see `audioFilters`.
    func setAudioFilters(enhanceDialogue: Bool, reduceLoud: Bool) async
    var supportsAudioFilters: Bool { get }
    func setRate(_ rate: Double) async
    func selectAudioTrack(id: Int?) async
    func selectSubtitleTrack(id: Int?) async
    func setVolume(_ volume: Double) async
    func setMuted(_ muted: Bool) async
    /// 100…200 percent. Amplifies past unity for quiet sources, at the cost of
    /// clipping — which is why it is separate from the volume slider.
    func setVolumeBoost(_ percent: Double) async
    func setAspectOverride(_ aspect: AspectOverride) async
    /// -1…1 as a fraction of frame height. Nudges the picture inside the frame,
    /// for sources with off-centre bars.
    func setVerticalShift(_ fraction: Double) async
    /// Mirrors the picture left-to-right, top-to-bottom, or both. For a file
    /// shot the wrong way round, or a screen behind a mirror.
    func setFlip(horizontal: Bool, vertical: Bool) async
    func setUpscaling(_ mode: UpscalingMode) async
    /// Seconds. Positive shows subtitles later, negative earlier — mpv's own sign
    /// convention, and the one every other player uses, so a number copied from
    /// elsewhere means the same thing here.
    func setSubtitleDelay(_ seconds: Double) async
    /// Seconds, same sign as subtitles: positive plays the sound later. For a
    /// file whose audio drifts against the picture. mpv only.
    func setAudioDelay(_ seconds: Double) async
    /// Writes the frame on screen, subtitles included, to `url` as PNG.
    /// False where the engine cannot. mpv only.
    func saveScreenshot(to url: URL) async -> Bool
    /// Repeats the stretch between `a` and `b`; nil for either clears it. mpv only.
    func setABLoop(a: Double?, b: Double?) async
    /// Plays through one output — an `AudioOutputs.Device` UID — or, nil,
    /// through whatever the system uses. mpv only.
    func setAudioDevice(uid: String?) async
    /// Loads a subtitle that is not in the file and selects it — a sidecar on
    /// disk, or one the server just fetched. Returns false where the engine
    /// cannot take one.
    @discardableResult
    func addSubtitle(url: URL, title: String, language: String) async -> Bool
    /// Applied while playing, so the effect of a choice is visible against the
    /// frame it will actually be read over.
    func setSubtitleSize(_ size: SubtitleSize) async
    /// The same, for the style. Read once at engine start until now, so choosing a
    /// preset did nothing until the next file — which reads exactly like a preset
    /// that does not work.
    func setSubtitleStyle(_ style: SubtitleStyle) async

    /// Repeats the file instead of ending it.
    ///
    /// Both engines can do this and they do it differently: mpv has `loop-file`,
    /// which never reports the end at all, while AVPlayer has to be told not to
    /// pause and then seeked back itself. The difference matters to the caller
    /// only in that neither fires `onEnded` while looping — which is what stops
    /// a looped film from advancing to the next episode.
    func setLooping(_ looping: Bool) async

    /// Advances or retreats exactly one frame, while paused.
    ///
    /// Not a small seek. A seek lands on a time and decodes to it, which on a
    /// long-GOP file is a different frame each time you ask for "one frame" —
    /// stepping is the operation that actually moves by one picture, and it is
    /// what makes a player usable for finding a moment rather than a region.
    ///
    /// Stepping backwards is the expensive direction on both engines: there is
    /// no such thing as decoding backwards, so it means seeking behind the
    /// current frame and decoding forward again.
    func step(frames: Int) async

    func stop() async

    /// Fires roughly 4×/second while playing. The progress reporter throttles
    /// this down to one Jellyfin call per 10 seconds.
    ///
    /// Main-actor closures, not `@Sendable` ones: the protocol is isolated, so
    /// every callback already arrives on the main actor and the UI can update
    /// from them directly.
    var onTick: ((Double) -> Void)? { get set }
    var onEnded: (() -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
}

/// A selectable audio or subtitle stream, normalised across both engines.
public struct MediaTrack: Sendable, Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let language: String?
    public let codec: String?
    public let channels: Int?
    public let isDefault: Bool
    public let isForced: Bool

    public init(
        id: Int,
        title: String,
        language: String? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        isDefault: Bool = false,
        isForced: Bool = false
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.channels = channels
        self.isDefault = isDefault
        self.isForced = isForced
    }
}

/// Everything an engine needs to start playing. Built by `StreamBuilder` from a
/// `PlaybackPlan`, so the engine itself makes no decisions.
public struct PlaybackRequest: Sendable, Equatable {
    public let url: URL
    /// Where to resume from, in seconds.
    public let startAt: Double
    public let preferredAudioTrack: Int?
    public let preferredSubtitleTrack: Int?
    /// Set when the source is Dolby Vision on a machine without DV output, so the
    /// mpv engine can enable HDR10 tone mapping.
    public let toneMapDolbyVision: Bool
    public let httpHeaders: [String: String]
    /// The files this one's ordered chapters borrow from — a release's
    /// opening and ending, shipped as their own segments. Only mpv can follow
    /// them; it is told where they are and stitches one timeline, as VLC does
    /// from a folder. Empty for almost every file.
    public let linkedFiles: [URL]

    public init(
        url: URL,
        startAt: Double = 0,
        preferredAudioTrack: Int? = nil,
        preferredSubtitleTrack: Int? = nil,
        toneMapDolbyVision: Bool = false,
        httpHeaders: [String: String] = [:],
        linkedFiles: [URL] = []
    ) {
        self.url = url
        self.startAt = startAt
        self.preferredAudioTrack = preferredAudioTrack
        self.preferredSubtitleTrack = preferredSubtitleTrack
        self.toneMapDolbyVision = toneMapDolbyVision
        self.linkedFiles = linkedFiles
        self.httpHeaders = httpHeaders
    }
}

/// Lets a remembered language be matched against this file's tracks. The matching
/// itself lives in LumiereKit beside the stored preference.
extension MediaTrack: SubtitleTrackDescribing {}

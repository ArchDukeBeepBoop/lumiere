import Foundation

/// How a file will be played, and why.
///
/// The `why` is not decoration: it drives the badge the user sees, and when
/// something goes wrong it is the difference between "the server is transcoding
/// and I don't know why" and a one-line answer.
public struct PlaybackDecision: Sendable, Equatable {

    public enum Route: String, Sendable {
        /// The original file, byte for byte. The goal for essentially everything.
        case directPlay
        /// Original streams, new container. The server copies, never re-encodes.
        case remux
        /// The server re-encodes. A last resort and, on a healthy setup, a bug.
        case transcode
    }

    public enum Engine: String, Sendable {
        case avPlayer
        case mpv
    }

    public enum Reason: String, Sendable {
        case nativelySupported
        case containerUnsupportedByAVFoundation
        case videoCodecUnsupportedByAVFoundation
        case audioCodecUnsupportedByAVFoundation
        case dolbyVisionNeedsToneMapping
        case subtitleNeedsRendering
        case bitrateOverLimit
        case resolutionOverDecoderLimit
        case noCompatibleEngine
        case userForcedTranscode

        /// One sentence, shown in the player's info panel.
        public var explanation: String {
            switch self {
            case .nativelySupported:
                return "Playing the original file directly."
            case .containerUnsupportedByAVFoundation:
                return "The container needs mpv; AVFoundation can't open it."
            case .videoCodecUnsupportedByAVFoundation:
                return "The video codec needs mpv."
            case .audioCodecUnsupportedByAVFoundation:
                return "The audio codec needs mpv."
            case .dolbyVisionNeedsToneMapping:
                return "Dolby Vision is being tone-mapped to HDR10 for this display."
            case .subtitleNeedsRendering:
                return "The selected subtitles need mpv to render."
            case .bitrateOverLimit:
                return "The file exceeds the bitrate limit you set."
            case .resolutionOverDecoderLimit:
                return "The resolution is beyond what this Mac can decode."
            case .noCompatibleEngine:
                return "Neither player can handle this file as-is."
            case .userForcedTranscode:
                return "Transcoding because you asked for it."
            }
        }
    }

    public let route: Route
    public let engine: Engine
    public let reason: Reason
    /// mpv should tone-map Dolby Vision to HDR10 rather than render it wrong.
    public let toneMapDolbyVision: Bool
    /// No hardware path for this codec — playable, but it will cost CPU and battery.
    public let softwareDecode: Bool

    public init(
        route: Route,
        engine: Engine,
        reason: Reason,
        toneMapDolbyVision: Bool = false,
        softwareDecode: Bool = false
    ) {
        self.route = route
        self.engine = engine
        self.reason = reason
        self.toneMapDolbyVision = toneMapDolbyVision
        self.softwareDecode = softwareDecode
    }

    /// What the badge row shows, and the thing to check against the Jellyfin
    /// dashboard: it must say the same word the server does.
    public var badgeText: String {
        switch route {
        case .directPlay: return "Direct play"
        case .remux: return "Direct stream"
        case .transcode: return "Transcoding"
        }
    }
}

/// Chooses how to play a file. Pure — no I/O, no singletons, no probing.
///
/// The whole point of Lumiere is that this almost always answers "direct play",
/// because mpv can take nearly everything a real library contains. AVPlayer is
/// preferred where it works because it is cheaper on battery and integrates with
/// the system; mpv covers the rest; the server is asked to work only when both
/// genuinely cannot.
public enum PlaybackPlanner {

    public struct Options: Sendable, Equatable {
        /// False only if libmpv failed to load, which turns a direct play into a
        /// server transcode — worth surfacing loudly if it ever happens.
        public var mpvAvailable: Bool
        /// The subtitle stream the user has chosen, if any.
        public var selectedSubtitleIndex: Int?
        /// Bits per second, from settings. Nil means unlimited, which is the
        /// right default on a LAN.
        public var maxBitrate: Int?
        public var forceTranscode: Bool

        public init(
            mpvAvailable: Bool = true,
            selectedSubtitleIndex: Int? = nil,
            maxBitrate: Int? = nil,
            forceTranscode: Bool = false
        ) {
            self.mpvAvailable = mpvAvailable
            self.selectedSubtitleIndex = selectedSubtitleIndex
            self.maxBitrate = maxBitrate
            self.forceTranscode = forceTranscode
        }
    }

    // MARK: - Compatibility tables

    /// Containers AVFoundation can demux. Notably absent: Matroska, which is most
    /// of a real library — hence mpv.
    static let avContainers: Set<String> = ["mp4", "m4v", "mov", "qt"]

    /// Audio codecs AVFoundation decodes inside those containers.
    ///
    /// DTS, TrueHD, FLAC, Opus and Vorbis are absent on purpose: macOS either
    /// cannot decode them at all or cannot in an MP4. Each is common in a ripped
    /// library, and each is a reason mpv exists here.
    static let avAudioCodecs: Set<String> = [
        "aac", "ac3", "eac3", "alac", "mp3", "pcm", "pcm_s16le", "pcm_s24le", "lpcm",
    ]

    /// Subtitle formats that must be drawn by a renderer rather than handed to
    /// the system. Bitmap formats and styled ASS both qualify.
    static let subtitlesNeedingRendering: Set<String> = [
        "pgssub", "pgs", "dvdsub", "vobsub", "dvbsub", "ass", "ssa",
    ]

    // MARK: - The decision

    public static func decide(
        source: MediaSource,
        capabilities: SystemCapabilities,
        options: Options = Options()
    ) -> PlaybackDecision {

        let video = source.videoStream
        let audio = source.defaultAudioStream
        let isDolbyVision = isDolbyVision(video)
        let needsToneMap = isDolbyVision && !capabilities.dolbyVision

        // Hardware decode is reported, never decisive: mpv plays 12-bit HEVC and
        // VC-1 in software perfectly well, just warmer.
        let software = video.map {
            !MediaSummary.decodesInHardware(codec: $0.codec, capabilities: capabilities)
        } ?? false

        func mpvOr(_ fallback: PlaybackDecision.Reason, _ reason: PlaybackDecision.Reason) -> PlaybackDecision {
            guard options.mpvAvailable else {
                return PlaybackDecision(
                    route: .transcode, engine: .avPlayer, reason: fallback,
                    toneMapDolbyVision: false, softwareDecode: software
                )
            }
            return PlaybackDecision(
                route: .directPlay, engine: .mpv, reason: reason,
                toneMapDolbyVision: needsToneMap, softwareDecode: software
            )
        }

        // 1. Explicit user request wins over everything.
        if options.forceTranscode {
            return PlaybackDecision(
                route: .transcode, engine: .avPlayer, reason: .userForcedTranscode
            )
        }

        // 2. A bitrate cap means the server must re-encode; no player can shrink
        //    a file on the client side.
        if let limit = options.maxBitrate, let bitrate = source.bitrate, bitrate > limit {
            return PlaybackDecision(
                route: .transcode, engine: .avPlayer, reason: .bitrateOverLimit
            )
        }

        // 3. Beyond what any decoder here can manage.
        //
        // mpv *can* decode 8K in software, but a 2018 Intel i7 will not sustain
        // 24fps doing it, and a stuttering direct play is worse than a clean
        // server transcode. The limit is the hardware limit, not double it.
        if let width = video?.width, width > capabilities.maxDecodeWidth {
            return PlaybackDecision(
                route: .transcode, engine: .avPlayer, reason: .resolutionOverDecoderLimit
            )
        }

        // 4. Dolby Vision that this Mac cannot present. AVPlayer would either
        //    refuse it or render it with the wrong colours, so mpv tone-maps.
        if needsToneMap {
            return mpvOr(.noCompatibleEngine, .dolbyVisionNeedsToneMapping)
        }

        // 5. The chosen subtitle needs a renderer.
        if let index = options.selectedSubtitleIndex,
           let subtitle = source.subtitleStreams.first(where: { $0.index == index }),
           needsRendering(subtitle) {
            return mpvOr(.noCompatibleEngine, .subtitleNeedsRendering)
        }

        // 6. Container.
        let container = (source.container ?? "").lowercased()
        if !avContainers.contains(container) {
            return mpvOr(.containerUnsupportedByAVFoundation, .containerUnsupportedByAVFoundation)
        }

        // 7. Video codec.
        if let video, !avSupportsVideo(video, capabilities: capabilities) {
            return mpvOr(.videoCodecUnsupportedByAVFoundation, .videoCodecUnsupportedByAVFoundation)
        }

        // 8. Audio codec.
        if let audio, !avAudioCodecs.contains((audio.codec ?? "").lowercased()) {
            return mpvOr(.audioCodecUnsupportedByAVFoundation, .audioCodecUnsupportedByAVFoundation)
        }

        // 9. Everything AVFoundation can take, it takes.
        return PlaybackDecision(
            route: .directPlay, engine: .avPlayer, reason: .nativelySupported,
            toneMapDolbyVision: false, softwareDecode: software
        )
    }

    // MARK: - Helpers

    static func isDolbyVision(_ video: MediaStream?) -> Bool {
        guard let video else { return false }
        if video.dvProfile != nil { return true }
        let range = (video.videoRangeType ?? video.videoRange ?? "").uppercased()
        return range.contains("DOVI") || range.contains("DOLBY")
    }

    static func needsRendering(_ subtitle: MediaStream) -> Bool {
        subtitlesNeedingRendering.contains((subtitle.codec ?? "").lowercased())
    }

    /// Whether AVFoundation can decode this video stream on this machine.
    static func avSupportsVideo(_ video: MediaStream, capabilities: SystemCapabilities) -> Bool {
        switch (video.codec ?? "").lowercased() {
        case "h264", "avc":
            return true
        case "hevc", "h265":
            // HEVC always goes to mpv, whatever this machine can decode.
            //
            // Not a decoder limitation — a container one, and an invisible one.
            // AVFoundation accepts HEVC in MP4 only when the sample entry is
            // `hvc1`, which carries its parameter sets in the sample description.
            // The other legal spelling, `hev1`, carries them in-band, and
            // AVFoundation refuses it outright: measured on a real file from this
            // library, `Veep - 1x08 - Tears.mp4` reports `isPlayable = false`,
            // `isDecodable = false`, and image generation fails, while its AAC
            // track decodes perfectly. That is precisely the reported symptom —
            // sound, controls and a clock, and no picture.
            //
            // The reason this cannot be decided per file is that nothing tells us
            // which spelling it is. Jellyfin sends no `CodecTag` on a MediaStream
            // — null on all 574 cached streams here, MP4 and MKV alike — and no
            // profile string either, so the tag is knowable only by reading the
            // file's own boxes, which a client streaming over HTTP cannot do
            // before it has to choose an engine.
            //
            // So the choice is between an engine that plays every HEVC file and
            // one that plays some of them and shows a black window for the rest
            // with nothing said. mpv decodes HEVC through the same VideoToolbox
            // hardware, so the cost is not performance: it is Picture in Picture,
            // which is AVPlayer's alone. A missing PiP button is a feature you can
            // see is absent. A missing picture is a bug you cannot explain.
            return false
        case "av1":
            // Software AV1 through AVFoundation is not a real option at 4K.
            return capabilities.hardwareAV1
        case "vp9":
            // VP9 in MP4 is not something AVFoundation demuxes reliably.
            return false
        default:
            return false
        }
    }
}

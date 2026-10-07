import Foundation

/// How the picture is fitted to the window.
///
/// Infuse offers this because rips lie: a 2.40:1 film stored in a 16:9 container
/// with baked-in bars, or an anamorphic source whose flags are wrong, both look
/// correct only when overridden by hand.
public enum AspectOverride: String, CaseIterable, Identifiable, Sendable {
    case auto
    case sdtv4x3
    case hdtv16x10
    case hdtv16x9
    case widescreen185
    case widescreen200
    case anamorphic235
    case anamorphic239
    case anamorphic240
    case ultraWide36x10

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .sdtv4x3: return "SDTV (4:3)"
        case .hdtv16x10: return "HDTV (16:10)"
        case .hdtv16x9: return "HDTV (16:9)"
        case .widescreen185: return "Widescreen A (1.85:1)"
        case .widescreen200: return "Widescreen B (2.00:1)"
        case .anamorphic235: return "Anamorphic A (2.35:1)"
        case .anamorphic239: return "Anamorphic B (2.39:1)"
        case .anamorphic240: return "Anamorphic C (2.40:1)"
        case .ultraWide36x10: return "Ultra-Widescreen (36:10)"
        }
    }

    /// The ratio to force, or nil to let the file decide.
    public var ratio: Double? {
        switch self {
        case .auto: return nil
        case .sdtv4x3: return 4.0 / 3.0
        case .hdtv16x10: return 16.0 / 10.0
        case .hdtv16x9: return 16.0 / 9.0
        case .widescreen185: return 1.85
        case .widescreen200: return 2.00
        case .anamorphic235: return 2.35
        case .anamorphic239: return 2.39
        case .anamorphic240: return 2.40
        case .ultraWide36x10: return 3.6
        }
    }
}

/// Scaler quality. Only mpv can honour these; AVPlayer has no equivalent.
public enum UpscalingMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case standard
    case high
    case highest

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .standard: return "Standard"
        case .high: return "High"
        case .highest: return "Highest"
        }
    }

    public var explanation: String {
        switch self {
        case .auto: return "Picks a scaler to suit the source and this Mac."
        case .standard: return "Bilinear. Cheapest, and fine when the source matches your display."
        case .high: return "Lanczos. Sharper on upscaled content, a little more GPU."
        case .highest: return "Ewa Lanczos. Sharpest, and the most expensive by some margin."
        }
    }

    /// mpv's `scale` and `cscale` values.
    var mpvScaler: String? {
        switch self {
        case .auto: return nil
        case .standard: return "bilinear"
        case .high: return "lanczos"
        case .highest: return "ewa_lanczossharp"
        }
    }
}

/// What the playback HUD reports.
///
/// Every field is optional because AVPlayer exposes almost none of it. Showing
/// "—" is honest; inventing a number is not.
public struct PlaybackStatistics: Sendable, Equatable {
    public var videoCodec: String?
    public var audioCodec: String?
    public var resolution: String?
    public var containerFPS: Double?
    public var estimatedFPS: Double?
    public var droppedFrames: Int?
    public var videoBitrate: Int?
    public var audioBitrate: Int?
    /// "videotoolbox", "videotoolbox-copy", or nil when decoding in software.
    public var hardwareDecoder: String?
    public var cacheSeconds: Double?
    public var engineName: String

    public init(engineName: String) {
        self.engineName = engineName
    }

    public var decodePath: String {
        hardwareDecoder.map { "Hardware (\($0))" } ?? "Software"
    }
}

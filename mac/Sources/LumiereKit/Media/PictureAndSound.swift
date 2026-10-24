import Foundation

/// The picture controls VLC keeps under Tools › Effects and Filters, brought
/// to where you are watching: brightness, contrast, saturation and gamma, a
/// quarter-turn rotation, zoom, and deinterlacing.
///
/// A value, so it can be compared with `.neutral`, saved with a show's preset
/// and applied in one call. mpv only; the AVPlayer engine has no equivalent.
public struct PictureAdjustments: Equatable, Codable, Sendable {
    /// -100…100, zero untouched — mpv's own scale for each.
    public var brightness: Int = 0
    public var contrast: Int = 0
    public var saturation: Int = 0
    public var gamma: Int = 0
    /// 0, 90, 180 or 270, clockwise.
    public var rotation: Int = 0
    /// 1 is the fitted picture; 1.25 is a quarter larger, cropping the edges.
    public var zoom: Double = 1
    public var deinterlace: Bool = false

    public init() {}

    public static let neutral = PictureAdjustments()

    public var isNeutral: Bool { self == .neutral }

    /// Turns the picture a quarter clockwise.
    public mutating func rotateClockwise() { rotation = (rotation + 90) % 360 }

    /// mpv's `video-zoom` is a power of two: 0 is fitted, 1 is double.
    public var mpvZoom: Double { log2(max(0.25, min(4, zoom))) }

    public static func clamp(_ value: Int) -> Int { max(-100, min(100, value)) }
}

/// Sound presets, in the spirit of VLC's equalizer but named for the room
/// rather than in hertz. Each is one mpv audio filter; Flat removes it.
public enum SoundPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case flat, bassBoost, trebleBoost, voice, smallSpeakers, headphones

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "More Bass"
        case .trebleBoost: return "More Treble"
        case .voice: return "Voices Forward"
        case .smallSpeakers: return "Laptop Speakers"
        case .headphones: return "Headphones"
        }
    }

    public var explanation: String {
        switch self {
        case .flat: return "The soundtrack as mixed."
        case .bassBoost: return "Warmer low end, for music and action."
        case .trebleBoost: return "Crisper detail, for a dull or muffled mix."
        case .voice: return "Lifts the speech band without changing the volume."
        case .smallSpeakers: return "Trims rumble the speakers can't play, so the rest is clearer."
        case .headphones: return "Folds a surround mix to stereo the way a room would."
        }
    }

    public var icon: String {
        switch self {
        case .flat: return "equal"
        case .bassBoost: return "speaker.wave.3"
        case .trebleBoost: return "waveform.path"
        case .voice: return "person.wave.2"
        case .smallSpeakers: return "laptopcomputer"
        case .headphones: return "headphones"
        }
    }

    /// The lavfi chain, or nil for no filter.
    public var lavfi: String? {
        switch self {
        case .flat: return nil
        case .bassBoost: return "bass=g=6:f=110"
        case .trebleBoost: return "treble=g=5:f=6000"
        case .voice: return "equalizer=f=1800:t=q:w=0.9:g=4,equalizer=f=120:t=q:w=1:g=-3"
        case .smallSpeakers: return "highpass=f=150,equalizer=f=3000:t=q:w=1:g=3"
        case .headphones: return "earwax"
        }
    }
}

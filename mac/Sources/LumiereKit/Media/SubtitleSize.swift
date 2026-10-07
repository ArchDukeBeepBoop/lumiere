import Foundation

/// How big subtitles are drawn, independent of which preset draws them.
///
/// Separate from `SubtitleStyle` because the two answer different questions. A
/// style is a look — a face, an outline, where the text sits — and picking one is
/// a matter of taste. Size is not taste: it depends on how far away the screen is
/// and how well you see, and it has to be adjustable without giving up the look
/// you chose. Folding it into the presets would have meant twelve presets.
public enum SubtitleSize: String, CaseIterable, Identifiable, Sendable {
    case small, normal, large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }

    /// A multiplier, not a point size. Every preset states its size as a
    /// percentage of video height so a subtitle is the same relative size on a
    /// 720p file and a 4K one; scaling that keeps the property, where a fixed
    /// size would throw it away.
    public var scale: Double {
        switch self {
        case .small: return 0.8
        case .normal: return 1.0
        case .large: return 1.3
        }
    }

    public static func size(id: String?) -> SubtitleSize {
        SubtitleSize(rawValue: id ?? "") ?? .normal
    }

    /// The mpv options this size sets.
    ///
    /// `sub-ass-override` is the subtle one. `sub-scale` does not touch an ASS or
    /// SSA track by default — mpv leaves a typeset script alone, which is the
    /// behaviour `SubtitleStyle` deliberately relies on — so on an anime library,
    /// where most tracks are ASS, a size control would appear to do nothing at
    /// all. `scale` is mpv's own answer to exactly this: it applies the scale and
    /// *only* the scale to ASS, leaving positioning, colour and font as the
    /// typesetter wrote them. At normal size nothing is overridden, so a script
    /// is untouched unless the size is actually being changed.
    public var mpvOptions: [(String, String)] {
        guard self != .normal else { return [] }
        return [
            ("sub-scale", String(format: "%.2f", scale)),
            ("sub-ass-override", "scale")
        ]
    }
}

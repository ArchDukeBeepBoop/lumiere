import Foundation

/// Whether a seek should land on the exact frame or the nearest keyframe.
///
/// An exact seek decodes forward from the keyframe before the target, and
/// how long that takes is set by the file: a 1080p episode is a few frames
/// of work, a 4K film decoded in software is a second or more of it — which
/// arrives as the picture landing once, then jumping a second time after a
/// wait. mpv's own default draws the same line by *kind* of seek: a relative
/// jump lands on a keyframe, an absolute one lands exactly. This draws it by
/// weight of file instead, and lets the choice be made outright.
public enum SeekLanding: String, CaseIterable, Sendable, Identifiable {
    /// Exactly where the scrubber was released, whatever it costs.
    case exact
    /// Exactly, unless the file is heavy enough that the wait would show.
    case auto
    /// The nearest keyframe, always. The cheapest, and a few seconds off.
    case keyframe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .exact: "Exactly"
        case .auto: "Exactly, unless the file is heavy"
        case .keyframe: "Nearest keyframe"
        }
    }

    /// The width from which `auto` stops decoding forward. Above 1440p: a 4K
    /// frame is four times the work of a 1080p one, and this player decodes
    /// every frame in software.
    public static let heavyWidth = 2560

    /// Whether a released scrubber should ask for an exact seek.
    public func landsExactly(width: Int?) -> Bool {
        switch self {
        case .exact: true
        case .keyframe: false
        case .auto: (width ?? 0) < Self.heavyWidth
        }
    }
}

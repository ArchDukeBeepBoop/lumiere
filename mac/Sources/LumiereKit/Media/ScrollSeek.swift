import Foundation

/// Turns a stream of scroll-wheel deltas into seek steps.
///
/// A trackpad reports dozens of tiny precise deltas per swipe; a wheel reports
/// one coarse notch. Both should feel like the same gesture — a swipe of the
/// fingers moves the picture a few seconds, a notch of the wheel moves it a
/// whole step, and neither issues a seek per event, which is what turns a
/// swipe into a queue the decoder never catches up with. So the deltas are
/// summed and handed out in whole seconds.
///
/// The direction follows mpv: fingers moving right is forward.
public struct ScrollSeek: Sendable {

    /// Seconds per point of trackpad travel. A full swipe across a trackpad is
    /// about 300 points, which at this rate is a minute — enough to cross a
    /// scene, not enough to lose the place.
    public static let secondsPerPoint = 0.2
    /// Seconds per notch of a wheel without precise deltas.
    public static let secondsPerNotch = 5.0
    /// Nothing is issued until this much has accumulated, so a hand resting on
    /// the trackpad does not issue sub-second seeks.
    public static let threshold = 1.0

    private var accumulated = 0.0

    public init() {}

    /// Adds one event and returns the seconds to seek by, if a whole step has
    /// accumulated. Positive is forward.
    public mutating func add(deltaX: Double, precise: Bool) -> Double? {
        // AppKit reports leftward travel as positive; mpv, and the timeline,
        // read rightward as forward.
        let forward = -deltaX
        accumulated += precise ? forward * Self.secondsPerPoint
                               : forward * Self.secondsPerNotch
        guard abs(accumulated) >= Self.threshold else { return nil }
        let step = accumulated.rounded(.towardZero)
        accumulated -= step
        return step
    }

    /// Drops what has not yet been issued — at the end of a gesture, so the
    /// remainder of one swipe does not become the start of the next.
    public mutating func reset() {
        accumulated = 0
    }
}

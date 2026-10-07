import SwiftUI

/// Apple TV's focus lift, for a pointer: the hovered card tilts a little
/// toward where the pointer is, and a soft light crosses it with the pointer —
/// the parallax shine tvOS gives a focused poster. Paired with the scale and
/// shadow the cards already have on hover.
///
/// Off for anyone who has asked macOS to reduce motion; the lift stays.
struct TVLift: ViewModifier {
    let corner: CGFloat
    /// The card's size, which every card knows — passed rather than measured,
    /// since a measuring view per card on a shelf of hundreds is not free.
    let size: CGSize
    @State private var point: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let unit = normalised
        return content
            .overlay {
                if let unit, !reduceMotion {
                    RadialGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0)],
                        center: UnitPoint(x: unit.x, y: unit.y),
                        startRadius: 0, endRadius: max(size.width, size.height) * 0.9
                    )
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(tilt(unit?.y, reversed: true)), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt(unit?.x, reversed: false)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): point = location
                case .ended: point = nil
                }
            }
            .animation(.easeOut(duration: 0.18), value: point)
    }

    /// Up to 3.5° toward the pointer.
    private func tilt(_ fraction: CGFloat?, reversed: Bool) -> Double {
        guard let fraction, !reduceMotion else { return 0 }
        let offset = Double(fraction) - 0.5
        return (reversed ? -offset : offset) * 7.0
    }

    private var normalised: CGPoint? {
        guard let point, size.width > 0, size.height > 0 else { return nil }
        return CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
    }
}

extension View {
    func tvLift(corner: CGFloat, size: CGSize) -> some View { modifier(TVLift(corner: corner, size: size)) }
}

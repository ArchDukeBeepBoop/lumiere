import SwiftUI

/// The pieces the player's chrome is assembled from: the surface a floating slab
/// sits on, the scrims that keep text legible over a bright scene, the secondary
/// icon button, and the Close button.
///
/// One file rather than repeated per control, for the same reason `Theme.Elevation`
/// exists: what makes chrome read as one designed surface is that every control on
/// it is the same size, lights up by the same amount, and sits on the same plate.

// MARK: - Surface

extension View {

    /// The plate under the transport bar and every floating panel.
    ///
    /// A material *and* a tint, in that order. `Material` blurs the window's own
    /// backdrop, and the picture is an AppKit layer — AVPlayer's or mpv's — rather
    /// than SwiftUI content, so the blur may sample nothing at all depending on the
    /// engine. The tint is therefore what actually carries the surface; the
    /// material is free frosting where the compositor gives it.
    func playerSurface(cornerRadius: CGFloat) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                GlassFill(shape: shape)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Theme.PlayerPalette.surfaceTop,
                            Theme.PlayerPalette.surfaceBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.strokeBorder(Theme.PlayerPalette.surfaceStroke, lineWidth: 1)
            }
            .shadow(
                color: Theme.PlayerPalette.surfaceShadow,
                radius: Theme.PlayerMetric.surfaceShadow,
                y: Theme.PlayerMetric.surfaceShadowY
            )
        }
    }
}

/// The wash at the top and bottom of the picture.
///
/// Chrome over a bright scene is unreadable however the bar itself is styled,
/// because the title and the badges sit outside the bar with nothing behind them.
/// A gradient rather than a band, so there is no edge to notice.
struct PlayerScrim: View {
    let edge: VerticalEdge

    var body: some View {
        LinearGradient(
            colors: [colour, .clear],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: Theme.PlayerMetric.scrimHeight)
        .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var colour: Color {
        edge == .top ? Theme.PlayerPalette.scrimTop : Theme.PlayerPalette.scrimBottom
    }
}

// MARK: - Controls

/// Everything on the transport that is not play.
///
/// The hover plate is drawn only while hovered rather than always: a row of eight
/// permanently plated glyphs reads as eight buttons competing with each other,
/// which is exactly what a subordinate control must not do.
struct PlayerIconButton: View {
    let systemName: String
    let help: String
    /// True while the thing this button opens is open.
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Theme.PlayerMetric.secondaryGlyph, weight: .medium))
                .foregroundStyle(
                    isHovering || isActive
                        ? Theme.Palette.onPlayerChrome
                        : Theme.Palette.onPlayerChromeSecondary
                )
                .frame(
                    width: Theme.PlayerMetric.secondaryButton,
                    height: Theme.PlayerMetric.secondaryButton
                )
                .background {
                    Circle()
                        .fill(
                            isActive
                                ? Theme.PlayerPalette.controlActive
                                : Theme.PlayerPalette.controlHover
                        )
                        .opacity(isHovering || isActive ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .animation(Theme.Motion.hover, value: isActive)
        .labelledHelp(help)
    }
}

/// The way out, in every state the player can be in.
///
/// Top *right* rather than top left: the window keeps its traffic lights during
/// playback — see `WindowChrome` — and a second close affordance under them is
/// both a collision and a coin toss about which one you hit.
struct PlayerCloseButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .frame(
                    width: Theme.PlayerMetric.closeButton,
                    height: Theme.PlayerMetric.closeButton
                )
                .background {
                    Circle().fill(
                        isHovering
                            ? Theme.PlayerPalette.controlActive
                            : Theme.Palette.playerChrome
                    )
                }
                .overlay {
                    Circle().strokeBorder(
                        Theme.PlayerPalette.surfaceStroke, lineWidth: 1
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .labelledHelp("Close the player (Escape)")
    }
}

import SwiftUI
import AppKit

/// The window's translucent backing, and the switch that turns it off.
///
/// Real glass on macOS is not a colour with opacity — it is `NSVisualEffectView`
/// sampling what is *behind the window* and blurring it, which is why the sidebar
/// and the menu bar look the way they do and a semi-transparent `Color` never
/// does. Two things have to be true for it: the effect view must be present, and
/// the window itself must stop being opaque, or AppKit fills the frame before
/// anything gets to sample through it.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        // Behind the window, not within it: `withinWindow` blurs this app's own
        // content, which is the frosted-panel look. This is the desktop showing
        // through, which is the one that reads as glass.
        view.blendingMode = .behindWindow
        // Active regardless of focus. The default dulls to grey when the window
        // loses key, and a media library that goes flat while you glance at
        // another app looks broken rather than unfocused.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Makes the hosting window translucent, and puts it back when glass is off.
///
/// Separate from the effect view because it acts on the window rather than on a
/// subview, and because it has to be undone: leaving `isOpaque` false with no
/// effect view behind it gives a window you can see the desktop through in full,
/// which is not a subtle bug to ship.
private struct WindowTransparency: NSViewRepresentable {
    let isGlass: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // On the next runloop pass: the view has no window at make time.
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = !isGlass
        window.backgroundColor = isGlass ? .clear : .windowBackgroundColor
    }
}

extension View {
    /// The sidebar's own backing, heavier than the content area's.
    ///
    /// The window is clear now, and a bare `List` has no background of its own, so
    /// the whole column went see-through — including the strip behind the traffic
    /// lights, where whatever app sits underneath shows through the icons. A
    /// sidebar has to stay legible at a glance while your eye is somewhere else,
    /// so it gets AppKit's `.sidebar` material and a much heavier scrim: frosted
    /// rather than clear.
    func sidebarBackground(_ isGlass: Bool) -> some View {
        background {
            if isGlass {
                ZStack {
                    GlassBackground(material: .sidebar)
                    // Deliberately not the content tint. Text and icons sit
                    // directly on this, and it is a fixed narrow column rather
                    // than something you scroll art through.
                    Theme.Palette.canvas.opacity(0.86)
                }
                .ignoresSafeArea()
            } else {
                ZStack {
                    Theme.Palette.canvas
                    PaperGrainLayer()
                }
                .ignoresSafeArea()
            }
        }
    }

    /// The app's background: glass where it is turned on, the flat canvas where it
    /// is not.
    ///
    /// The canvas colour stays as a scrim over the blur rather than being replaced
    /// by it. Posters and white text sit on this, and a wallpaper showing through
    /// at full strength makes both unreadable — the blur is atmosphere, not the
    /// surface things are read against.
    func glassBackground(_ isGlass: Bool, opacity: Double) -> some View {
        background {
            if isGlass {
                ZStack {
                    GlassBackground()
                    Theme.Palette.canvas.opacity(opacity)
                }
                .ignoresSafeArea()
            } else {
                Theme.Palette.canvas.ignoresSafeArea()
            }
        }
        .background(WindowTransparency(isGlass: isGlass))
    }
}

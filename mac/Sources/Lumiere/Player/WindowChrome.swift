import SwiftUI
import AppKit

/// Hides the window's title bar while the player is up.
///
/// The player fills the window, but the window still drew its toolbar strip above
/// the video — a pale band across the top of a film, which is exactly the kind of
/// chrome Infuse does not have. SwiftUI has no way to say "no title bar for this
/// state", so the window gets configured directly.
///
/// `fullSizeContentView` is what lets the picture extend under the title bar rather
/// than starting below it; without it the band turns black instead of disappearing.
struct WindowChrome: NSViewRepresentable {
    let immersive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Purely a handle on the window. It draws nothing.
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let immersive = self.immersive
        // The window is not attached during the first update pass, so this waits a
        // turn rather than doing nothing on the transition into playback.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            apply(immersive, to: window)
        }
    }

    private func apply(_ immersive: Bool, to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = immersive

        if immersive {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }

        // The toolbar is what actually paints the pale band, so hiding the title
        // alone is not enough.
        window.toolbar?.isVisible = !immersive

        // The traffic lights stay: this is a window filling itself with video, not
        // true full screen, and a window with no way to close it is a trap.
    }
}

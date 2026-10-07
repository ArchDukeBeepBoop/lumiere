import AppKit

/// Video › Mini Player: the window as a small floating picture in the corner
/// of the screen, and back again.
///
/// Not picture in picture. That needs mpv to draw into a second window while
/// the first goes on browsing, which is a new video surface rather than a
/// command; for files Apple's player handles the real thing already exists on
/// the player's own bar. This is the part that is honest to offer: keep
/// watching in a corner while something else on the Mac has the screen.
@MainActor
enum MiniPlayer {
    private static var saved: (frame: NSRect, level: NSWindow.Level)?

    static var isOn: Bool { saved != nil }

    static func toggle() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        if let saved {
            window.setFrame(saved.frame, display: true, animate: true)
            window.level = saved.level
            self.saved = nil
            return
        }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        saved = (window.frame, window.level)
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = NSSize(width: 480, height: 270 + 28)
        let origin = NSPoint(x: screen.maxX - size.width - 20, y: screen.minY + 20)
        window.level = .floating
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }
}

import AppKit

/// The pointer over the player: hidden while it rests on the film after the
/// controls fade, back the moment the mouse does anything, anywhere.
///
/// `NSCursor.setHiddenUntilMouseMoves` did not hold — the controls fading
/// changes the views under the pointer, AppKit resets their cursor rects, and
/// the pointer came straight back. `hide()` holds, but it hides the pointer
/// for the whole app, and it was only brought back by movement *over the
/// player*: move first over the sidebar, or switch apps, and it stayed gone
/// everywhere. So while it is hidden, any mouse event in the app brings it
/// back, and so does the app losing focus. It is a counted call; this keeps
/// the count at one at most, and leaving the player always shows it.
@MainActor
enum PlayerPointer {
    private static var hidden = false
    /// Where the pointer was when it was hidden. A hover event can arrive with
    /// the mouse still — the views under it changed as the controls faded —
    /// and that is not a reason to show it.
    private static var hiddenAt: NSPoint = .zero
    private static var monitor: Any?
    private static var resign: NSObjectProtocol?

    static func hide() {
        guard !hidden else { return }
        hidden = true
        hiddenAt = NSEvent.mouseLocation
        NSCursor.hide()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                       .leftMouseDragged, .scrollWheel]
        ) { event in
            // A click shows it even with the mouse still; a move must be a move.
            PlayerPointer.show(force: event.type != .mouseMoved)
            return event
        }
        resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PlayerPointer.show(force: true) }
        }
    }

    /// Shows it if the mouse has moved since it was hidden, or always when
    /// `force` — leaving the player, or the app.
    static func show(force: Bool = false) {
        guard hidden, force || NSEvent.mouseLocation != hiddenAt else { return }
        hidden = false
        NSCursor.unhide()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resign { NotificationCenter.default.removeObserver(resign) }
        monitor = nil
        resign = nil
    }
}

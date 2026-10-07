import AppKit
import LocalAuthentication
import LumiereKit

/// The private room: the private libraries as a space of their own.
///
/// "Show Private Libraries" used to add them beside everything else, which
/// mixed an adult library into the same Home, the same Continue Watching and
/// the same search as everything the household watches. Now it is a room you
/// go into. Inside: only those libraries, their own Home, a quieter palette,
/// the window titled plainly and closed to screen capture. Outside: none of it.
///
/// Entering can ask for Touch ID or the Mac's password — the Mac's own lock,
/// never a password of Lumiere's — and the room closes itself when Lumiere has
/// been in the background for the time chosen in Settings.
@MainActor
extension AppModel {

    /// Opens the room, after the Mac's own authentication if that is on.
    func enterRoom() async {
        guard hasPrivateLibraries, !isShowingPrivateLibraries else { return }
        if Preference.roomRequiresUnlock.value, !(await Self.unlock()) { return }
        RoomPreferences.enter()
        RoomChrome.apply(inRoom: true)
        await setShowingPrivateLibraries(true)
        pendingRoute = .home
        Diagnostics.log("[room] entered")
    }

    /// Leaves the room: back to the main Home, the palette and window as they
    /// were, and nothing of the room left in the back stack.
    func leaveRoom() async {
        guard isShowingPrivateLibraries else { return }
        RoomPreferences.leave()
        RoomChrome.apply(inRoom: false)
        await setShowingPrivateLibraries(false)
        pendingRoute = .home
        Diagnostics.log("[room] left")
    }

    /// The quick hide: stop whatever is playing and leave, at once.
    func hideNow() async {
        nowPlayingItemId = nil
        await leaveRoom()
        pendingRoute = .home
    }

    private static func unlock() async -> Bool {
        let context = LAContext()
        var error: NSError?
        // Touch ID where there is a sensor, the login password where there is not.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: "open your private libraries"
        )) ?? false
    }

    /// Closes the room after Lumiere has been in the background for the chosen
    /// time. Started once at launch.
    func watchRoomIdle() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in RoomIdle.leftAt = Date() }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isShowingPrivateLibraries, let left = RoomIdle.leftAt else { return }
                let minutes = Preference.roomLockMinutes.value
                if minutes >= 0, Date().timeIntervalSince(left) >= Double(minutes) * 60 {
                    await self.leaveRoom()
                }
            }
        }
    }
}

@MainActor
enum RoomIdle {
    static var leftAt: Date?
}

/// What changes about the window in the room: its palette, its title, and
/// whether it can be captured.
@MainActor
enum RoomChrome {
    /// Whether the room is open, for titles decided while it is.
    static var isOpen = false
    /// The appearance the room replaced, put back when it closes.
    private static var outside: NSAppearance?
    private static var replaced = false

    static func apply(inRoom: Bool) {
        isOpen = inRoom
        RoomTheme.isOn = inRoom && Preference.roomUsesOwnTheme.value
        for window in NSApp.windows where window.isVisible {
            // Kept out of screenshots, screen sharing and recordings while inside.
            window.sharingType = inRoom && Preference.roomBlocksCapture.value ? .none : .readOnly
            // The title is what the Dock, Mission Control and the Window menu show.
            window.title = "Lumiere"
        }
        // The palette is resolved when drawn; a nudge to the appearance makes
        // every view draw again with the room's colours, or without them.
        //
        // The room is dark, whatever the Mac is, so the sidebar's system-drawn
        // labels are light on its dark ground. What it replaced is kept from
        // before the room took over — reading NSApp.appearance on the way out
        // read the room's own dark, and the app stayed dark after leaving.
        if inRoom && RoomTheme.isOn {
            if !replaced { outside = NSApp.appearance; replaced = true }
            NSApp.appearance = NSAppearance(named: .aqua)
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            NSApp.appearance = replaced ? outside : NSApp.appearance
            replaced = false
        }
    }
}

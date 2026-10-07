import Foundation
import ServiceManagement

/// Whether this controller starts itself at login.
///
/// The server, not Lumiere. That distinction is the whole point of the setting:
/// a media server is only useful if it is already up when you go looking for
/// something to watch, whereas an app that opens itself at login is an
/// imposition. So the controller launches, starts the server, and waits in the
/// menu bar; the player stays closed until asked for.
///
/// SMAppService rather than a LaunchAgent plist written by hand: the plist
/// approach still works but the approval lives in System Settings either way,
/// and this way macOS keeps the two in step instead of leaving a stale file
/// behind when the app moves.
@MainActor
@Observable
final class LoginItem {

    private(set) var isEnabled: Bool = false
    private(set) var problem: String?

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Turn this on the first time the app is run, and never again.
    ///
    /// A media server is only useful if it is already up when you go looking for
    /// something to watch, so starting at login is the intended default. Trying
    /// exactly once is the part that matters: if the setting is later turned off
    /// — here, or in System Settings — this must not quietly turn it back on at
    /// the next launch. A default is a starting point, not a policy.
    func enableOnFirstRun() {
        let key = "hasOfferedLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }

    func set(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            // The usual cause is the app not being in /Applications, or a
            // previous approval the user revoked. Saying so beats a checkbox
            // that silently springs back.
            problem = error.localizedDescription
        }
        refresh()
    }
}

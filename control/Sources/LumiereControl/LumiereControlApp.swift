import AppKit
import ControlCore
import SwiftUI

/// A menu bar controller for Lumiere and its media server.
///
/// MenuBarExtra with no window and no Dock icon: `LSUIElement` in the Info.plist
/// makes it an accessory, which is what a thing that lives in the menu bar
/// should be. There is no main window at all — a controller with a window would
/// be an application, and this is a switch.
@main
struct LumiereControlApp: App {
    @NSApplicationDelegateAdaptor(Startup.self) private var startup

    var body: some Scene {
        MenuBarExtra {
            MenuView(
                server: startup.server,
                lumiere: startup.lumiere,
                backups: startup.backups,
                monitor: startup.monitor
            )
        } label: {
            // The prism, as a template image: holding its play mark while the
            // server is serving, empty while it is not. State carried by shape, because a template
            // image has no colour to carry it with.
            Image(nsImage: PrismGlyph.image(running: startup.server.state == .running))
        }
        .menuBarExtraStyle(.window)

        // Every backup with what it holds, opened from the Backups section.
        Window("Backups", id: BackupBrowser.windowID) {
            BackupBrowser(backups: startup.backups, server: startup.server)
        }
        .windowResizability(.contentMinSize)
        // Opened from the menu only. Without this SwiftUI may open it at
        // launch, and a menu bar app that greets you with a window is not one.
        .defaultLaunchBehavior(.suppressed)

        // The window behind "Settings…" — options live here, not in the menu.
        Settings {
            SettingsView(loginItem: startup.loginItem, server: startup.server)
        }
    }
}

/// Everything that must happen at launch, whether or not anyone opens the menu.
///
/// An app delegate rather than a `.task` on the menu's content view, and the
/// difference is not stylistic: `MenuBarExtra(.window)` does not build its
/// content until the icon is clicked, so startup work attached there simply does
/// not run. The app sat in the menu bar with the server stopped until you opened
/// the menu — which is the one moment you least need it to start.
@MainActor
final class Startup: NSObject, NSApplicationDelegate {
    let server = ServerProcess()
    let lumiere = AppLauncher()
    let loginItem = LoginItem()
    let backups = BackupRestorer()
    let monitor = LibraryMonitor()
    let notifier = Notifier()

    private var watcher: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItem.enableOnFirstRun()
        lumiere.refresh()
        watcher = Task { [weak self] in await self?.run() }
    }

    /// Stopping the server on quit is deliberate and the menu says so. The
    /// alternative is an orphaned process that outlives the thing that started
    /// it, holding port 8098 against the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        watcher?.cancel()
        server.stop()
    }

    /// Set when the watchdog stopped trying, so a server it gave up on stays
    /// down until someone starts it from the menu.
    private var gaveUp = false

    /// Restarts, or gives up and says so. A server this app did not start is
    /// only reported: signalling a process found already running is not this
    /// app's to do.
    private func act(_ action: Watchdog.Action, why: String) async {
        switch action {
        case .none:
            break
        case .restart(let pause):
            guard server.ownsProcess || server.state != .running else {
                notifier.serverStopped("A server started elsewhere is not answering.")
                return
            }
            server.note("restarting the server: \(why)")
            await server.stopAndWait()
            try? await Task.sleep(for: pause)
            server.start()
        case .giveUp:
            gaveUp = true
            let reason = "Stopped after five restarts in ten minutes. Show Server Log says why."
            server.note("gave up: \(why), five restarts in ten minutes")
            server.giveUp(reason)
            notifier.serverStopped(reason)
        }
    }

    private func run() async {
        // Adopt before starting, always. A server left running from a terminal
        // or a previous launch would otherwise be met with a second one, and
        // the port clash reported as a failure — exactly the confusion this app
        // exists to remove.
        await server.adoptIfAlreadyRunning()
        if server.state == .stopped {
            server.start()
        }
        // A slow poll: the interesting transitions are ones this app caused and
        // already knows about. This catches only the others — a server that
        // died, or Lumiere quit from its own menu.
        var beat = 0
        var dog = Watchdog()
        var toldMissing = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            lumiere.refresh()
            switch server.state {
            case .running:
                let action = dog.probed(answered: await server.isLive(), now: Date())
                await act(action, why: "it stopped answering for 15 seconds")
            case .failed(let why) where !server.libraryMissing && !gaveUp:
                // A stop nobody asked for: `.failed` is only ever set by the
                // process exiting on its own, never by Stop in the menu.
                await act(dog.crashed(now: Date()), why: "it stopped by itself (\(why))")
            default:
                break
            }
            // One notification for a missing library — the one stop that needs
            // a person — and it is withdrawn once the server is back.
            if server.libraryMissing, !toldMissing {
                notifier.serverStopped("The library is missing. Open the menu to restore a backup.")
                toldMissing = true
            }
            if server.state == .running {
                if gaveUp || toldMissing { notifier.serverBack() }
                gaveUp = false
                toldMissing = false
            }
            // Library numbers every 15 s; the menu also refreshes on opening.
            beat += 1
            if beat % 3 == 0 { await monitor.refresh() }
        }
    }
}

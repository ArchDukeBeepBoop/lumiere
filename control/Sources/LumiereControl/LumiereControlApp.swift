import AppKit
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
            // The iris, as a template image: open while the server is serving,
            // shut while it is not. State carried by shape, because a template
            // image has no colour to carry it with.
            Image(nsImage: IrisGlyph.image(running: startup.server.state == .running))
        }
        .menuBarExtraStyle(.window)

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
        var reported = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            lumiere.refresh()
            if server.state == .running, await !server.isAnswering() {
                server.stop()
                notifier.serverStopped("It stopped answering. Open the menu to start it again.")
                reported = true
            }
            // A stop nobody asked for. `.failed` is only ever set by the process
            // exiting on its own — a Stop from the menu goes to `.stopped` — so
            // this cannot fire for something the user just did.
            if case .failed(let why) = server.state, !reported {
                notifier.serverStopped(why)
                reported = true
            }
            if server.state == .running, reported {
                notifier.serverBack()
                reported = false
            }
            // Library numbers every 15 s; the menu also refreshes on opening.
            beat += 1
            if beat % 3 == 0 { await monitor.refresh() }
        }
    }
}

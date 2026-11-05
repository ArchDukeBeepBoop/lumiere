import AppKit
import Foundation

/// Launching and quitting Lumiere itself.
///
/// Quitting is done by asking, not by killing. `terminate()` on a running
/// application sends the same request the Quit menu item does, so the player
/// gets to report its final position to the server before it goes — which is
/// the difference between resuming where you stopped and resuming where you
/// last happened to send a progress report.
@MainActor
@Observable
final class AppLauncher {

    private(set) var isRunning = false

    /// The bundle identifier is the reliable handle. Matching on the name would
    /// find any application called Lumiere, and matching on the path would break
    /// the moment the app moved out of /Applications.
    // Read from the installed app, not guessed. The first version assumed
    // "com.lumiere.app"; it is "com.lumiere.client", and the difference is a
    // menu item that quietly does nothing — NSWorkspace returns no match and
    // there is no error to notice.
    private let bundleID = "com.lumiere.client"
    private let fallbackPath = URL(fileURLWithPath: "/Applications/Lumiere.app")

    func refresh() {
        isRunning = !runningInstances().isEmpty
    }

    /// The async form, never the completion handler. That handler is not
    /// `@Sendable`, so written here it inherits the main actor — and Launch
    /// Services calls it on its own queue, where Swift's isolation check traps
    /// (SIGILL, no message). Every press of the Lumiere tile crashed this app,
    /// and the server, whose output runs through this app, died with it: the
    /// "server stops when Lumiere starts" of 2026-10-25.
    func launch() {
        guard let url = installedURL() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            refresh()
        }
    }

    func quit() {
        for app in runningInstances() {
            app.terminate()
        }
        // The state is not set here. terminate() is a request the app may take a
        // moment to honour — it is saving a playback position — and reporting
        // "quit" before it has quit would make the menu lie for a second.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.refresh()
        }
    }

    var isInstalled: Bool { installedURL() != nil }

    private func runningInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    private func installedURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        // A freshly built copy that has never been launched is not yet in
        // Launch Services' database, so the well-known path is a real fallback
        // rather than a guess.
        return FileManager.default.fileExists(atPath: fallbackPath.path) ? fallbackPath : nil
    }
}

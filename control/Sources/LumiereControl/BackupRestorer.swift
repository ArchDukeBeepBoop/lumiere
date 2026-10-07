import AppKit
import ControlCore
import Foundation

/// Putting the library back as it was on a given day.
///
/// The server keeps a week of daily copies of its database — the one file
/// holding what has been watched, which no rescan can rebuild. Copies are only
/// worth having if using one is simple, so this lists them by date and
/// restores one in place: the server stops, today's database is set aside
/// beside it (never deleted), the copy goes in, and the server starts again.
@MainActor
@Observable
final class BackupRestorer {

    struct Backup: Identifiable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    private(set) var backups: [Backup] = []
    private(set) var message: String?

    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LumiereServer")

    func note(_ text: String) { message = text }

    func refresh() {
        let dir = Self.dataDir.appendingPathComponent("backups")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        backups = files
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "db" }
            .compactMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return date.map { Backup(url: url, date: $0) }
            }
            .sorted { $0.date > $1.date }
    }

    /// Asks, then restores.
    func restore(_ backup: Backup, server: ServerProcess) async {
        let alert = NSAlert()
        alert.messageText = "Restore the library from \(backup.date.formatted(date: .abbreviated, time: .shortened))?"
        alert.informativeText = "Watch history and changes since then will be undone. "
            + "Today's database is kept beside it as library.db.before-restore, so this "
            + "can be reversed by hand. The server restarts."
        MenuLook.style(alert)
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let wasRunning = server.state == .running || server.state == .starting
        await server.stopAndWait()
        do {
            try BackupSwap.swap(in: backup.url, dataDir: Self.dataDir)
            message = "Restored from \(backup.date.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            message = "Could not restore: \(error.localizedDescription)"
        }
        if wasRunning { server.start() }
    }
}

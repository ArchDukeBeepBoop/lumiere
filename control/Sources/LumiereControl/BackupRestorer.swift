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
        /// From the second folder rather than the first.
        var onMirror = false
        var id: URL { url }
    }

    private(set) var backups: [Backup] = []
    private(set) var message: String?

    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LumiereServer")

    /// The daily copies' own folder — not inside `dataDir`, so whatever empties
    /// one does not empty the other. The server moves copies here from the old
    /// `backups/` beside the database on its first start.
    static let backupDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LumiereServer Backups")

    static let mirrorKey = "backupMirrorPath"

    /// The second folder chosen in Settings, ideally on another disk.
    static var mirrorFolder: URL? {
        UserDefaults.standard.string(forKey: mirrorKey).map { URL(fileURLWithPath: $0) }
    }

    func note(_ text: String) { message = text }

    /// Both folders, newest first. A copy in both is listed once, from the
    /// first folder; one only on the second disk — because the first was
    /// emptied — is listed from there, which is the point of having it.
    func refresh() {
        var seen = Set<String>()
        let folders = [(Self.backupDir, false)] + (Self.mirrorFolder.map { [($0, true)] } ?? [])
        backups = folders.flatMap { dir, onMirror in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files
                .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "db" }
                .filter { seen.insert($0.lastPathComponent).inserted }
                .compactMap { url in
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    return date.map { Backup(url: url, date: $0, onMirror: onMirror) }
                }
        }
        .sorted { $0.date > $1.date }
    }

    /// Where the copies are and how old, for the Restore row.
    var health: BackupHealth {
        let mirror = Self.mirrorFolder.map { folder -> (name: String, newest: Date?, attached: Bool) in
            let newest = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]))?
                .filter { $0.pathExtension == "db" }
                .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                .max()
            let attached = FileManager.default.fileExists(atPath: folder.path)
            // The volume's name says more than the folder's: "on Media"
            let volume = (try? folder.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            let name = folder.path.hasPrefix("/Volumes/") ? (volume ?? folder.lastPathComponent)
                : folder.lastPathComponent
            return (name, newest, attached)
        }
        return BackupHealth.summarize(newest: backups.first { !$0.onMirror }?.date,
                                      mirror: mirror, now: Date())
    }

    /// Asks, then restores.
    func restore(_ backup: Backup, server: ServerProcess) async {
        let alert = NSAlert()
        alert.messageText = "Restore the library from \(backup.date.formatted(date: .abbreviated, time: .shortened))?"
        alert.informativeText = "Watch history and changes since then will be undone. "
            + "Today's database is kept beside it as library.db.before-restore, so this "
            + "can be reversed by hand. The server restarts."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // A server that refused to start for want of a library is one to start
        // once the library is back.
        let wasRunning = server.state == .running || server.state == .starting
            || server.libraryMissing
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

import Foundation

/// The file half of restoring a backup, apart from the menu so it can be
/// tested against a folder. It moves the only copy of the watch history, so
/// it is the part that must be proven rather than read. See `BackupRestorer`.
public enum BackupSwap {

    public enum Failure: Error { case backupMissing }

    /// Sets the live database aside and copies the backup into its place.
    ///
    /// All or nothing. The backup is checked before anything moves, and if
    /// the copy fails after today's files were set aside they are put back —
    /// otherwise the server would start on no database at all and create an
    /// empty library over the watch history it was meant to restore.
    public static func swap(in backup: URL, dataDir: URL) throws {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: backup.path) else { throw Failure.backupMissing }
        let live = dataDir.appendingPathComponent("library.db")
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let aside = dataDir.appendingPathComponent("library.db.before-restore-\(stamp)")

        // The write-ahead log belongs to the database set aside; left behind,
        // SQLite would replay it into the restored copy.
        var moved: [(from: URL, to: URL)] = []
        for suffix in ["", "-wal", "-shm"] {
            let file = dataDir.appendingPathComponent("library.db" + suffix)
            guard fm.fileExists(atPath: file.path) else { continue }
            let target = dataDir.appendingPathComponent(aside.lastPathComponent + suffix)
            try fm.moveItem(at: file, to: target)
            moved.append((file, target))
        }
        do {
            try fm.copyItem(at: backup, to: live)
        } catch {
            try? fm.removeItem(at: live)
            for m in moved { try? fm.moveItem(at: m.to, to: m.from) }
            throw error
        }
    }
}

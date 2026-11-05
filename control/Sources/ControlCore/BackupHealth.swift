import Foundation

/// One line on whether the backups are keeping up, for the menu.
///
/// On 2026-10-25 a week of verified copies was lost along with the database
/// they protected, and nothing anywhere had said they were all in one place.
/// This says where the copies are and how old, and turns red when either place
/// has fallen behind — the 48 hours of the plan, two missed nights.
public struct BackupHealth: Equatable, Sendable {
    public let text: String
    public let warning: Bool

    public static let staleAfter: TimeInterval = 48 * 3600

    /// - Parameters:
    ///   - newest: the newest copy in the backup folder.
    ///   - mirror: the second folder's name and newest copy, when one is set;
    ///     `attached` false when its disk is not plugged in.
    public static func summarize(newest: Date?, mirror: (name: String, newest: Date?, attached: Bool)?,
                                 now: Date) -> BackupHealth {
        var parts: [String] = []
        var warning = false
        if let newest {
            let stale = now.timeIntervalSince(newest) > staleAfter
            warning = warning || stale
            parts.append((stale ? "Last backed up " : "Backed up ") + relative(newest, now))
        } else {
            parts.append("No backup yet")
            warning = true
        }
        if let mirror {
            if let copy = mirror.newest, now.timeIntervalSince(copy) <= staleAfter {
                parts.append("second copy on \(mirror.name)")
            } else if !mirror.attached {
                // A removable disk away for a night is ordinary; away for two
                // is a second copy that is not being made.
                parts.append("\(mirror.name) not attached")
                warning = warning || mirror.newest.map { now.timeIntervalSince($0) > staleAfter } ?? true
            } else {
                parts.append("second copy " + (mirror.newest.map { relative($0, now) } ?? "not made yet"))
                warning = true
            }
        } else {
            parts.append("no second copy")
        }
        return BackupHealth(text: parts.joined(separator: " · "), warning: warning)
    }

    private static func relative(_ date: Date, _ now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

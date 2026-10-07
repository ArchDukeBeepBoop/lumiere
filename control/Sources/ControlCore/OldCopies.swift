import Foundation

/// Database copies left beside the live one by hand, before the daily
/// backups existed: `library.db.pre-<change>` from before a risky change,
/// and `library.db.before-restore-…` from a restore. Each is the whole
/// library, half a gigabyte, and the week of daily backups has made them
/// redundant. Listed so they can be moved to the Trash — never deleted
/// outright, and never the live database, its WAL or the backups folder.
public enum OldCopies {

    public struct Copy: Sendable {
        public let url: URL
        public let bytes: Int64
    }

    public static func list(in dataDir: URL) -> [Copy] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dataDir.path)) ?? []
        return names
            .filter { isOldCopy($0) }
            .sorted()
            .map { name in
                let url = dataDir.appendingPathComponent(name)
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                return Copy(url: url, bytes: size)
            }
    }

    /// Only the hand-made kinds. Pure, so the rule can be tested by name.
    public static func isOldCopy(_ name: String) -> Bool {
        guard name.hasPrefix("library.db.") else { return false }
        let rest = String(name.dropFirst("library.db.".count))
        return rest.hasPrefix("pre-") || rest.hasPrefix("before-restore-")
    }

    /// Moves each to the Trash. Returns how many went.
    @discardableResult
    public static func trash(_ copies: [Copy]) -> Int {
        copies.reduce(0) { count, copy in
            (try? FileManager.default.trashItem(at: copy.url, resultingItemURL: nil)) != nil
                ? count + 1 : count
        }
    }
}

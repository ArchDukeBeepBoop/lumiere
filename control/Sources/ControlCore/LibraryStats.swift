import Foundation
import SQLite3

/// What the menu says about the library, read straight from the server's
/// database — read-only, never written.
///
/// Read here rather than asked of the server because every useful route on it
/// needs a token, and this app has none: it starts the server, it does not sign
/// in to it. SQLite in WAL mode lets a reader in beside a writer without
/// blocking either, so a count taken while a scan runs costs the scan nothing.
///
/// Private libraries are left out of every number. They are hidden in the app
/// behind a room the user has to open, and a menu bar is the most public
/// surface on the machine — counts are innocuous, but "this library exists"
/// is exactly what a private room is for not saying.
public struct LibraryStats: Equatable, Sendable {
    public var films = 0
    public var shows = 0
    public var episodes = 0
    public var tracks = 0
    public var watched = 0
    public var inProgress = 0
    /// Something reported playback in the last three minutes — the same window
    /// the server uses to hold back scans and previews.
    public var isPlaying = false
    public var lastScan: Date?
    public var backupsVerifiedAt: Date?
    public var backupCheckFailed = false
    /// Whether the server also answers on the home network, from its own
    /// settings. Read rather than probed: connecting to this Mac's LAN address
    /// from an app trips macOS's Local Network permission prompt, which would
    /// be a strange thing for a status line to cause.
    public var listensOnNetwork = false

    public init() {}

    /// Reads the stats, or nil if the database cannot be opened. Nil and an
    /// empty library are different answers and the menu shows them differently.
    public static func read(database: URL, now: Date = Date()) -> LibraryStats? {
        var db: OpaquePointer?
        let uri = "file:\(database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? database.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        // Short: a count that has to wait is a count the menu can skip.
        sqlite3_busy_timeout(db, 300)

        let hidden = privateFolders(db)
        let visible = hidden.isEmpty ? "" :
            " AND (library_id IS NULL OR library_id NOT IN (\(hidden.map { "'\($0)'" }.joined(separator: ","))))"

        var s = LibraryStats()
        s.films = count(db, "SELECT COUNT(*) FROM item WHERE type = 'Movie' AND extra_type IS NULL" + visible)
        s.shows = count(db, "SELECT COUNT(*) FROM item WHERE type = 'Series'" + visible)
        s.episodes = count(db, "SELECT COUNT(*) FROM item WHERE type = 'Episode' AND extra_type IS NULL" + visible)
        s.tracks = count(db, "SELECT COUNT(*) FROM item WHERE type = 'Audio'" + visible)
        let watchedJoin = "FROM user_data u JOIN item i ON i.id = u.item_id WHERE 1=1"
            + visible.replacingOccurrences(of: "library_id", with: "i.library_id")
        s.watched = count(db, "SELECT COUNT(*) " + watchedJoin + " AND u.played = 1")
        s.inProgress = count(db, "SELECT COUNT(*) " + watchedJoin
                             + " AND u.played = 0 AND u.position_ticks > 0")

        let since = iso(now.addingTimeInterval(-180))
        s.isPlaying = count(db, "SELECT COUNT(*) FROM user_data WHERE source = 'local' AND updated_at > '\(since)'") > 0
        s.lastScan = meta(db, "auto_scan_at").flatMap(parse)
        s.backupsVerifiedAt = meta(db, "restore_check_at").flatMap(parse)
        s.backupCheckFailed = !(meta(db, "restore_check_failed") ?? "").isEmpty
        if let raw = meta(db, "server_settings")?.data(using: .utf8),
           let settings = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            s.listensOnNetwork = settings["ListensOnNetwork"] as? Bool ?? false
        }
        return s
    }

    /// Physical folders behind the private views. The setting names views; the
    /// items carry their folder's id, so the one is mapped to the other.
    static func privateFolders(_ db: OpaquePointer?) -> [String] {
        let views = (meta(db, "private_libraries") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.allSatisfy { $0.isHexDigit } && !$0.isEmpty }
        guard !views.isEmpty else { return [] }
        let list = views.map { "'\($0)'" }.joined(separator: ",")
        return strings(db, "SELECT folder_id FROM library_folder WHERE view_id IN (\(list))")
            .filter { $0.allSatisfy { $0.isHexDigit } }
    }

    static func count(_ db: OpaquePointer?, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    static func strings(_ db: OpaquePointer?, _ sql: String) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    static func meta(_ db: OpaquePointer?, _ key: String) -> String? {
        guard key.allSatisfy({ $0.isLetter || $0 == "_" }) else { return nil }
        return strings(db, "SELECT value FROM meta WHERE key = '\(key)'").first
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw)
    }
}

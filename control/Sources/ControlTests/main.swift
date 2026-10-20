import ControlCore
import Foundation

// LumiereControl's tests. An executable rather than XCTest: this machine has
// Command Line Tools and no Xcode. `swift run ControlTests`; exits non-zero
// on any failure.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "  ✓ \(what)" : "  ✗ \(what)")
    if !ok { failures += 1 }
}

func folder() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("control-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, _ url: URL) { try! text.write(to: url, atomically: true, encoding: .utf8) }
func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

print("Backup swap")
do {
    let dir = folder()
    let live = dir.appendingPathComponent("library.db")
    write("today", live)
    write("today-wal", dir.appendingPathComponent("library.db-wal"))
    write("today-shm", dir.appendingPathComponent("library.db-shm"))
    let backup = dir.appendingPathComponent("library-20260920.db")
    write("sunday", backup)

    try BackupSwap.swap(in: backup, dataDir: dir)

    expect(read(live) == "sunday", "the backup is now the live database")
    expect(read(backup) == "sunday", "the backup itself is untouched")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    let aside = names.filter { $0.hasPrefix("library.db.before-restore-") }
    expect(aside.count == 3, "today's database, WAL and SHM are set aside, not deleted")
    expect(aside.contains { !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm")
                            && read(dir.appendingPathComponent($0)) == "today" },
           "the set-aside database holds today's data")
    expect(!names.contains("library.db-wal"), "no stale WAL is left to replay into the copy")
}

do {
    let dir = folder()
    let backup = dir.appendingPathComponent("library-1.db")
    write("only", backup)
    try BackupSwap.swap(in: backup, dataDir: dir)
    expect(read(dir.appendingPathComponent("library.db")) == "only", "restores with no live database at all")
}

do {
    let dir = folder()
    write("today", dir.appendingPathComponent("library.db"))
    let missing = dir.appendingPathComponent("gone.db")
    var threw = false
    do { try BackupSwap.swap(in: missing, dataDir: dir) } catch { threw = true }
    expect(threw, "a missing backup is an error")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    expect(names.contains("library.db") && read(dir.appendingPathComponent("library.db")) == "today",
           "a failed restore leaves today's database exactly where it was")
}

print("Old copies")
do {
    for (name, want) in [
        ("library.db.pre-onefile.20260922-194836", true),
        ("library.db.pre-scanner", true),
        ("library.db.before-restore-20260923T101500Z", true),
        ("library.db.before-restore-20260923T101500Z-wal", true),
        ("library.db", false), ("library.db-wal", false), ("library.db-shm", false),
        ("backups", false), ("tmdb.token", false), ("library.dbx.pre-x", false),
    ] {
        expect(OldCopies.isOldCopy(name) == want, "\(name) is \(want ? "" : "not ")an old copy")
    }
    let dir = folder()
    write("live", dir.appendingPathComponent("library.db"))
    write("old", dir.appendingPathComponent("library.db.pre-test"))
    let listed = OldCopies.list(in: dir)
    expect(listed.count == 1 && listed[0].bytes == 3, "lists the old copy with its size, not the live one")
}

print("Library stats")
do {
    let dir = folder()
    let db = dir.appendingPathComponent("library.db")
    // Built with the sqlite3 tool: the same engine the server writes with, and
    // no test-only code path in ControlCore for making a database.
    let now = Date()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let recent = iso.string(from: now.addingTimeInterval(-60))
    let old = iso.string(from: now.addingTimeInterval(-3600))
    let sql = """
    CREATE TABLE item (id TEXT PRIMARY KEY, type TEXT, library_id TEXT, extra_type TEXT);
    CREATE TABLE user_data (item_id TEXT, played INTEGER, position_ticks INTEGER, source TEXT, updated_at TEXT);
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE library_folder (view_id TEXT, folder_id TEXT);
    INSERT INTO library_folder VALUES ('aa11', 'f00d01'), ('bb22', 'f00d02');
    INSERT INTO meta VALUES ('private_libraries', 'bb22'), ('auto_scan_at', '2026-10-13T17:15:28Z'),
        ('server_settings', '{"ListensOnNetwork": true, "ScanEveryHours": 6}');
    INSERT INTO item VALUES ('m1','Movie','f00d01',NULL), ('m2','Movie','f00d01',NULL),
        ('x1','Movie','f00d01','Trailer'), ('s1','Series','f00d01',NULL),
        ('e1','Episode','f00d01',NULL), ('e2','Episode','f00d01',NULL),
        ('p1','Movie','f00d02',NULL), ('p2','Episode','f00d02',NULL),
        ('a1','Audio','f00d01',NULL);
    INSERT INTO user_data VALUES ('m1',1,0,'jellyfin','\(old)'), ('e1',0,500,'jellyfin','\(old)'),
        ('p1',1,0,'jellyfin','\(old)'), ('p2',0,900,'jellyfin','\(old)');
    """
    let make = Process()
    make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    make.arguments = [db.path, sql]
    try make.run(); make.waitUntilExit()

    guard let s = LibraryStats.read(database: db, now: now) else {
        expect(false, "an existing database can be read"); exit(1)
    }
    expect(s.films == 2, "films are counted, extras are not (\(s.films))")
    expect(s.episodes == 2 && s.shows == 1 && s.tracks == 1, "episodes, shows and tracks")
    expect(s.watched == 1, "a watched film in a private library is not counted (\(s.watched))")
    expect(s.inProgress == 1, "nor is a half-watched episode in one (\(s.inProgress))")
    expect(!s.isPlaying, "nothing local in the last three minutes is not playing")
    expect(s.lastScan != nil, "the last scheduled scan is read")
    expect(s.listensOnNetwork, "home-network sharing is read from the server's own settings")

    let poke = Process()
    poke.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    poke.arguments = [db.path, "INSERT INTO user_data VALUES ('e2',0,100,'local','\(recent)');"]
    try poke.run(); poke.waitUntilExit()
    expect(LibraryStats.read(database: db, now: now)?.isPlaying == true,
           "a local report a minute ago is playing")

    expect(LibraryStats.read(database: dir.appendingPathComponent("none.db")) == nil,
           "a missing database is nil, not an empty library")
}

print(failures == 0 ? "All passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

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

print(failures == 0 ? "All passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

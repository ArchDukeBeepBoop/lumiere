import Foundation
import TestKit
import LumiereKit

/// What a tile from a folder library is called.
///
/// Pinned because the rule escaped three times. It began as a `titleOverride` the
/// folder browser passed by hand, so the same file was its filename inside the
/// browser and its metadata name on the home screen; moving it into one helper fixed
/// the cards but not the backdrops, which built their titles separately. Every one of
/// those was a surface that had to remember, and the point of the helper is that a
/// surface should not have to.
@MainActor
func registerFolderTitleTests(_ t: TestRunner) async {

    func item(
        _ name: String,
        libraryId: String?,
        path: String?,
        year: Int? = nil
    ) throws -> ItemRecord {
        var json: [String: Any] = ["Id": "i1", "Name": name, "Type": "Movie"]
        if let path { json["Path"] = path }
        if let year { json["ProductionYear"] = year }
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        var record = ItemRecord(from: decoded, serverId: "s1", syncedAt: Date())
        record.libraryId = libraryId
        return record
    }

    func entry(_ record: ItemRecord) -> LibraryEntry {
        LibraryEntry(item: record, userData: nil)
    }

    let folders: Set<String> = ["folderLib"]

    t.suite("Folder titles") { t in

        t.test("a folder library shows the filename, not the tidied name") {
            // The real shape on this library: Jellyfin strips the release group and
            // truncates, and those are the characters that tell two rips apart.
            let record = try item(
                "Granddaughter",
                libraryId: "folderLib",
                path: "/Volumes/M/3D/Clips/[Group] Granddaughter [Akira].mp4"
            )
            t.expectEqual(
                FolderTitle.title(
                    for: entry(record), style: .metadataTitle, folderLibraryIds: folders
                ),
                "[Group] Granddaughter [Akira]"
            )
        }

        t.test("the extension is dropped from the tile") {
            // Every tile in such a library ends in the same three letters; it is a
            // column of repeated text stealing room from the part that differs.
            let record = try item(
                "Clip", libraryId: "folderLib", path: "/v/My Videos/Clip.mkv"
            )
            let title = FolderTitle.title(
                for: entry(record), style: .metadataTitle, folderLibraryIds: folders
            )
            t.expect(!title.hasSuffix(".mkv"), "got \(title)")
        }

        t.test("a scraped library keeps its metadata name") {
            let record = try item(
                "The Dark Knight",
                libraryId: "movies",
                path: "/films/the.dark.knight.2008.1080p.mkv",
                year: 2008
            )
            t.expectEqual(
                FolderTitle.title(
                    for: entry(record), style: .metadataTitle, folderLibraryIds: folders
                ),
                "The Dark Knight"
            )
        }

        t.test("a scraped library still honours the title-style setting") {
            // The folder rule must not swallow the Settings preference for everything
            // else — that would be one fix breaking another.
            let record = try item(
                "The Dark Knight", libraryId: "movies",
                path: "/films/the.dark.knight.2008.1080p.mkv", year: 2008
            )
            t.expectEqual(
                FolderTitle.title(
                    for: entry(record), style: .originalFilename, folderLibraryIds: folders
                ),
                "the.dark.knight.2008.1080p.mkv"
            )
        }

        t.test("an item with no library falls back rather than blanking") {
            let record = try item("Loose", libraryId: nil, path: "/x/Loose.mp4")
            t.expectEqual(
                FolderTitle.title(
                    for: entry(record), style: .metadataTitle, folderLibraryIds: folders
                ),
                "Loose"
            )
        }

        t.test("a folder-library item with no path does not render empty") {
            // Rows synced before the path column existed. A blank title is never the
            // right answer.
            let record = try item("Old Row", libraryId: "folderLib", path: nil)
            let title = FolderTitle.title(
                for: entry(record), style: .metadataTitle, folderLibraryIds: folders
            )
            t.expect(!title.isEmpty, "got an empty title")
        }
    }
}

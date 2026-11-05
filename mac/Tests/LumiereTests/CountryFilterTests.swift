import Foundation
import TestKit
import LumiereKit
import GRDB

/// The country filter: codes from the server's ProductionLocations land in
/// the cache, the menu lists only what a library holds, and the filter
/// matches whole codes — a co-production under each of its countries.
@MainActor
func registerCountryFilterTests(_ t: TestRunner) async {
    func film(_ database: LibraryDatabase, _ id: String, _ countries: [String]) throws {
        let json: [String: Any] = ["Id": id, "Name": id, "Type": "Movie", "ProductionLocations": countries]
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: json))
        var record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
        record.libraryId = "lib"
        try database.writer.write { db in try record.insert(db) }
    }

    await t.suite("Country filter") { t in
        await t.test("codes are cached, tallied and matched whole") {
            let (repository, database) = try makeRepository()
            try film(database, "spirited", ["JP"])
            try film(database, "parasite", ["KR"])
            try film(database, "coproduction", ["JP", "US"])
            try film(database, "unknown", [])

            let tallies = try await repository.countryTallies(libraryId: "lib")
            t.expectEqual(tallies.map(\.name), ["JP", "KR", "US"])
            t.expectEqual(tallies.first?.count, 2)

            let japan = try await repository.count(types: [.movie], libraryId: "lib", country: "JP")
            t.expectEqual(japan, 2)
            let us = try await repository.count(types: [.movie], libraryId: "lib", country: "US")
            t.expectEqual(us, 1)
            // A code is not a substring match: "J" finds nothing.
            let partial = try await repository.count(types: [.movie], libraryId: "lib", country: "J")
            t.expectEqual(partial, 0)
        }
        t.test("named in the viewer's language") {
            t.expectEqual(LibraryRepository.countryName("JP", locale: Locale(identifier: "en_US")), "Japan")
            t.expectEqual(LibraryRepository.countryName("JP", locale: Locale(identifier: "fr_FR")), "Japon")
        }
    }
}

@MainActor
func registerTitleOrderTests(_ t: TestRunner) {
    func show() -> ItemRecord {
        var item = ItemRecord(id: "s", serverId: "s1", type: "Series", name: "Elf Village",
                              sortName: "elf village", searchKey: "elf village", isFolder: true, syncedAt: Date())
        item.path = "/Volumes/Media/Shows/Elf no Mori [2019]"
        item.originalTitle = "エルフの森"
        item.romajiTitle = "Elf no Mori"
        return item
    }
    t.suite("Title order per library") { t in
        t.test("folder name first, romaji under it") {
            t.expectEqual(LibraryTitleOrder.folderThenRomaji.primary(for: show()), "Elf no Mori [2019]")
            t.expectEqual(LibraryTitleOrder.folderThenRomaji.secondary(for: show()), "Elf no Mori")
        }
        t.test("romaji first, the title under it") {
            t.expectEqual(LibraryTitleOrder.romajiThenTitle.primary(for: show()), "Elf no Mori")
            t.expectEqual(LibraryTitleOrder.romajiThenTitle.secondary(for: show()), "Elf Village")
        }
        t.test("the standard order changes nothing, and episodes keep their names") {
            t.expectEqual(LibraryTitleOrder.standard.primary(for: show()), nil)
            var episode = show()
            episode.type = "Episode"
            t.expectEqual(LibraryTitleOrder.folder.primary(for: episode), nil)
        }
        t.test("a film goes by its file name") {
            var film = show()
            film.type = "Movie"
            film.isFolder = false
            film.path = "/m/Some Film (1999).mkv"
            t.expectEqual(LibraryTitleOrder.folder.primary(for: film), "Some Film (1999)")
        }
    }
}

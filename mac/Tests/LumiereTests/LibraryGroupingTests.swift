import Foundation
import TestKit
import LumiereKit

/// Splitting a gathered list back into the libraries it came from.
@MainActor
func registerLibraryGroupingTests(_ t: TestRunner) {

    func entry(_ id: String, library: String?) -> LibraryEntry {
        let json: [String: Any] = ["Id": id, "Name": "Item \(id)", "Type": "Movie"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        var record = ItemRecord(from: decoded, serverId: "s1", syncedAt: Date())
        record.libraryId = library
        return LibraryEntry(item: record, userData: nil)
    }

    let order = [(id: "films", name: "Movies"), (id: "anime", name: "Anime")]

    t.suite("Library grouping") { t in

        t.test("sections follow the sidebar's order, not the rows'") {
            // The rows arrive anime-first; the sidebar says films come first. A grid
            // that disagrees with the sidebar about order looks shuffled.
            let sections = LibraryGrouping.sections(
                entries: [entry("a", library: "anime"), entry("f", library: "films")],
                order: order
            )
            t.expectEqual(sections.map(\.name), ["Movies", "Anime"])
        }

        t.test("order within a section is the order it was given") {
            // Whatever the query sorted by — newest first, usually — survives.
            let sections = LibraryGrouping.sections(
                entries: [
                    entry("1", library: "films"),
                    entry("2", library: "films"),
                    entry("3", library: "films"),
                ],
                order: order
            )
            t.expectEqual(sections.first?.entries.map(\.id), ["1", "2", "3"])
        }

        t.test("a library with nothing in it gets no heading") {
            let sections = LibraryGrouping.sections(
                entries: [entry("f", library: "films")], order: order
            )
            t.expectEqual(sections.count, 1)
        }

        t.test("rows with no library are kept, at the end") {
            // An item the sync never stamped. Dropping it would be a title that
            // exists in the library and cannot be found through a genre.
            let sections = LibraryGrouping.sections(
                entries: [entry("x", library: nil), entry("f", library: "films")],
                order: order
            )
            t.expectEqual(sections.map(\.name), ["Movies", "Elsewhere"])
            t.expectEqual(sections.last?.entries.map(\.id), ["x"])
        }

        t.test("a library missing from the order still appears") {
            // A library hidden from the sidebar, or one added since. Its rows are
            // shown rather than silently discarded.
            let sections = LibraryGrouping.sections(
                entries: [entry("h", library: "hidden")], order: order
            )
            t.expectEqual(sections.count, 1)
            t.expectEqual(sections.first?.entries.map(\.id), ["h"])
        }

        t.test("empty in, empty out") {
            t.expectEqual(LibraryGrouping.sections(entries: [], order: order).count, 0)
        }
    }
}

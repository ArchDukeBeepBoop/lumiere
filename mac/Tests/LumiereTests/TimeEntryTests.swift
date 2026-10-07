import Foundation
import TestKit
import LumiereKit

/// Jump to Time's reading of what was typed.
@MainActor
func registerTimeEntryTests(_ t: TestRunner) async {
    t.suite("Jump to time") { t in
        t.test("timecodes, units, minutes and percentages all land") {
            let hour = 3600.0 * 2
            t.expectEqual(TimeEntry.seconds(from: "1:23:45", duration: hour), 5025)
            t.expectEqual(TimeEntry.seconds(from: "23:45", duration: hour), 1425)
            t.expectEqual(TimeEntry.seconds(from: "45", duration: hour), 2700)
            t.expectEqual(TimeEntry.seconds(from: "1h20m", duration: hour), 4800)
            t.expectEqual(TimeEntry.seconds(from: "90s", duration: hour), 90)
            t.expectEqual(TimeEntry.seconds(from: "50%", duration: hour), 3600)
        }
        t.test("nonsense is refused, and a time past the end stops short of it") {
            t.expect(TimeEntry.seconds(from: "soon", duration: 100) == nil)
            t.expect(TimeEntry.seconds(from: "1:2:3:4", duration: 100) == nil)
            t.expect(TimeEntry.seconds(from: "", duration: 100) == nil)
            t.expect(TimeEntry.seconds(from: "20m5", duration: 100) == nil)
            t.expectEqual(TimeEntry.seconds(from: "3:00:00", duration: 100), 99)
        }
    }
}

@MainActor
func registerCollectionSearchTests(_ t: TestRunner) async {
    t.suite("Demo Library Health") { t in
        t.test("the walkthrough's report decodes, with every fix represented") {
            let kinds = Set(LibraryHealthIssue.demo.map(\.kind))
            t.expectEqual(kinds.count, 6)
            t.expect(kinds.contains("DuplicateCollections") && kinds.contains("MismatchedShows"))
            t.expectEqual(LibraryHealthIssue.demo.first { $0.kind == "UnnamedEpisodes" }?.changeSinceYesterday,
                          "2 new since yesterday")
        }
    }
    t.suite("Collections in search") { t in
        t.test("a collection outranks the film it is named after") {
            let term = "alien"
            let collection = SearchRanking.score(
                name: SearchRanking.bareCollectionName("Alien Collection"), term: term, kindWeight: 4)
            let film = SearchRanking.score(name: "Alien", term: term, kindWeight: 3)
            t.expect(collection > film)
        }
    }
}

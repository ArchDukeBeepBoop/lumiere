import Foundation
import TestKit
import LumiereKit
import GRDB

@MainActor
func registerTitleSortTests(_ t: TestRunner) {
    t.suite("Title sort follows the library's title order") { t in
        func sorted(_ order: LibraryTitleOrder) throws -> [String] {
            let db = try DatabaseQueue()
            return try db.write { db in
                try db.execute(sql: """
                    CREATE TABLE item (id TEXT, type TEXT, name TEXT, sortName TEXT, path TEXT, romajiTitle TEXT);
                    INSERT INTO item VALUES
                      ('1', 'Series', 'Mrs. Teacup', 'mrs. teacup', '/m/Library/Careful Advice', 'Zettai Teacup'),
                      ('2', 'Series', 'The Copper Tray', 'copper tray', '/m/Library/Copper Tray', NULL),
                      ('3', 'Series', 'Blue Saga', 'blue saga', '', 'Blue Saga'),
                      ('4', 'Movie', 'Aria', 'aria', '/m/Films/Zeta.mkv', 'Aaa');
                    """)
                return try String.fetchAll(db, sql: "SELECT id FROM item ORDER BY \(order.titleSortSQL), item.sortName")
            }
        }
        t.test("standard sorts by the title") {
            t.expectEqual(try sorted(.standard), ["4", "3", "2", "1"])
        }
        t.test("folder name first sorts by the folder, then romaji, then title") {
            // Careful Advice, Copper Tray, then Blue Saga by romaji, Zeta.mkv by its file.
            t.expectEqual(try sorted(.folderThenRomaji), ["3", "1", "2", "4"])
        }
        t.test("romaji first sorts by romaji, falling back to the title") {
            t.expectEqual(try sorted(.romajiThenTitle), ["4", "3", "2", "1"])
        }
    }
}

@MainActor
func registerFranchiseNamingTests(_ t: TestRunner) {
    t.test("franchise naming follows each library's title order") {
        let defaults = UserDefaults(suiteName: "franchise-naming-test")!
        defaults.removePersistentDomain(forName: "franchise-naming-test")
        LibraryTitleOrder.set(.folderThenRomaji, for: "adult", in: defaults)
        LibraryTitleOrder.set(.romajiThenTitle, for: "anime", in: defaults)
        LibraryTitleOrder.set(.standard, for: "films", in: defaults)
        t.expectEqual(LibraryTitleOrder.franchiseNaming(in: defaults), ["adult": "folder", "anime": "romaji"])
    }
}

@MainActor
func registerAnimeSeasonTests(_ t: TestRunner) {
    t.suite("Anime seasons") { t in
        t.test("a month falls in its season") {
            t.expectEqual(AnimeSeason(year: 2023, month: 10)?.title, "Fall 2023")
            t.expectEqual(AnimeSeason(year: 1991, month: 7)?.title, "Summer 1991")
            t.expectEqual(AnimeSeason(year: 2024, month: 1)?.quarter, .winter)
            t.expectEqual(AnimeSeason(year: 2024, month: 13), nil)
        }
        t.test("an id round-trips, and the season's dates bound it") {
            let fall = AnimeSeason(year: 2024, quarter: .fall)
            t.expectEqual(AnimeSeason(id: fall.id), fall)
            t.expectEqual(fall.arguments, ["2024-10-01", "2025-01-01"])
            t.expectEqual(AnimeSeason(year: 2024, quarter: .spring).arguments, ["2024-04-01", "2024-07-01"])
        }
        t.test("newer seasons sort first") {
            let list = [AnimeSeason(year: 2023, quarter: .fall), AnimeSeason(year: 2024, quarter: .winter)].sorted(by: >)
            t.expectEqual(list.first?.title, "Winter 2024")
        }
    }
}

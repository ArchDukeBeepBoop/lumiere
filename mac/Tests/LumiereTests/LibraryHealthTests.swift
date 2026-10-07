import Foundation
import TestKit
import LumiereKit

@MainActor
func registerLibraryHealthTests(_ t: TestRunner) {
    t.suite("Library health news") { t in
        t.test("only a count that grew is news") {
            let json = """
                {"Issues":[{"Kind":"Unreadable","Count":5,"Samples":[]},
                           {"Kind":"UnnamedEpisodes","Count":200,"Samples":[]},
                           {"Kind":"EmptySeries","Count":1,"Samples":[]}]}
                """
            struct R: Decodable { let Issues: [LibraryHealthIssue] }
            let issues = try JSONDecoder().decode(R.self, from: Data(json.utf8)).Issues
            let grown = LibraryHealthIssue.grown(
                issues, since: ["Unreadable": 4, "UnnamedEpisodes": 369])
            t.expectEqual(grown, ["Unreadable", "EmptySeries"])
        }

        t.test("an old Lumiere server is named; Jellyfin is not") {
            func info(_ json: String) throws -> PublicSystemInfo {
                try JSONDecoder().decode(PublicSystemInfo.self, from: Data(json.utf8))
            }
            t.expect(ServerCompatibility.warning(for: try info(#"{"Id":"a","LumiereApi":5}"#)) != nil)
            t.expect(ServerCompatibility.warning(for: try info(#"{"Id":"a","LumiereApi":6}"#)) == nil)
            t.expect(ServerCompatibility.warning(for: try info(#"{"Id":"a","Version":"10.9"}"#)) == nil)
        }

        t.test("the subtitle queue's status decodes") {
            let json = #"{"Waiting":20,"Done":3,"Failed":1,"DoneToday":3,"DailyLimit":5}"#
            let status = try JSONDecoder().decode(SubtitleQueueStatus.self, from: Data(json.utf8))
            t.expectEqual(status.waiting, 20)
            t.expectEqual(status.dailyLimit, 5)
            let withShows = #"{"Waiting":1,"Done":2,"Failed":0,"DoneToday":0,"DailyLimit":5,"Shows":[{"Series":"InuYasha","Waiting":1,"Done":2,"Failed":0}]}"#
            let byShow = try JSONDecoder().decode(SubtitleQueueStatus.self, from: Data(withShows.utf8))
            t.expectEqual(byShow.shows?.first?.series, "InuYasha")
            let shows = byShow.shows ?? []
            t.expectEqual(SubtitleArrivals.message(for: shows, seen: [:]),
                          "2 new subtitles ready for InuYasha.")
            t.expect(SubtitleArrivals.message(for: shows, seen: ["InuYasha": 2]) == nil)
        }

        t.test("the app never needs a server newer than the one beside it") {
            // The two levels are bumped together by hand, and forgetting one half
            // ships an app that calls every current server old. Read from the
            // server's source, which sits beside this repository.
            let system = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("LumiereServer/internal/api/system.go")
            guard let text = try? String(contentsOf: system, encoding: .utf8) else { return }
            let level = text.split(separator: "\n")
                .first { $0.hasPrefix("const APILevel = ") }
                .flatMap { Int($0.split(separator: "=").last!.trimmingCharacters(in: .whitespaces)) }
            t.expectEqual(level, ServerCompatibility.requiredLevel)
        }

        t.test("an episode-order answer from the server decodes") {
            let json = """
                {"Groups":[{"id":"5b","name":"DVD Order","description":"","type":3,
                            "group_count":3,"episode_count":91}],"Selected":""}
                """
            let choice = try JSONDecoder().decode(EpisodeGroupChoice.self, from: Data(json.utf8))
            t.expectEqual(choice.groups.first?.kindName, "DVD")
            t.expectEqual(choice.groups.first?.episodeCount, 91)
            t.expectEqual(choice.selected, "")
            let withFits = #"{"Groups":[],"Selected":"","Fits":{"a":0.2,"b":0.9}}"#
            let fitted = try JSONDecoder().decode(EpisodeGroupChoice.self, from: Data(withFits.utf8))
            t.expectEqual(fitted.bestFit, "b")
        }
    }
}

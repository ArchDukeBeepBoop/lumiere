import Foundation
import TestKit
import LumiereKit

@MainActor
func registerFetchedSubtitleTests(_ t: TestRunner) {
    t.suite("Fetched subtitles") { t in
        func stream(_ json: [String: Any]) -> MediaStream {
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! JellyfinClient.decoder.decode(MediaStream.self, from: data)
        }
        let embedded = stream(["Index": 2, "Type": "Subtitle", "Language": "eng", "Title": "Signs"])
        let fetched = stream(["Index": 1000, "Type": "Subtitle", "Language": "en",
                              "Title": "OpenSubtitles", "IsExternal": true])
        let fetchedJa = stream(["Index": 1001, "Type": "Subtitle", "Language": "ja",
                                "Title": "OpenSubtitles", "IsExternal": true])

        t.test("a subtitle fetched in the search language is chosen") {
            t.expectEqual(PreferredTracks.fetchedSubtitle(in: [embedded, fetchedJa, fetched], language: "en"), 1000)
            t.expectEqual(PreferredTracks.fetchedSubtitle(in: [embedded, fetchedJa, fetched], language: "ja, en"), 1001)
        }
        t.test("a file's own track is never mistaken for a fetched one") {
            t.expect(PreferredTracks.fetchedSubtitle(in: [embedded], language: "en") == nil)
        }
    }
}

import Foundation
import TestKit
import LumiereKit

@MainActor
func registerExtrasGroupingTests(_ t: TestRunner) async {
    func extra(_ name: String, _ type: String = "Clip") -> LibraryEntry {
        let data = try! JSONSerialization.data(withJSONObject: ["Id": name, "Name": name, "Type": "Video", "ExtraType": type])
        let item = ItemRecord(from: try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data),
                              serverId: "s", syncedAt: Date())
        return LibraryEntry(item: item, userData: nil)
    }
    t.suite("Extras") { t in
        t.test("an anime's extras group into openings, endings and specials, named plainly") {
            let show = "ACCA: 13-Territory Inspection Dept."
            let entries = ["ACCA 13-Territory Inspection Dept. - SP02", "ACCA 13-Territory Inspection Dept. - Opening",
                           "ACCA 13-Territory Inspection Dept. - SP01", "ACCA 13-Territory Inspection Dept. - Ending"].map { extra($0) }
            let groups = ExtrasGrouping.groups(entries, showName: show)
            t.expectEqual(groups.map(\.title), ["Openings", "Endings", "Specials"])
            t.expectEqual(groups[2].entries.map { ExtrasGrouping.name(of: $0, showName: show) }, ["Special 1", "Special 2"])
            t.expectEqual(ExtrasGrouping.name(of: entries[1], showName: show), "Opening")
        }
        t.test("a film's trailers and featurettes stay apart") {
            let groups = ExtrasGrouping.groups([extra("Teaser", "Trailer"), extra("Making Of", "Featurette")], showName: "Alien")
            t.expectEqual(groups.map(\.title), ["Trailers", "Featurettes"])
        }
    }
}

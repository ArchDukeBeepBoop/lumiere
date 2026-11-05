import Foundation
import TestKit
import LumiereKit

private func item(_ json: [String: Any]) throws -> JellyfinItem {
    try JSONDecoder().decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: json))
}

@MainActor
func registerMusicCardTests(_ t: TestRunner) {
    t.suite("Music cards and chosen orders") { t in
        t.test("an artist with a photo is pictured by it") {
            let card = MusicCard(try item(["Id": "a1", "Name": "Fleetwood Mac", "Type": "MusicArtist",
                                           "ImageTags": ["Primary": "tag1"], "AlbumId": "al9"]))
            t.expectEqual(card.pictureId, "a1")
            t.expectEqual(card.pictureTag, "tag1")
        }
        t.test("an artist or a genre without one is pictured by its album") {
            let card = MusicCard(try item(["Id": "Rock", "Name": "Rock", "Type": "MusicGenre", "AlbumId": "al9"]))
            t.expectEqual(card.pictureId, "al9")
            t.expectEqual(card.pictureTag, nil)
        }
        t.test("a collection's order is the one chosen on it, else the default") {
            let key = CollectionOrder.storageKey("box-test")
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            t.expectEqual(CollectionOrder.chosen(for: "box-test"),
                          CollectionOrder(rawValue: Preference.collectionDefaultOrder.value) ?? .releaseDate)
            UserDefaults.standard.set(CollectionOrder.personal.rawValue, forKey: key)
            t.expectEqual(CollectionOrder.chosen(for: "box-test"), .personal)
        }
    }
}

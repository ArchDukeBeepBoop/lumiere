import Foundation
import TestKit
import LumiereKit

/// The line of facts under a title, chosen by what the title is.
@MainActor
func registerMetadataLineTests(_ t: TestRunner) {

    func entry(
        type: String,
        year: Int? = nil,
        runtime: Double? = nil,
        seasons: Int? = nil,
        unwatched: Int? = nil
    ) throws -> LibraryEntry {
        var object: [String: Any] = ["Id": "1", "Name": "A Title", "Type": type]
        if let year { object["ProductionYear"] = year }
        if let runtime { object["RunTimeTicks"] = Int(runtime * 10_000_000) }
        if let seasons { object["ChildCount"] = seasons }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        let record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
        guard let unwatched else { return LibraryEntry(item: record, userData: nil) }
        var userData = UserDataRecord(itemId: "1", from: nil, updatedAt: Date())
        userData.unplayedItemCount = unwatched
        return LibraryEntry(item: record, userData: userData)
    }

    t.suite("Metadata lines") { t in

        t.test("a film says year, runtime and who made it") {
            let film = try entry(type: "Movie", year: 1982, runtime: 7020)
            t.expectEqual(
                MetadataLine.line(for: film, kind: .film, director: "Ridley Scott"),
                "1982 · 1 hr 57 · Ridley Scott"
            )
        }

        t.test("a series says how much is left, which is the fact that changes") {
            let series = try entry(type: "Series", year: 2008, seasons: 5, unwatched: 12)
            t.expectEqual(
                MetadataLine.line(for: series, kind: .series),
                "2008 · 5 seasons · 12 unwatched"
            )
        }

        t.test("a finished series does not claim unwatched episodes") {
            let done = try entry(type: "Series", year: 2008, seasons: 5, unwatched: 0)
            t.expectEqual(MetadataLine.line(for: done, kind: .series), "2008 · 5 seasons")
        }

        t.test("an anime leads with the studio") {
            // In an anime library the studio is most of the judgement, and the
            // old line never showed it at all.
            let show = try entry(type: "Series", year: 2019, seasons: 2, unwatched: 6)
            t.expectEqual(
                MetadataLine.line(for: show, kind: .anime, studio: "Bones"),
                "Bones · 2019 · 2 seasons · 6 unwatched"
            )
        }

        t.test("an anime film reads like a film, with the studio in front") {
            let film = try entry(type: "Movie", year: 2016, runtime: 6360)
            t.expectEqual(
                MetadataLine.line(for: film, kind: .anime, studio: "CoMix Wave"),
                "CoMix Wave · 2016 · 1 hr 46"
            )
        }

        t.test("the library decides anime, not the item") {
            let series = try entry(type: "Series")
            t.expectEqual(MetadataLine.kind(for: series.item, isAnimeLibrary: true), .anime)
            t.expectEqual(MetadataLine.kind(for: series.item, isAnimeLibrary: false), .series)
            let film = try entry(type: "Movie")
            t.expectEqual(MetadataLine.kind(for: film.item, isAnimeLibrary: false), .film)
        }

        t.test("nothing known draws nothing rather than a bare separator") {
            let bare = try entry(type: "Movie")
            t.expectNil(MetadataLine.line(for: bare, kind: .film))
        }

        t.test("runtimes read as time, not as arithmetic") {
            t.expectEqual(MetadataLine.runtimeText(2880), "48 min")
            t.expectEqual(MetadataLine.runtimeText(7200), "2 hr")
            t.expectEqual(MetadataLine.runtimeText(7020), "1 hr 57")
            // Below a minute is not a runtime worth printing.
            t.expectNil(MetadataLine.runtimeText(30))
            t.expectNil(MetadataLine.runtimeText(nil))
        }
    }

    t.suite("Card metadata lines") { t in

        t.test("an anime card leads with its studio") {
            let series = try entry(type: "Series", year: 2019, seasons: 2, unwatched: 6)
            t.expectEqual(
                MetadataLine.cardLine(for: series, kind: .anime, studio: "Bones"),
                "Bones · 6 unwatched"
            )
        }

        t.test("a series card says what is left, not what year it began") {
            let series = try entry(type: "Series", year: 2008, seasons: 5, unwatched: 12)
            t.expectEqual(
                MetadataLine.cardLine(for: series, kind: .series),
                "5 seasons · 12 unwatched"
            )
        }

        t.test("a film card says year and runtime") {
            let film = try entry(type: "Movie", year: 1982, runtime: 7020)
            t.expectEqual(
                MetadataLine.cardLine(for: film, kind: .film),
                "1982 · 1 hr 57"
            )
        }

        t.test("a card never runs past two facts") {
            let series = try entry(type: "Series", year: 2008, seasons: 5, unwatched: 12)
            for kind in [MetadataLine.Kind.film, .series, .anime] {
                let line = MetadataLine.cardLine(for: series, kind: kind, studio: "Bones")
                t.expectEqual((line ?? "").components(separatedBy: " · ").count <= 2, true)
            }
        }
    }

    t.suite("Ratings") { t in

        t.test("a rating is one figure, never a decimal") {
            t.expectEqual(Rating.text(8.6), "9")
            t.expectEqual(Rating.text(10.0), "10")
            t.expectEqual(Rating.text(7.4), "7")
        }

        t.test("no rating draws nothing rather than a zero") {
            t.expectEqual(Rating.text(nil), nil)
            t.expectEqual(Rating.text(0), nil)
            t.expectEqual(Rating.starred(nil), nil)
        }

        t.test("the starred form carries the same figure") {
            t.expectEqual(Rating.starred(8.6), "★ 9")
        }
    }
}

/// The type scale, as a set of relationships rather than a list of numbers.
@MainActor
func registerTypeScaleTests(_ t: TestRunner) {

    t.suite("Type scale") { t in

        t.test("body, card title and caption are actually different sizes") {
            // The finding: 13 / 12 / 11 is three levels inside two points, which
            // reads as one level. A step of at least two separates them.
            t.expect(TypeScale.body - TypeScale.cardTitle >= 2,
                     "body \(TypeScale.body) vs card \(TypeScale.cardTitle)")
            t.expect(TypeScale.body - TypeScale.caption >= 3,
                     "body \(TypeScale.body) vs caption \(TypeScale.caption)")
        }

        t.test("a heading announces itself against the text under it") {
            t.expect(TypeScale.sectionHeader - TypeScale.body >= 3,
                     "header \(TypeScale.sectionHeader) vs body \(TypeScale.body)")
        }

        t.test("the scale climbs without a flat step") {
            // Every level at least two points from its neighbour, all the way up.
            let scale = [
                TypeScale.caption, TypeScale.cardTitle, TypeScale.body,
                TypeScale.sectionHeader, TypeScale.shelfHeader,
                TypeScale.title, TypeScale.hero,
            ]
            for (smaller, larger) in zip(scale, scale.dropFirst()) {
                t.expect(larger - smaller >= 2, "\(smaller) → \(larger) is not a step")
            }
        }
    }
}

/// Arrow-key movement over a wall of tiles.
@MainActor
func registerGridKeyboardTests(_ t: TestRunner) {

    let ids = (1...10).map { "id\($0)" }

    t.suite("Grid keyboard") { t in

        t.test("right and left step one tile") {
            let k = GridKeyboard()
            k.columns = 3
            k.begin(in: ids)
            t.expectEqual(k.move(.right, in: ids), "id2")
            t.expectEqual(k.move(.left, in: ids), "id1")
        }

        t.test("down moves a whole row, not a tile") {
            let k = GridKeyboard()
            k.columns = 3
            k.begin(in: ids)
            t.expectEqual(k.move(.down, in: ids), "id4")
            t.expectEqual(k.move(.up, in: ids), "id1")
        }

        t.test("movement clamps rather than wrapping") {
            let k = GridKeyboard()
            k.columns = 3
            k.begin(in: ids)
            // Left from the first tile stays put: wrapping to the end of a wall
            // of hundreds sends you somewhere nobody asked to go.
            t.expectNil(k.move(.left, in: ids))
            t.expectEqual(k.focusedId, "id1")
        }

        t.test("down from the last ragged row lands on the last tile") {
            let k = GridKeyboard()
            k.columns = 3
            k.begin(in: ids)
            for _ in 0..<4 { _ = k.move(.down, in: ids) }
            t.expectEqual(k.focusedId, "id10")
        }

        t.test("an empty wall cannot be navigated into") {
            let k = GridKeyboard()
            t.expectNil(k.move(.right, in: []))
            t.expectNil(k.focusedId)
        }

        t.test("columns are counted from the room and the tile size") {
            t.expectEqual(
                GridKeyboard.columnCount(width: 1000, tileWidth: 180, spacing: 20), 5
            )
            // Never zero, whatever the arithmetic says.
            t.expectEqual(
                GridKeyboard.columnCount(width: 0, tileWidth: 180, spacing: 20), 1
            )
        }
    }
}

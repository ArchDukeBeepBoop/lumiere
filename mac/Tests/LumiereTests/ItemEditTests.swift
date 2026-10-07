import Foundation
import TestKit
import LumiereKit

/// Building the payload that edits an item without destroying it.
///
/// The stakes here are asymmetric: the update endpoint replaces the whole item, so
/// a payload that drops a key clears that field on the server for every client. Most
/// of these tests are about what the edit leaves *alone*.
@MainActor
func registerItemEditTests(_ t: TestRunner) {

    /// A stand-in for the parts of a real BaseItemDto this app never decodes.
    func serverItem() -> [String: Any] {
        [
            "Id": "abc",
            "Name": "コードギアス 反逆のルルーシュ",
            "Overview": "An old synopsis.",
            "ProductionYear": 2006,
            "ProviderIds": ["Tvdb": "79525", "Imdb": "tt0999913"],
            "People": [["Name": "Someone", "Type": "Director"]],
            "Taglines": ["A tagline"],
            "LockedFields": [],
        ]
    }

    t.suite("Item edit payload") { t in

        t.test("the edited field is set and everything else survives") {
            let payload = ItemEdit(name: "Code Geass: Lelouch of the Rebellion")
                .applied(to: serverItem())

            t.expectEqual(payload["Name"] as? String, "Code Geass: Lelouch of the Rebellion")
            // The fields this app has never heard of are the ones a typed
            // round-trip would quietly erase.
            t.expectNotNil(payload["ProviderIds"], "provider ids survive an edit")
            t.expectNotNil(payload["People"], "cast survives an edit")
            t.expectEqual((payload["Taglines"] as? [String])?.first, "A tagline")
            t.expectEqual(payload["Overview"] as? String, "An old synopsis.")
        }

        t.test("an empty field means leave it alone, not clear it") {
            // A text field someone tabbed through must not erase what was there.
            let payload = ItemEdit(name: "", overview: "   ").applied(to: serverItem())
            t.expectEqual(payload["Name"] as? String, "コードギアス 反逆のルルーシュ")
            t.expectEqual(payload["Overview"] as? String, "An old synopsis.")
        }

        t.test("names are trimmed before they are saved") {
            let payload = ItemEdit(name: "  Code Geass  ").applied(to: serverItem())
            t.expectEqual(payload["Name"] as? String, "Code Geass")
        }

        t.test("locking a field is what makes the edit stick") {
            let payload = ItemEdit(name: "Code Geass", lockedFields: [.name])
                .applied(to: serverItem())
            t.expectEqual(payload["LockedFields"] as? [String], ["Name"])
        }

        t.test("existing locks are kept, never replaced") {
            // Someone who locked Genres last month should not lose that by
            // renaming something today.
            var item = serverItem()
            item["LockedFields"] = ["Genres", "Studios"]
            let payload = ItemEdit(name: "Code Geass", lockedFields: [.name])
                .applied(to: item)
            t.expectEqual(payload["LockedFields"] as? [String], ["Genres", "Name", "Studios"])
        }

        t.test("the same edit twice produces the same payload") {
            // An unordered set here would make every save look like a change.
            let edit = ItemEdit(name: "X", lockedFields: [.name, .overview, .genres])
            let first = edit.applied(to: serverItem())["LockedFields"] as? [String]
            let second = edit.applied(to: serverItem())["LockedFields"] as? [String]
            t.expectEqual(first, second)
        }

        t.test("a sort name is forced only when the caller says it is an override") {
            // Both halves matter. Without ForcedSortName the server recomputes the
            // order from the title on the next scan, so a real override needs it —
            // but the editor prefills this field from the server's *computed* sort
            // name, and writing it back unconditionally turned an automatic value
            // into a permanent manual override on every item ever opened there.
            let deliberate = ItemEdit(sortName: "Code Geass 01", forcesSortName: true)
                .applied(to: serverItem())
            t.expectEqual(deliberate["SortName"] as? String, "Code Geass 01")
            t.expectEqual(deliberate["ForcedSortName"] as? String, "Code Geass 01")

            let untouched = ItemEdit(sortName: "Code Geass 01").applied(to: serverItem())
            t.expectEqual(untouched["SortName"] as? String, "Code Geass 01")
            t.expectNil(untouched["ForcedSortName"])
        }

        t.test("locking everything is off unless asked for") {
            t.expectNil(ItemEdit(name: "X").applied(to: serverItem())["LockData"])
            t.expectEqual(
                ItemEdit(name: "X", lockAll: true).applied(to: serverItem())["LockData"] as? Bool,
                true
            )
        }

        t.test("the original title is kept apart from the display name") {
            let payload = ItemEdit(
                name: "Code Geass", originalTitle: "コードギアス 反逆のルルーシュ"
            ).applied(to: serverItem())
            t.expectEqual(payload["Name"] as? String, "Code Geass")
            t.expectEqual(payload["OriginalTitle"] as? String, "コードギアス 反逆のルルーシュ")
        }

        t.test("a year of zero is still a year, and nil still means unchanged") {
            t.expectEqual(
                ItemEdit(productionYear: 1998).applied(to: serverItem())["ProductionYear"] as? Int,
                1998
            )
            t.expectEqual(
                ItemEdit(name: "X").applied(to: serverItem())["ProductionYear"] as? Int,
                2006
            )
        }
    }
}

/// The field set is a safety property, so it is pinned like one.
///
/// `updateItem` posts the detail response back as the whole item. Anything missing
/// from this list is a field the next save silently clears — which is how provider
/// ids, tags, original titles and every existing lock were being destroyed by an
/// edit to an unrelated field.
@MainActor
func registerEditFieldSetTests(_ t: TestRunner) {
    t.suite("Edit field set") { t in
        t.test("the detail fields carry everything a write must not lose") {
            let fields = JellyfinClient.FieldSet.detail.value
            for required in [
                "ProviderIds", "Tags", "OriginalTitle", "Settings",
                "ProductionLocations", "CustomRating", "SortName", "Overview", "Genres",
            ] {
                t.expect(
                    fields.contains(required),
                    "Fields is missing \(required); a save would clear it on the server"
                )
            }
        }
    }
}

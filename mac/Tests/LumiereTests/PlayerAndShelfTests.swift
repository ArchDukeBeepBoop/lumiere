import Foundation
import TestKit
import LumiereKit

/// The volume the player opens at.
@MainActor
func registerRememberedVolumeTests(_ t: TestRunner) {

    t.suite("Remembered volume") { t in

        let key = PlayerVolume.storageKey

        t.test("a fresh install opens at full volume") {
            UserDefaults.standard.removeObject(forKey: key)
            t.expectEqual(PlayerVolume.remembered(), PlayerVolume.defaultLevel)
        }

        t.test("a stored level is read back") {
            UserDefaults.standard.set(0.4, forKey: key)
            t.expectEqual(PlayerVolume.remembered(), 0.4)
            UserDefaults.standard.removeObject(forKey: key)
        }

        t.test("a preference file is not trusted to be sane") {
            // Editable by hand, and a volume of 40 is silence then clipping
            // rather than loud.
            UserDefaults.standard.set(40.0, forKey: key)
            t.expectEqual(PlayerVolume.remembered(), 1)
            UserDefaults.standard.set(-3.0, forKey: key)
            t.expectEqual(PlayerVolume.remembered(), 0)
            UserDefaults.standard.removeObject(forKey: key)
        }

        t.test("silence is a level someone can mean") {
            // Zero is a real choice and must survive, which is why the read
            // checks for the key rather than treating 0 as "unset".
            UserDefaults.standard.set(0.0, forKey: key)
            t.expectEqual(PlayerVolume.remembered(), 0)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// The settings panel takes a share of the player.
@MainActor
func registerSettingsPanelSizeTests(_ t: TestRunner) {

    t.suite("Player settings panel size") { t in

        t.test("a small window never has the panel cover it") {
            // The minimum window is 720 wide, and every control in the panel is
            // judged against the picture behind it — a panel covering the frame
            // defeats the reason it is not a sheet.
            let size = PlayerPanelSize.settingsPanel(
                in: CGSize(width: 720, height: 420)
            )
            t.expect(size.width <= 720 * 0.9, "panel is \(size.width) wide in a 720 window")
            t.expect(size.height <= 420 * 0.8, "panel is \(size.height) tall in a 420 window")
        }

        t.test("a large display does not leave it stranded at dialog size") {
            let size = PlayerPanelSize.settingsPanel(
                in: CGSize(width: 2560, height: 1440)
            )
            t.expect(size.width > 640, "panel should grow past the old constant, got \(size.width)")
            // And still bounded: a panel half the width of a 5K display is a wall.
            t.expect(size.width <= 820, "panel is \(size.width) wide")
        }

        t.test("before the first layout it falls back rather than collapsing") {
            let size = PlayerPanelSize.settingsPanel(in: .zero)
            t.expectEqual(size.width, 640)
            t.expectEqual(size.height, 420)
        }
    }
}

/// The two shelves that answer what Continue Watching and Next Up don't.
@MainActor
func registerNewShelfTests(_ t: TestRunner) {

    t.suite("Finish the season and Forgotten") { t in

        t.test("both are in the default order, under the row each answers") {
            let order = HomeOrder.defaultOrder(libraryIds: [])
            guard let finish = order.firstIndex(of: .finishSeason),
                  let resume = order.firstIndex(of: .continueWatching),
                  let forgotten = order.firstIndex(of: .forgotten),
                  let next = order.firstIndex(of: .nextUp)
            else { return t.expect(false, "both sections should be in the default order") }
            // Each sits directly beneath the shelf whose question it finishes.
            t.expectEqual(finish, resume + 1)
            t.expectEqual(forgotten, next + 1)
        }

        t.test("they survive a round trip through preferences") {
            // The ids are what gets written to disk; a rename would silently
            // reset somebody's home screen.
            t.expectEqual(HomeSection(id: "finishSeason"), .finishSeason)
            t.expectEqual(HomeSection(id: "forgotten"), .forgotten)
            t.expectEqual(HomeSection.finishSeason.id, "finishSeason")
            t.expectEqual(HomeSection.forgotten.id, "forgotten")
        }

        t.test("an order written before they existed gets them back in place") {
            // The upgrade case: a preference saved last week never mentions them.
            let old = HomeOrder.defaultOrder(libraryIds: ["lib"])
                .filter { $0 != .finishSeason && $0 != .forgotten }
            let resolved = HomeOrder.resolve(stored: HomeOrder.encode(old), libraryIds: ["lib"])
            t.expectEqual(resolved, HomeOrder.defaultOrder(libraryIds: ["lib"]))
        }

        t.test("they are named as shelves, not as jargon") {
            t.expectEqual(HomeSection.finishSeason.title { _ in nil }, "Finish the Season")
            t.expectEqual(HomeSection.forgotten.title { _ in nil }, "Forgotten")
        }

        t.test("the thresholds are one number, not three") {
            // "Nearly done" appears in a shelf, in the hero's reasoning and in
            // the copy under both; three copies would not stay equal.
            t.expectEqual(SeriesProgress.nearlyDoneRemaining, SpotlightReason.nearlyDoneRemaining)
            t.expectEqual(SeriesProgress.forgottenAfter, SpotlightReason.forgottenAfter)
        }
    }
}

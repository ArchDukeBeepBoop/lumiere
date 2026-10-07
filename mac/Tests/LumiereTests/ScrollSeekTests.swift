import Foundation
import TestKit
import LumiereKit

/// Scroll deltas becoming seek steps.
@MainActor
func registerScrollSeekTests(_ t: TestRunner) {

    t.suite("Scroll seeking") { t in

        t.test("a trackpad swipe sums into whole seconds") {
            var seek = ScrollSeek()
            // Four points is under a second: nothing yet.
            t.expectEqual(seek.add(deltaX: -2, precise: true), nil)
            t.expectEqual(seek.add(deltaX: -2, precise: true), nil)
            // Six points total is 1.2s: one second out, 0.2 kept.
            t.expectEqual(seek.add(deltaX: -2, precise: true), 1)
            // Another four points: 0.2 + 0.8 = 1.0.
            t.expectEqual(seek.add(deltaX: -4, precise: true), 1)
        }

        t.test("fingers moving right is forward, left is back") {
            var seek = ScrollSeek()
            t.expectEqual(seek.add(deltaX: -10, precise: true), 2)
            t.expectEqual(seek.add(deltaX: 10, precise: true), -2)
        }

        t.test("a wheel notch is a whole step") {
            var seek = ScrollSeek()
            t.expectEqual(seek.add(deltaX: -1, precise: false), ScrollSeek.secondsPerNotch)
        }

        t.test("reset drops the remainder") {
            var seek = ScrollSeek()
            t.expectEqual(seek.add(deltaX: -4, precise: true), nil)
            seek.reset()
            t.expectEqual(seek.add(deltaX: -1, precise: true), nil)
        }
    }
}

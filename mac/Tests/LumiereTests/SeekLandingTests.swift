import Foundation
import TestKit
import LumiereKit

/// Whether a released scrubber decodes forward to the exact frame.
@MainActor
func registerSeekLandingTests(_ t: TestRunner) {

    t.suite("Seek landing") { t in

        t.test("auto lands exactly on 1080p and on a keyframe at 4K") {
            t.expect(SeekLanding.auto.landsExactly(width: 1920))
            t.expect(SeekLanding.auto.landsExactly(width: 2560 - 1), "1440p is still light")
            t.expect(!SeekLanding.auto.landsExactly(width: 3840))
        }

        t.test("an unknown width is treated as light") {
            t.expect(SeekLanding.auto.landsExactly(width: nil))
        }

        t.test("the outright choices ignore the width") {
            t.expect(SeekLanding.exact.landsExactly(width: 7680))
            t.expect(!SeekLanding.keyframe.landsExactly(width: 640))
        }

        t.test("the stored default is auto") {
            t.expectEqual(SeekLanding(rawValue: Preference.seekLanding.defaultValue), .auto)
        }
    }
}

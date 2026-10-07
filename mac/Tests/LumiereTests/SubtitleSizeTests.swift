import Foundation
import TestKit
import LumiereKit

/// What the size control actually asks mpv for.
///
/// Worth pinning because the interesting part is invisible: on an anime library
/// most tracks are ASS, and mpv leaves ASS alone unless it is told otherwise — so
/// a size control that sets only `sub-scale` looks like it does nothing on the
/// exact library that needed it most.
@MainActor
func registerSubtitleSizeTests(_ t: TestRunner) {

    func options(_ size: SubtitleSize) -> [String: String] {
        Dictionary(uniqueKeysWithValues: size.mpvOptions)
    }

    t.suite("Subtitle size") { t in

        t.test("normal sets nothing, so a typeset script is untouched") {
            t.expectEqual(SubtitleSize.normal.mpvOptions.count, 0)
        }

        t.test("a chosen size lets the scale reach ASS, and only the scale") {
            for size in [SubtitleSize.small, .large] {
                t.expectEqual(options(size)["sub-ass-override"], "scale")
            }
        }

        t.test("small shrinks and large grows") {
            t.expect(SubtitleSize.small.scale < 1, "small must be under unity")
            t.expect(SubtitleSize.large.scale > 1, "large must be over unity")
            t.expectEqual(SubtitleSize.normal.scale, 1.0)
        }

        t.test("the scale mpv is given matches the stated one") {
            t.expectEqual(options(.large)["sub-scale"], "1.30")
            t.expectEqual(options(.small)["sub-scale"], "0.80")
        }

        t.test("an unknown or missing stored value reads as normal") {
            // The stored form is a raw string in UserDefaults, so it can be absent
            // on first run and stale after a rename.
            t.expectEqual(SubtitleSize.size(id: nil), .normal)
            t.expectEqual(SubtitleSize.size(id: "enormous"), .normal)
            t.expectEqual(SubtitleSize.size(id: "large"), .large)
        }
    }
}

/// The one duration formatter, and the input that used to take the process down.
@MainActor
func registerTimecodeTests(_ t: TestRunner) {
    t.suite("Timecode") { t in
        t.test("a non-finite duration reads 0:00 instead of trapping") {
            // `Int(Double.nan)` traps in Swift. The detail page's copy had no guard,
            // so a chapter with a non-finite start time crashed there while every
            // other copy printed "0:00".
            t.expectEqual(Timecode.string(.nan), "0:00")
            t.expectEqual(Timecode.string(.infinity), "0:00")
            t.expectEqual(Timecode.string(-5), "0:00")
        }

        t.test("hours appear only when there are hours") {
            t.expectEqual(Timecode.string(0), "0:00")
            t.expectEqual(Timecode.string(61), "1:01")
            t.expectEqual(Timecode.string(2_531), "42:11")
            t.expectEqual(Timecode.string(3_600), "1:00:00")
            t.expectEqual(Timecode.string(7_384), "2:03:04")
        }
    }
}

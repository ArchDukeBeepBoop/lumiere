import Foundation
import TestKit
import LumiereKit

/// Cutting one frame out of a trickplay sheet.
@MainActor
func registerTrickplayCellTests(_ t: TestRunner) {
    // 5x5 grid of 320x180 frames.
    let info = TrickplayInfo(
        width: 320, height: 180, tileWidth: 5, tileHeight: 5,
        thumbnailCount: 60, interval: 10_000
    )

    t.suite("Trickplay cell") { t in

        t.test("the first frame is the top-left cell") {
            let location = TrickplayLocation(sheetIndex: 0, column: 0, row: 0, thumbnailIndex: 0)
            let cell = info.cell(at: location, inSheetOf: 1600, by: 900)
            t.expectEqual(cell?.x, 0)
            t.expectEqual(cell?.y, 0)
            t.expectEqual(cell?.width, 320)
            t.expectEqual(cell?.height, 180)
        }

        t.test("a middle frame lands on its own row and column") {
            let location = TrickplayLocation(sheetIndex: 0, column: 3, row: 2, thumbnailIndex: 13)
            let cell = info.cell(at: location, inSheetOf: 1600, by: 900)
            t.expectEqual(cell?.x, 960)
            t.expectEqual(cell?.y, 360)
        }

        t.test("the sheet's real size wins over the reported frame size") {
            // A server that re-encoded its tiles reports 320x180 and stores half
            // that. Trusting the report crops a quarter of the wrong frame.
            let cell = info.cell(
                at: TrickplayLocation(sheetIndex: 0, column: 1, row: 1, thumbnailIndex: 6),
                inSheetOf: 800, by: 450
            )
            t.expectEqual(cell?.width, 160)
            t.expectEqual(cell?.x, 160)
        }

        t.test("a cell outside the sheet is declined, not clamped") {
            let location = TrickplayLocation(sheetIndex: 0, column: 9, row: 0, thumbnailIndex: 9)
            t.expectNil(info.cell(at: location, inSheetOf: 1600, by: 900))
        }

        t.test("a sheet too small to hold one cell is declined") {
            let location = TrickplayLocation(sheetIndex: 0, column: 0, row: 0, thumbnailIndex: 0)
            t.expectNil(info.cell(at: location, inSheetOf: 3, by: 3))
        }

        t.test("locate picks the frame covering that moment") {
            // 10s interval: 125s is frame 12, which on a 5-wide grid is row 2,
            // column 2.
            let location = info.locate(seconds: 125)
            t.expectEqual(location?.thumbnailIndex, 12)
            t.expectEqual(location?.row, 2)
            t.expectEqual(location?.column, 2)
        }
    }
}

import Foundation
import TestKit
import LumiereKit

/// Trickplay is pure arithmetic over a tile grid, and getting it wrong shows the
/// wrong frame while scrubbing — which is worse than showing none. So it is
/// tested exhaustively even though the server data cannot be reached from here.
@MainActor
func registerTrickplayTests(_ t: TestRunner) {

    // A typical Jellyfin layout: 320px thumbs, 10 seconds apart, 10x10 per sheet.
    let info = TrickplayInfo(
        width: 320, height: 180, tileWidth: 10, tileHeight: 10,
        thumbnailCount: 250, interval: 10_000
    )

    t.suite("Trickplay geometry") { t in

        t.test("the first frame is the top-left cell of the first sheet") {
            let location = info.locate(seconds: 0)
            t.expectEqual(location?.sheetIndex, 0)
            t.expectEqual(location?.column, 0)
            t.expectEqual(location?.row, 0)
        }

        t.test("a time inside the first interval still maps to the first cell") {
            // 9.9s is before the second thumbnail at 10s.
            t.expectEqual(info.locate(seconds: 9.9)?.thumbnailIndex, 0)
            t.expectEqual(info.locate(seconds: 10.0)?.thumbnailIndex, 1)
        }

        t.test("cells fill left to right, then down") {
            t.expectEqual(info.locate(seconds: 90)?.column, 9)
            t.expectEqual(info.locate(seconds: 90)?.row, 0)
            // The eleventh thumbnail wraps onto the second row.
            t.expectEqual(info.locate(seconds: 100)?.column, 0)
            t.expectEqual(info.locate(seconds: 100)?.row, 1)
        }

        t.test("sheets roll over after 100 thumbnails") {
            // Index 99 is the last cell of sheet 0; index 100 opens sheet 1.
            t.expectEqual(info.locate(seconds: 990)?.sheetIndex, 0)
            t.expectEqual(info.locate(seconds: 990)?.row, 9)
            t.expectEqual(info.locate(seconds: 990)?.column, 9)

            t.expectEqual(info.locate(seconds: 1000)?.sheetIndex, 1)
            t.expectEqual(info.locate(seconds: 1000)?.row, 0)
            t.expectEqual(info.locate(seconds: 1000)?.column, 0)
        }

        t.test("scrubbing past the end clamps to the last thumbnail") {
            // 250 thumbnails at 10s covers 2500s; ask for an hour.
            let location = info.locate(seconds: 3600)
            t.expectEqual(location?.thumbnailIndex, 249)
            t.expectEqual(location?.sheetIndex, 2)
        }

        t.test("a negative time yields nothing rather than a negative index") {
            t.expectNil(info.locate(seconds: -5))
        }

        t.test("degenerate metadata is rejected rather than dividing by zero") {
            let broken = TrickplayInfo(
                width: 320, height: 180, tileWidth: 10, tileHeight: 10,
                thumbnailCount: 0, interval: 0
            )
            t.expectNil(broken.locate(seconds: 10))
        }

        t.test("a single-column sheet still walks down rows") {
            let strip = TrickplayInfo(
                width: 320, height: 180, tileWidth: 1, tileHeight: 20,
                thumbnailCount: 40, interval: 5_000
            )
            t.expectEqual(strip.locate(seconds: 10)?.row, 2)
            t.expectEqual(strip.locate(seconds: 10)?.column, 0)
            t.expectEqual(strip.locate(seconds: 100)?.sheetIndex, 1)
        }

        t.test("thumbnails per sheet is the product of the tile grid") {
            t.expectEqual(info.thumbnailsPerSheet, 100)
        }
    }

    t.suite("Trickplay URLs") { t in
        let server = URL(string: "http://192.168.60.40:8096")!

        t.test("builds a sheet URL keyed by thumbnail width") {
            let url = StreamBuilder.trickplayURL(
                serverURL: server, itemId: "abc", width: 320, sheetIndex: 2
            )?.absoluteString ?? ""
            t.expect(url.hasSuffix("/Videos/abc/Trickplay/320/2.jpg"), url)
        }

        t.test("carries the media source when a title has several versions") {
            let url = StreamBuilder.trickplayURL(
                serverURL: server, itemId: "abc", width: 320,
                sheetIndex: 0, mediaSourceId: "src7"
            )?.absoluteString ?? ""
            t.expect(url.contains("mediaSourceId=src7"), url)
        }
    }
}

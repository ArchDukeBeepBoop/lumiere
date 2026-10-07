import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import TestKit
import LumiereKit

@MainActor
func registerDownsampleTests(_ t: TestRunner) {

    t.suite("Downsample sizing") { t in

        t.test("an SVG logo decodes to a transparent bitmap at the asked size") {
            let svg = Data("""
            <?xml version="1.0"?>
            <svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">
              <rect x="0" y="0" width="200" height="200" fill="white"/>
            </svg>
            """.utf8)
            t.expect(Downsample.isSVG(svg))
            let image = Downsample.decode(data: svg, maxPixelSize: 100)
            t.expectEqual(image?.width, 100)
            t.expectEqual(image?.height, 50)
            t.expect(image?.alphaInfo == CGImageAlphaInfo.premultipliedLast,
                     "a logo needs its transparency")
        }

        t.test("a JPEG is not mistaken for SVG") {
            t.expect(!Downsample.isSVG(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])))
        }

        t.test("a 2:3 poster sizes by its height, the longest edge") {
            // 150pt wide at 2× is 300px wide, so 450px tall.
            let size = Downsample.targetPixelSize(
                displayWidth: 150, aspectRatio: 2.0 / 3.0, screenScale: 2
            )
            t.expectEqual(size, 450)
        }

        t.test("a 16:9 backdrop sizes by its width") {
            let size = Downsample.targetPixelSize(
                displayWidth: 1280, aspectRatio: 16.0 / 9.0, screenScale: 2
            )
            t.expectEqual(size, 2560)
        }

        t.test("a 1× display halves the decode size") {
            let retina = Downsample.targetPixelSize(
                displayWidth: 150, aspectRatio: 2.0 / 3.0, screenScale: 2
            )
            let standard = Downsample.targetPixelSize(
                displayWidth: 150, aspectRatio: 2.0 / 3.0, screenScale: 1
            )
            t.expectEqual(standard, retina / 2)
        }

        t.test("fractional sizes round up, never down") {
            // 100.5 × 2 = 201px wide; at 2:3 that is 301.5px tall.
            let size = Downsample.targetPixelSize(
                displayWidth: 100.5, aspectRatio: 2.0 / 3.0, screenScale: 2
            )
            t.expectEqual(size, 302)
        }

        t.test("the maximum is respected") {
            let size = Downsample.targetPixelSize(
                displayWidth: 8000, aspectRatio: 16.0 / 9.0, screenScale: 2, maximum: 4096
            )
            t.expectEqual(size, 4096)
        }

        t.test("degenerate input yields 1 rather than crashing or returning 0") {
            t.expectEqual(Downsample.targetPixelSize(displayWidth: 0, aspectRatio: 1, screenScale: 2), 1)
            t.expectEqual(Downsample.targetPixelSize(displayWidth: 150, aspectRatio: 0, screenScale: 2), 1)
            t.expectEqual(Downsample.targetPixelSize(displayWidth: 150, aspectRatio: 1, screenScale: 0), 1)
            t.expectEqual(Downsample.targetPixelSize(displayWidth: -5, aspectRatio: 1, screenScale: 2), 1)
        }
    }

    t.suite("Server request width ladder") { t in

        t.test("snaps up to a standard rung so the server caches one size") {
            t.expectEqual(Downsample.requestWidth(forDisplayWidth: 150, screenScale: 2), 320)
            t.expectEqual(Downsample.requestWidth(forDisplayWidth: 155, screenScale: 2), 320)
            t.expectEqual(Downsample.requestWidth(forDisplayWidth: 161, screenScale: 2), 480)
        }

        t.test("nearby cell sizes share one rung, so the server resizes once") {
            let a = Downsample.requestWidth(forDisplayWidth: 148, screenScale: 2)
            let b = Downsample.requestWidth(forDisplayWidth: 152, screenScale: 2)
            t.expectEqual(a, b)
        }

        t.test("an oversized request clamps to the top rung") {
            t.expectEqual(Downsample.requestWidth(forDisplayWidth: 9000, screenScale: 2), 3840)
        }
    }

    t.suite("Downsample decoding") { t in

        // A 2000x3000 poster: the exact case the pipeline exists to avoid
        // decoding at full size.
        guard let posterData = makeJPEG(width: 2000, height: 3000) else {
            t.test("could not synthesise test image") { t.expect(false) }
            return
        }

        t.test("decodes to the requested longest edge, not the source size") {
            let image = Downsample.decode(data: posterData, maxPixelSize: 450)
            t.expectNotNil(image)
            t.expectEqual(image?.height, 450)
            t.expectEqual(image?.width, 300)
        }

        t.test("a downsampled poster costs a fraction of the full decode") {
            let full = Downsample.decode(data: posterData, maxPixelSize: 3000)!
            let thumb = Downsample.decode(data: posterData, maxPixelSize: 450)!

            let fullCost = Downsample.byteCost(of: full)
            let thumbCost = Downsample.byteCost(of: thumb)

            // Full decode is ~24 MB; the thumbnail must be under 1 MB. This is the
            // core memory claim of the whole app, so it is asserted, not assumed.
            t.expect(fullCost > 20_000_000, "full decode should be ~24 MB, was \(fullCost)")
            t.expect(thumbCost < 1_000_000, "thumbnail should be under 1 MB, was \(thumbCost)")
            t.expect(fullCost / thumbCost > 20,
                     "expected >20x saving, got \(fullCost / thumbCost)x")
        }

        t.test("byte cost is proportional to pixel count") {
            let small = Downsample.decode(data: posterData, maxPixelSize: 300)!
            let large = Downsample.decode(data: posterData, maxPixelSize: 600)!
            let ratio = Double(Downsample.byteCost(of: large)) / Double(Downsample.byteCost(of: small))
            // Doubling the edge quadruples the area, allowing for row padding.
            t.expect(ratio > 3.5 && ratio < 4.5, "expected ~4x, got \(ratio)x")
        }

        t.test("garbage data returns nil rather than throwing") {
            t.expectNil(Downsample.decode(data: Data([0x00, 0x01, 0x02]), maxPixelSize: 300))
            t.expectNil(Downsample.decode(data: Data(), maxPixelSize: 300))
        }
    }
}

/// Synthesises a JPEG of the given dimensions, so the decode tests run without
/// any fixture files or a live server.
private func makeJPEG(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // A gradient rather than flat colour: a solid fill compresses to almost
    // nothing and would not exercise a realistic decode.
    for y in stride(from: 0, to: height, by: 4) {
        context.setFillColor(
            red: Double(y) / Double(height),
            green: 0.35,
            blue: 1 - Double(y) / Double(height),
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: y, width: width, height: 4))
    }

    guard let image = context.makeImage() else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
}

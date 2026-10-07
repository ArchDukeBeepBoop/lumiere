import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import TestKit
import LumiereKit

/// Forces a decoded image's pixels into memory.
///
/// The reason this exists is the reason these tests were passing for free: a
/// `CGImage` from `CGImageSourceCreateThumbnailAtIndex` is lazy — it holds a
/// description of the bitmap, not the bitmap — so a test that decodes four hundred
/// posters and never draws one measures almost nothing. Reproduced both ways: with a
/// 24 MB cache the footprint grew 7.1 MB, and with a 2,000 MB cache it grew 4.6 MB.
/// Identical within noise, both far under the 60 MB assertion, so the bound the test
/// exists to defend could have been deleted entirely and it would still have passed.
///
/// Drawn once into a throwaway 64x64 context, the same run gives 26.6 MB against
/// 195.0 MB. That is the difference the assertion is supposed to see.
@MainActor
private func materialise(_ image: DecodedImage?) {
    guard let cgImage = image?.cgImage else { return }
    guard let context = CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
}

/// The memory budget, enforced.
///
/// Scrolling a real grid cannot be automated from this shell — posting synthetic
/// scroll events needs Accessibility permission — so the guarantee is asserted
/// where it actually lives: the pipeline. If 400 posters can pass through it
/// while the process stays bounded, a grid displaying them will too, because the
/// grid holds nothing the pipeline does not.
@MainActor
func registerMemoryBudgetTests(_ t: TestRunner) async {

    func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumiere-mem-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    await t.suite("Memory budget") { t in

        t.test("the footprint probe returns something plausible") {
            guard let bytes = MemoryProbe.physFootprint() else {
                t.expect(false, "probe returned nil")
                return
            }
            t.expect(bytes > 1_000_000, "footprint should exceed 1 MB, got \(bytes)")
            t.expect(bytes < 4_000_000_000, "footprint should be under 4 GB, got \(bytes)")
        }

        await t.test("400 posters through the pipeline stay inside the cache ceiling") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            // A 24 MB ceiling rather than the shipping 96 MB, so the bound is
            // crossed decisively within the test and a regression cannot hide
            // under headroom.
            let pipeline = try ImagePipeline(
                memoryByteLimit: 24_000_000,
                diskByteLimit: 200_000_000
            )

            let server = URL(string: "http://demo.local")!
            let count = 400

            // Seed the disk cache so no network is involved: this measures decode
            // and caching, which is what the budget is about.
            for index in 0..<count {
                let request = ImageRequest(
                    serverURL: server, itemId: "item-\(index)", kind: .primary,
                    tag: "tag-\(index)", displayWidth: 150,
                    aspectRatio: 2.0 / 3.0, screenScale: 2
                )
                guard let data = syntheticPoster(seed: index, width: request.requestWidth) else {
                    continue
                }
                await pipeline.seedDiskCache(data, for: request.diskKey)
            }

            let baseline = MemoryProbe.physFootprint() ?? 0

            for index in 0..<count {
                let request = ImageRequest(
                    serverURL: server, itemId: "item-\(index)", kind: .primary,
                    tag: "tag-\(index)", displayWidth: 150,
                    aspectRatio: 2.0 / 3.0, screenScale: 2
                )
                materialise(await pipeline.image(for: request))
            }

            let after = MemoryProbe.physFootprint() ?? 0
            let growthMB = Double(after - baseline) / 1_048_576

            // 400 posters drawn once are ~540 KB each: 195 MB measured with the
            // ceiling lifted, 26.6 MB with it in place. 45 leaves headroom over the
            // real figure while still failing if the bound is removed — which the
            // old limit of 60 did not, because without `materialise` above the whole
            // run measured 7 MB either way.
            print("      measured: 400 posters grew the footprint by \(Int(growthMB)) MB")
            t.expect(
                growthMB < 45,
                "400 posters grew the footprint by \(Int(growthMB)) MB; the 24 MB cache is not bounding"
            )
        }

        await t.test("a purge releases decoded bitmaps") {
            let pipeline = try ImagePipeline(
                memoryByteLimit: 48_000_000, diskByteLimit: 200_000_000
            )
            let server = URL(string: "http://demo.local")!

            for index in 0..<80 {
                let request = ImageRequest(
                    serverURL: server, itemId: "purge-\(index)", kind: .primary,
                    tag: "t", displayWidth: 150, aspectRatio: 2.0 / 3.0, screenScale: 2
                )
                if let data = syntheticPoster(seed: index, width: request.requestWidth) {
                    await pipeline.seedDiskCache(data, for: request.diskKey)
                }
                materialise(await pipeline.image(for: request))
            }

            let loaded = MemoryProbe.physFootprint() ?? 0
            await pipeline.purgeMemory(all: true)

            // Allocator behaviour makes an exact drop unassertable, so this checks
            // the purge is not a no-op that grows memory instead.
            let purged = MemoryProbe.physFootprint() ?? 0
            t.expect(
                purged <= loaded + 4_000_000,
                "purge should not increase the footprint (\(loaded) -> \(purged))"
            )
        }

        await t.test("the disk cache survives a purge, so re-display costs no download") {
            let pipeline = try ImagePipeline(
                memoryByteLimit: 8_000_000, diskByteLimit: 200_000_000
            )
            let server = URL(string: "http://demo.local")!
            let request = ImageRequest(
                serverURL: server, itemId: "survivor", kind: .primary, tag: "t",
                displayWidth: 150, aspectRatio: 2.0 / 3.0, screenScale: 2
            )

            guard let data = syntheticPoster(seed: 1, width: request.requestWidth) else {
                t.expect(false, "could not synthesise poster")
                return
            }
            await pipeline.seedDiskCache(data, for: request.diskKey)

            t.expectNotNil(await pipeline.image(for: request))
            await pipeline.purgeMemory(all: true)
            // Still resolvable with no network: the compressed copy is on disk.
            t.expectNotNil(await pipeline.image(for: request))
        }
    }
}

/// A compressible-but-not-trivial poster, so decode cost is realistic.
private func syntheticPoster(seed: Int, width: Int) -> Data? {
    let height = Int(Double(width) / (2.0 / 3.0))
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    for band in 0..<12 {
        let shade = Double((seed + band * 7) % 100) / 100
        context.setFillColor(CGColor(red: shade, green: 0.4, blue: 1 - shade, alpha: 1))
        context.fill(CGRect(
            x: 0, y: band * (height / 12), width: width, height: height / 12
        ))
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

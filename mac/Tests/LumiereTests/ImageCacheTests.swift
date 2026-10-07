import Foundation
import TestKit
import LumiereKit

@MainActor
func registerImageCacheTests(_ t: TestRunner) async {

    func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumiere-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    await t.suite("Image disk cache") { t in

        await t.test("stores and reads back") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let cache = try ImageDiskCache(directory: dir, byteLimit: 1_000_000)
            let payload = Data(repeating: 0xAB, count: 1024)
            await cache.store(payload, for: "poster|abc")
            let loaded = await cache.data(for: "poster|abc")
            t.expectEqual(loaded, payload)
        }

        await t.test("a missing key returns nil") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let cache = try ImageDiskCache(directory: dir, byteLimit: 1_000_000)
            let loaded = await cache.data(for: "never-stored")
            t.expectNil(loaded)
        }

        await t.test("keys with slashes and long tags do not break the filename") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let cache = try ImageDiskCache(directory: dir, byteLimit: 1_000_000)
            let nasty = "Items/abc/Images/Primary?tag=" + String(repeating: "x", count: 500)
            let payload = Data(repeating: 0x01, count: 64)
            await cache.store(payload, for: nasty)
            let loaded = await cache.data(for: nasty)
            t.expectEqual(loaded, payload)
        }

        await t.test("exceeding the byte limit evicts down to the low-water mark") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            // 10 KB budget, filled with 20 entries of 1 KB.
            let cache = try ImageDiskCache(directory: dir, byteLimit: 10_240)
            for index in 0..<20 {
                await cache.store(Data(repeating: UInt8(index), count: 1024), for: "key-\(index)")
            }
            let total = await cache.currentByteCount
            t.expect(total <= 10_240, "cache should stay within its limit, was \(total)")
            t.expect(total > 0, "cache should not evict everything")
        }

        await t.test("the most recently stored entry survives eviction") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let cache = try ImageDiskCache(directory: dir, byteLimit: 10_240)
            for index in 0..<20 {
                await cache.store(Data(repeating: UInt8(index), count: 1024), for: "key-\(index)")
            }
            let newest = await cache.data(for: "key-19")
            t.expectNotNil(newest, "the newest entry should not be the one evicted")
        }

        await t.test("removeAll empties the cache") {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let cache = try ImageDiskCache(directory: dir, byteLimit: 1_000_000)
            await cache.store(Data(repeating: 0x02, count: 2048), for: "a")
            await cache.removeAll()
            let loaded = await cache.data(for: "a")
            let total = await cache.currentByteCount
            t.expectNil(loaded)
            t.expectEqual(total, 0)
        }
    }

    t.suite("Image request keys") { t in

        let server = URL(string: "http://192.168.60.40:8096")!

        func request(width: CGFloat, scale: CGFloat = 2, tag: String = "t") -> ImageRequest {
            ImageRequest(
                serverURL: server, itemId: "item1", kind: .primary, tag: tag,
                displayWidth: width, aspectRatio: 2.0 / 3.0, screenScale: scale
            )
        }

        t.test("two cells of the same size share one memory entry") {
            t.expectEqual(request(width: 150).cacheKey, request(width: 150).cacheKey)
        }

        t.test("different cell sizes are separate memory entries") {
            t.expect(request(width: 150).cacheKey != request(width: 300).cacheKey)
        }

        t.test("nearby cell sizes share one downloaded file") {
            // 148pt and 152pt both land on the 320px rung, so the server is asked
            // once and the bytes are reused.
            t.expectEqual(request(width: 148).diskKey, request(width: 152).diskKey)
        }

        t.test("a changed artwork tag busts both caches") {
            t.expect(request(width: 150, tag: "old").cacheKey != request(width: 150, tag: "new").cacheKey)
            t.expect(request(width: 150, tag: "old").diskKey != request(width: 150, tag: "new").diskKey)
        }

        t.test("the built URL carries the ladder width, not the decode size") {
            let req = request(width: 150)
            let url = req.url?.absoluteString ?? ""
            t.expect(url.contains("maxWidth=320"), "expected the 320px rung, got \(url)")
        }

        func backdrop(width: CGFloat, scale: CGFloat = 2) -> ImageRequest {
            ImageRequest(
                serverURL: server, itemId: "item1", kind: .backdrop, tag: "t",
                displayWidth: width, aspectRatio: 16.0 / 9.0, screenScale: scale
            )
        }

        t.test("a backdrop is never requested larger than it is decoded") {
            // A 1512pt window at 2x laddered to 3840 while the decode ceiling for
            // this kind is 2560 — a download two thirds of which was discarded.
            t.expectEqual(backdrop(width: 1512).requestWidth, 2560)
        }

        t.test("every wide window asks for the same backdrop file") {
            // The point of the cap for offline browsing: the disk key stops moving
            // with the window, so one warmed file answers any size above the rung.
            t.expectEqual(backdrop(width: 1280).diskKey, backdrop(width: 1900).diskKey)
        }

        t.test("a poster is not capped — it never approaches the ceiling anyway") {
            t.expectEqual(request(width: 150).requestWidth, 320)
        }

        t.test("a 1x display asks the server for a smaller image") {
            t.expect(request(width: 150, scale: 1).requestWidth < request(width: 150, scale: 2).requestWidth)
        }
    }
}

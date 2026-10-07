import Foundation
import CoreGraphics
import Dispatch

/// What to load, and at what size. Built by views; resolved by `ImagePipeline`.
/// `CGImage` is immutable once created and safe to read from any thread, but
/// CoreGraphics predates `Sendable` and carries no conformance. This box states
/// that invariant in one place rather than scattering unsafe opt-outs.
public final class DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let byteCost: Int

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
        self.byteCost = Downsample.byteCost(of: cgImage)
    }
}

/// Loads artwork with a hard ceiling on memory.
///
/// Three layers: a bounded in-memory cache of decoded bitmaps, an LRU disk cache
/// of the compressed originals, and the network. Concurrent requests for the same
/// image are coalesced, so a grid scrolling past 40 copies of one series poster
/// issues one download.
public actor ImagePipeline {

    private let memoryCache = NSCache<NSString, DecodedImage>()
    private let diskCache: ImageDiskCache
    private let urlSession: URLSession
    private let headers: [String: String]

    private var inFlight: [String: Task<DecodedImage?, Never>] = [:]
    private var pressureSource: DispatchSourceMemoryPressure?

    /// 96 MB of decoded bitmaps — roughly 180 posters or 12 full-screen backdrops.
    /// Enough that scrolling back up is instant, small enough to stay inside the
    /// 180 MB idle budget alongside everything else.
    public init(
        memoryByteLimit: Int = 96_000_000,
        // Raised from 2 GB with the prefetch. Measured on a 45,000-item library:
        // 5,017 posters at three widths ≈ 530 MB, 2,576 backdrops at 2560px ≈ 1.3 GB,
        // 37,646 episode stills at 480px ≈ 1.5 GB — about 3.3 GB for a library that
        // browses completely with the server off. LRU-evicted, so this is a ceiling
        // rather than a reservation.
        diskByteLimit: Int = 4_000_000_000,
        headers: [String: String] = [:]
    ) throws {
        self.diskCache = try ImageDiskCache(byteLimit: diskByteLimit)
        self.headers = headers

        memoryCache.totalCostLimit = memoryByteLimit
        // Cost is bytes, so an item count limit would be redundant and would
        // evict small images unnecessarily.
        memoryCache.countLimit = 0

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        // Artwork is cached by this pipeline; a URLCache would store a second copy.
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 6
        self.urlSession = URLSession(configuration: config)

        Task { await self.installMemoryPressureHandler() }
    }

    // MARK: - Loading

    /// Puts an image on disk without decoding it or touching the memory cache.
    ///
    /// What a prefetch actually wants. `image(for:)` decodes every byte it fetches
    /// and inserts the result into the shared 96 MB cache — and a `CGImage` from
    /// `CGImageSourceCreateThumbnailAtIndex` does not materialise its pixels until
    /// something draws it, so a never-drawn prefetch cost ~4 MB of real memory for
    /// 400 images while being *charged* ~195 MB. Being the most recently inserted,
    /// those near-free entries evicted the posters actually on screen, which are the
    /// ones that do cost their full weight. The decode was wasted too: ~12 ms each,
    /// for a bitmap nothing ever drew.
    ///
    /// Disk is the layer a prefetch is for — it is what makes the image appear
    /// without a network round trip when you scroll to it. The decode belongs to
    /// whoever draws it.
    public func warmDisk(_ request: ImageRequest) async {
        if await diskCache.data(for: request.diskKey) != nil { return }
        guard let url = request.url else { return }

        var urlRequest = URLRequest(url: url)
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        guard let (data, response) = try? await urlSession.data(for: urlRequest),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty else {
            return
        }
        await diskCache.store(data, for: request.diskKey)
    }

    public func image(for request: ImageRequest) async -> DecodedImage? {
        let key = request.cacheKey

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Coalesce: forty cells asking for the same poster share one task.
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<DecodedImage?, Never> { [diskCache, urlSession, headers] in
            let pixelSize = request.decodePixelSize

            if let data = await diskCache.data(for: request.diskKey),
               let image = Downsample.decode(data: data, maxPixelSize: pixelSize) {
                return DecodedImage(image)
            }

            guard let url = request.url else { return nil }
            var urlRequest = URLRequest(url: url)
            for (field, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: field)
            }

            guard let (data, response) = try? await urlSession.data(for: urlRequest),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                return nil
            }

            await diskCache.store(data, for: request.diskKey)
            guard let image = Downsample.decode(data: data, maxPixelSize: pixelSize) else {
                return nil
            }
            return DecodedImage(image)
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            memoryCache.setObject(result, forKey: key as NSString, cost: result.byteCost)
        }
        return result
    }

    // MARK: - Memory pressure

    /// macOS asks politely before it starts killing processes. Dropping decoded
    /// bitmaps is nearly free here because the compressed originals are still on
    /// disk — re-decoding costs milliseconds, not another download.
    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let isCritical = source.data.contains(.critical)
            Task { await self.purgeMemory(all: isCritical) }
        }
        source.resume()
        pressureSource = source
    }

    public func purgeMemory(all: Bool) {
        if all {
            memoryCache.removeAllObjects()
        } else {
            // NSCache offers no partial eviction, so lowering the limit forces it
            // to shed, then the limit is restored.
            let limit = memoryCache.totalCostLimit
            memoryCache.totalCostLimit = limit / 4
            memoryCache.totalCostLimit = limit
        }
    }

    public func clearAll() async {
        memoryCache.removeAllObjects()
        await diskCache.removeAll()
    }

    public func diskByteCount() async -> Int {
        await diskCache.currentByteCount
    }

    /// Writes bytes directly into the disk cache under a known key.
    ///
    /// Used only by `DemoFixtures`, so the demo library renders through the real
    /// decode path and the real caches rather than through a mock — which is what
    /// makes a memory measurement taken against it meaningful.
    public func seedDiskCache(_ data: Data, for key: String) async {
        await diskCache.store(data, for: key)
    }
}

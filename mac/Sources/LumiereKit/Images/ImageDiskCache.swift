import Foundation
import CryptoKit

/// On-disk cache of original artwork bytes, LRU-evicted against a byte budget.
///
/// Separate from the in-memory cache and holding different things: this stores
/// the compressed JPEG the server sent (~30 KB), the memory cache stores the
/// decoded bitmap (~540 KB). Keeping the compressed copy means a poster survives
/// a relaunch and a memory-pressure purge without another round trip.
public actor ImageDiskCache {

    private let directory: URL
    private let byteLimit: Int
    private let fileManager = FileManager.default

    /// Tracked in memory so eviction does not stat the whole directory on every
    /// write. Rebuilt once at startup.
    private var totalBytes: Int = 0
    private var didLoadIndex = false

    public init(directory: URL? = nil, byteLimit: Int = 2_000_000_000) throws {
        if let directory {
            self.directory = directory
        } else {
            let caches = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            self.directory = caches
                .appendingPathComponent("Lumiere", isDirectory: true)
                .appendingPathComponent("Artwork", isDirectory: true)
        }
        self.byteLimit = byteLimit
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// SHA-256 of the cache key. Keys contain URLs and tags, which are not safe
    /// as filenames and can exceed the 255-byte limit.
    private func path(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    public func data(for key: String) -> Data? {
        let url = path(for: key)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        // Touch the access date so LRU eviction sees this as recently used.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func store(_ data: Data, for key: String) {
        loadIndexIfNeeded()

        let url = path(for: key)
        let existing = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        totalBytes += data.count - (existing ?? 0)
        if totalBytes > byteLimit {
            evict(toTarget: Int(Double(byteLimit) * 0.8))
        }
    }

    public func removeAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        totalBytes = 0
    }

    public var currentByteCount: Int {
        loadIndexIfNeeded()
        return totalBytes
    }

    // MARK: - Eviction

    private func loadIndexIfNeeded() {
        guard !didLoadIndex else { return }
        didLoadIndex = true
        totalBytes = entries().reduce(0) { $0 + $1.size }
    }

    private struct Entry {
        let url: URL
        let size: Int
        let accessed: Date
    }

    private func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            return Entry(
                url: url,
                size: size,
                accessed: values.contentModificationDate ?? .distantPast
            )
        }
    }

    /// Deletes least-recently-used files until under `target`. Evicting to 80% of
    /// the limit rather than exactly to it avoids thrashing — otherwise every
    /// subsequent write would trigger another directory scan.
    private func evict(toTarget target: Int) {
        var running = totalBytes
        for entry in entries().sorted(by: { $0.accessed < $1.accessed }) {
            guard running > target else { break }
            try? fileManager.removeItem(at: entry.url)
            running -= entry.size
        }
        totalBytes = running
    }
}

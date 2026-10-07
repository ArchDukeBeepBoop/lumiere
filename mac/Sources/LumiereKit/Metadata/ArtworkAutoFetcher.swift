import Foundation

/// Fills in missing posters automatically, using the server's own providers.
///
/// Choosing a poster by hand, one title at a time, does not scale past a handful —
/// and on a real library the gap is in the hundreds. This walks everything with no
/// Primary image, asks the server what its providers can offer, and applies the best
/// candidate without asking. The manual picker stays for the cases where the
/// automatic choice is wrong, which is what it is actually good for.
///
/// Everything happens server-side, so no API key lives here and the result lands in
/// the server's own database — every other client sees the same artwork.
public actor ArtworkAutoFetcher {

    public struct Progress: Sendable, Equatable {
        public let done: Int
        public let total: Int
        public let applied: Int
        public let currentTitle: String

        public var fraction: Double {
            total > 0 ? Double(done) / Double(total) : 0
        }
    }

    private let client: JellyfinClient
    private var task: Task<Void, Never>?
    private(set) public var progress: Progress?

    public init(client: JellyfinClient) {
        self.client = client
    }

    public var isRunning: Bool { task != nil }

    public func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }

    /// Works through `items`, applying the best offered poster to each.
    ///
    /// Sequential on purpose. Each item costs the server a provider round-trip and
    /// then an image download, and firing hundreds of those concurrently at a machine
    /// that is also serving video is the kind of thing that makes a media server
    /// stutter mid-playback. One at a time is slower and considerate; this is
    /// background work nobody is watching.
    public func run(
        items: [(id: String, name: String)],
        onProgress: (@Sendable (Progress) -> Void)? = nil,
        onItemUpdated: (@Sendable (String) -> Void)? = nil
    ) {
        guard task == nil, !items.isEmpty else { return }

        task = Task { [client] in
            var applied = 0
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }

                let didApply = await Self.applyBestImage(client: client, itemId: item.id)
                if didApply {
                    applied += 1
                    onItemUpdated?(item.id)
                }

                let snapshot = Progress(
                    done: index + 1, total: items.count,
                    applied: applied, currentTitle: item.name
                )
                // No `await`: this Task inherits the actor's isolation, so these are
                // already synchronous calls on it.
                self.update(snapshot)
                onProgress?(snapshot)
            }
            self.finish()
        }
    }

    /// Asks for candidates and applies the best one. Returns whether anything was
    /// applied, so the caller can report how much of the gap was actually closed
    /// rather than just how many items were tried.
    private static func applyBestImage(client: JellyfinClient, itemId: String) async -> Bool {
        // Each refusal named, because "0 of 45 applied" is not a result anybody can
        // act on. Measured on a real library: a missing-artwork pass over 45 items
        // applied nothing at all and said nothing about it, and the three reasons
        // that can produce that are entirely different problems — the server's
        // providers were never asked, or they were asked and offered nothing, or
        // they offered something with no usable URL. Only the middle one means
        // "there is no poster for this"; the first means the request failed.
        let options: [RemoteImageOption]
        do {
            options = try await client.remoteImages(itemId: itemId, type: "Primary")
        } catch {
            Diagnostics.log("[artwork] \(itemId) could not ask the server: \(error)")
            return false
        }
        guard let best = bestOption(from: options) else {
            Diagnostics.log("[artwork] \(itemId) no poster offered by any provider")
            return false
        }
        guard let url = best.url else {
            Diagnostics.log("[artwork] \(itemId) best candidate carries no URL")
            return false
        }

        do {
            try await client.applyRemoteImage(itemId: itemId, url: url, type: "Primary")
            return true
        } catch {
            Diagnostics.log("[artwork] \(itemId) failed: \(error)")
            return false
        }
    }

    /// Highest community rating wins, then largest. Providers return their own
    /// preferred image first, but that ordering mixes languages and sizes; a
    /// community score is the closest thing to "the one people actually chose".
    static func bestOption(from options: [RemoteImageOption]) -> RemoteImageOption? {
        options.max { left, right in
            let leftScore = left.communityRating ?? 0
            let rightScore = right.communityRating ?? 0
            if leftScore != rightScore { return leftScore < rightScore }
            return (left.width ?? 0) < (right.width ?? 0)
        }
    }

    private func update(_ snapshot: Progress) {
        progress = snapshot
    }

    private func finish() {
        task = nil
        progress = nil
    }
}

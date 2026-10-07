import Foundation

/// Warms the disk cache with every poster in the library, so browsing works with
/// the server switched off.
///
/// The cache alone was never enough for that. It fills only as artwork is
/// *displayed*, so a series never scrolled past had nothing stored and appeared as
/// a blank card offline — the library looked broken rather than merely stale.
///
/// Deliberately sequential and cancellable. Firing thousands of concurrent requests
/// at a Jellyfin server is how you make it thrash and stall real playback, and the
/// whole point of this app is to leave the server alone.
public actor ArtworkPrefetcher {

    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var bytesCached: Int

        public var fraction: Double {
            total > 0 ? Double(done) / Double(total) : 0
        }
    }

    private let pipeline: ImagePipeline
    private let serverURL: URL
    private var task: Task<Void, Never>?

    public private(set) var progress: Progress?

    public init(pipeline: ImagePipeline, serverURL: URL) {
        self.pipeline = pipeline
        self.serverURL = serverURL
    }

    /// One item's worth of what to fetch. A value type so the caller can build the
    /// list from the database and hand it over without the prefetcher needing to
    /// know about GRDB.
    public struct Target: Sendable, Hashable {
        public let itemId: String
        public let tag: String?
        public let kind: JellyfinImageURL.ImageKind
        /// The on-screen widths this particular image is drawn at, when they are not
        /// the run's default.
        ///
        /// One list for everything was wrong in both directions. Posters were being
        /// warmed at 384pt — a size no poster is ever drawn at, `continueCardWidth`
        /// being a *wide* card — which spent a quarter of the budget on files nothing
        /// could ever hit. Episode stills and backdrops were not warmed at all, and
        /// they are most of what a library looks like.
        public let widths: [CGFloat]?

        public init(
            itemId: String,
            tag: String?,
            kind: JellyfinImageURL.ImageKind,
            widths: [CGFloat]? = nil
        ) {
            self.itemId = itemId
            self.tag = tag
            self.kind = kind
            self.widths = widths
        }

        /// Where this target sits in the run, for the resume cursor.
        ///
        /// An item contributes more than one target now — a film has a poster and a
        /// backdrop — so its id alone is no longer a position in the list, and a
        /// resume keyed on it would drop everything after the first match.
        public var cursorKey: String { "\(itemId)|\(kind.rawValue)" }
    }

    /// Fetches every target at each display width, skipping whatever is cached.
    ///
    /// `widths` is the set of on-screen sizes the UI actually uses. Fetching one
    /// arbitrary size would not help: the cache keys include the decode width, so a
    /// poster stored at 240pt is a miss for a 140pt card and would be downloaded
    /// again the moment the server went away.
    public func run(
        targets: [Target],
        widths: [CGFloat],
        aspectRatio: CGFloat,
        screenScale: CGFloat,
        byteBudget: Int,
        resumeAfter: String? = nil,
        onProgress: (@Sendable (Progress) -> Void)? = nil,
        onItemComplete: (@Sendable (String) -> Void)? = nil
    ) {
        task?.cancel()

        // Everything up to and including the cursor is already done. Dropped rather
        // than re-checked so a resumed run does not walk 4,000 cache lookups first.
        let remaining: [Target]
        if let resumeAfter,
           let index = targets.firstIndex(where: { $0.cursorKey == resumeAfter }) {
            remaining = Array(targets[(index + 1)...])
            Diagnostics.log("[prefetch] resuming after \(resumeAfter), \(remaining.count) left")
        } else {
            remaining = targets
        }

        let total = remaining.reduce(0) { $0 + max(1, ($1.widths ?? widths).count) }
        progress = Progress(done: 0, total: total, bytesCached: 0)

        task = Task { [pipeline, serverURL] in
            var done = 0
            for target in remaining {
                if Task.isCancelled { break }

                // Checked per item rather than once at the start: the budget is
                // about the cache's total size, and this loop is what grows it.
                let bytes = await pipeline.diskByteCount()
                if bytes >= byteBudget {
                    Diagnostics.log("[prefetch] stopping at \(bytes / 1_000_000) MB — budget reached")
                    break
                }

                for width in target.widths ?? widths {
                    if Task.isCancelled { break }
                    let request = ImageRequest(
                        serverURL: serverURL,
                        itemId: target.itemId,
                        kind: target.kind,
                        tag: target.tag,
                        displayWidth: width,
                        aspectRatio: aspectRatio,
                        screenScale: screenScale
                    )
                    // Awaited, so the loop keeps its backpressure — and `warmDisk`
                    // rather than `image`, so this fills the disk cache without
                    // decoding a bitmap nothing will draw or evicting the posters
                    // that are on screen. See `ImagePipeline.warmDisk`.
                    await pipeline.warmDisk(request)
                    done += 1
                }

                let snapshot = Progress(done: done, total: total, bytesCached: bytes)
                // No `await`: this Task inherits the actor's isolation, so these are
                // already synchronous calls on it.
                self.update(snapshot)
                onProgress?(snapshot)
                // Recorded per item, after its widths are all fetched, so an interrupted
                // run loses at most one item's work.
                if !Task.isCancelled { onItemComplete?(target.cursorKey) }
            }
            self.finish()
        }
    }

    private func update(_ snapshot: Progress) {
        progress = snapshot
    }

    private func finish() {
        Diagnostics.log("[prefetch] finished \(progress?.done ?? 0) of \(progress?.total ?? 0)")
        progress = nil
    }

    public func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }
}

public extension ArtworkPrefetcher {
    /// Every on-screen width the UI actually asks for.
    ///
    /// One width is not enough, and that is not a detail: cache keys include the
    /// decode size, so a poster stored at 140pt is a *miss* at 120pt and gets fetched
    /// again the moment the server is gone. Prefetching only the grid width left the
    /// "More like this" shelf and the wide cards to fail offline.
    ///
    /// Kept as a list here so it cannot drift out of step with the views: any new card
    /// size has to be added, or that size is simply not available offline.
    /// Poster widths, and only poster widths.
    ///
    /// 384 used to be in here for "continue watching", which draws a `WideCard` —
    /// no poster is drawn at 384pt anywhere in the app, so every one of those
    /// downloads was a file nothing would ever ask for. On 5,017 titles that was
    /// most of a gigabyte.
    ///
    /// 220 covers `shelfPosterWidth` (200) as well: both land on the 480 rung.
    static let uiWidths: [CGFloat] = [
        120,  // "More like this"
        140,  // the library grid's default tile
        220,  // home shelves, library cards
    ]

    /// Wide 16:9 art — an episode's still, a series' thumb.
    ///
    /// One width, and it is a budget decision rather than a design one. 240pt is the
    /// episode list and the season strip, which is where almost every episode still
    /// in the app is drawn; 384pt is Continue Watching and Next Up, which show a
    /// dozen cards between them and warm themselves the first time you look at them.
    /// Adding 384 here would have meant 37,646 more files at roughly 110 KB each —
    /// four gigabytes to pre-cache twelve visible cards.
    static let wideWidths: [CGFloat] = [240]

    /// Full-bleed backdrops: the home hero and every detail header.
    ///
    /// One width, because `ImageRequest.requestWidth` now caps this kind at 2560 —
    /// so every window from 1280pt up asks for the same file, and warming that one
    /// file covers all of them.
    static let backdropWidths: [CGFloat] = [1280]

    /// The title set as artwork — a show's own logotype over its backdrop.
    ///
    /// One width: the detail header draws it at 440pt and the home hero at 380pt,
    /// and both land on the same 960 rung. Warmed because without it an offline
    /// header falls back to plain type, which is the "fonts in the backdrop"
    /// disappearing — 2,071 titles on this library have one.
    static let logoWidths: [CGFloat] = [440]
}

public extension LibraryRepository {
    /// The last item the prefetch finished, so a new run continues from there.
    ///
    /// Stored rather than held in memory because the run takes twenty minutes and the
    /// app gets quit — twice by a routine process kill during development. Without
    /// this, every interruption restarted from the first item and reported nothing,
    /// which is indistinguishable from never having run.
    func prefetchCursor() async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM syncState WHERE key = 'prefetch.cursor'"
            )
        }
    }

    func setPrefetchCursor(_ itemId: String?) async throws {
        try await database.writer.write { db in
            guard let itemId else {
                try db.execute(sql: "DELETE FROM syncState WHERE key = 'prefetch.cursor'")
                return
            }
            try db.execute(
                sql: "INSERT INTO syncState (key, value, updatedAt) VALUES ('prefetch.cursor', ?, ?) "
                   + "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
                arguments: [itemId, Date()]
            )
        }
    }
}

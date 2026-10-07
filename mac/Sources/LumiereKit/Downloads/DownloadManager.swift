import Foundation
import GRDB

/// Downloads items for offline playback, one at a time.
///
/// Sequential on purpose. Several concurrent multi-gigabyte transfers saturate the
/// link, make the server thrash, and ruin playback of whatever the user is actually
/// watching — the same thermal-and-politeness reasoning as everywhere else here.
///
/// Files land in Application Support, not Caches: the system may evict Caches under
/// disk pressure, and a download the user explicitly asked for disappearing on its
/// own is data loss from their point of view.
public actor DownloadManager {

    private let database: LibraryDatabase
    private let client: JellyfinClient
    private let directory: URL
    private var worker: Task<Void, Never>?
    /// Which worker owns the slot. See `clearWorker(generation:)`.
    private var workerGeneration = 0

    /// Nil when idle. Read by the UI for the progress row.
    public private(set) var active: DownloadRecord?

    public init(database: LibraryDatabase, client: JellyfinClient) throws {
        self.database = database
        self.client = client
        self.directory = try Self.defaultDirectory()
    }

    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("Lumiere", isDirectory: true)
        .appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Re-queues anything that was mid-flight when the app last stopped.
    ///
    /// A `.downloading` row means "a worker owns this", and at launch no worker
    /// does — quitting mid-download, or signing out, left the row saying otherwise
    /// forever. The list then showed a download in progress that nothing was
    /// progressing, and there was no control that fixed it: cancelling threw the
    /// partial file away, and asking for it again was the only route back.
    ///
    /// The partial file is left alone. `enqueue` already resets the byte count, and
    /// the transfer replaces the file outright rather than writing over it.
    public func requeueInterrupted() async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE download SET state = ? WHERE state = ?",
                arguments: [
                    DownloadRecord.State.queued.rawValue,
                    DownloadRecord.State.downloading.rawValue
                ]
            )
        }
        startWorker()
    }

    // MARK: - Queue

    /// Queues an item, then starts the worker if it is not already running.
    public func enqueue(itemId: String) async throws {
        let serverId = client.session.serverId
        try await database.writer.write { db in
            // An upsert rather than an insert: re-requesting a failed download
            // should retry it, not throw a primary-key conflict at the user.
            var record = try DownloadRecord.fetchOne(db, key: itemId)
                ?? DownloadRecord(itemId: itemId, serverId: serverId, requestedAt: Date())
            if record.state != .complete {
                record.state = .queued
                record.errorMessage = nil
                record.receivedBytes = 0
                record.requestedAt = Date()
            }
            try record.save(db)
        }
        startWorker()
    }

    public func cancel(itemId: String) async throws {
        try await database.writer.write { db in
            if let record = try DownloadRecord.fetchOne(db, key: itemId) {
                if let path = record.localPath {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                }
                try record.delete(db)
            }
        }
        if active?.itemId == itemId {
            worker?.cancel()
            workerGeneration += 1
            worker = nil
            active = nil
            startWorker()
        }
    }

    public func records() async throws -> [DownloadRecord] {
        try await database.writer.read { db in
            try DownloadRecord.order(Column("requestedAt").desc).fetchAll(db)
        }
    }

    public func record(for itemId: String) async throws -> DownloadRecord? {
        try await database.writer.read { db in try DownloadRecord.fetchOne(db, key: itemId) }
    }

    /// Stops everything in flight. Used on sign-out, where a download that keeps
    /// running holds the previous account's client and token and would write rows
    /// into a database being wiped.
    public func cancelAll() {
        worker?.cancel()
        // Bumped so the dying worker's own cleanup cannot clear a later one.
        workerGeneration += 1
        worker = nil
        active = nil
    }

    private func startWorker() {
        guard worker == nil else { return }
        workerGeneration += 1
        let generation = workerGeneration
        worker = Task { [weak self] in
            while let self, await self.drainOne() {
                if Task.isCancelled { break }
            }
            await self?.clearWorker(generation: generation)
        }
    }

    /// Clears the slot only if this worker still owns it.
    ///
    /// A cancelled worker used to clear unconditionally, and it ran *after* its
    /// replacement had been installed: `cancel(itemId:)` cancels W1, nils the slot
    /// and starts W2, then W1 finally unwinds and nils W2's handle. Two things then
    /// go wrong — the progress row for W2 freezes, because `report` guards on
    /// `active`; and the next enqueue sees an empty slot and starts W3 beside W2,
    /// which can take the same queued row and open two file handles on one path.
    private func clearWorker(generation: Int) {
        guard generation == workerGeneration else { return }
        worker = nil
        active = nil
    }

    /// Takes the next queued item and downloads it. Returns false when the queue is
    /// empty, which ends the worker.
    private func drainOne() async -> Bool {
        let next: DownloadRecord?
        do {
            next = try await database.writer.read { db in
                try DownloadRecord
                    .filter(Column("state") == DownloadRecord.State.queued.rawValue)
                    .order(Column("requestedAt"))
                    .fetchOne(db)
            }
        } catch {
            Diagnostics.log("[download] queue read failed: \(error)")
            return false
        }
        guard var record = next else { return false }

        record.state = .downloading
        active = record
        try? await save(record)

        do {
            let url = client.downloadURL(itemId: record.itemId)
            // Sanitised, because this name comes off the wire.
            //
            // `itemId` is decoded straight from server JSON and nothing validates its
            // shape. `appendingPathComponent` does not normalise, so an id containing
            // `../` resolved at the filesystem — and this app is not sandboxed, so a
            // hostile or compromised server could have chosen both the path and the
            // bytes written to it. `ImageDiskCache` already hashes its keys for
            // exactly this reason; this is the same defence, and the containment
            // check below is the belt to that braces.
            let safeName = record.itemId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            guard !safeName.isEmpty, safeName == record.itemId else {
                throw DownloadError.unusableItemId(record.itemId)
            }
            let destination = directory.appendingPathComponent(safeName + ".media")
            guard destination.deletingLastPathComponent().standardizedFileURL
                    == directory.standardizedFileURL else {
                throw DownloadError.unusableItemId(record.itemId)
            }
            let itemId = record.itemId
            let bytes = try await download(from: url, to: destination) { received, total in
                Task { [weak self] in await self?.report(itemId, received, total) }
            }

            record.state = .complete
            record.localPath = destination.path
            record.receivedBytes = bytes
            record.totalBytes = bytes
            record.completedAt = Date()
            record.errorMessage = nil
            Diagnostics.log("[download] \(record.itemId) complete, \(bytes / 1_000_000) MB")
        } catch is CancellationError {
            return false
        } catch {
            record.state = .failed
            record.errorMessage = ConnectionState.message(for: error)
            Diagnostics.log("[download] \(record.itemId) failed: \(error)")
        }

        try? await save(record)
        active = nil
        return true
    }

    private func report(_ itemId: String, _ received: Int64, _ total: Int64?) async {
        guard var record = active, record.itemId == itemId else { return }
        record.receivedBytes = received
        record.totalBytes = total
        active = record
        // Deliberately not written to the database on every chunk — that would be
        // thousands of writes per file for a number only the current window shows.
    }

    private func save(_ record: DownloadRecord) async throws {
        try await database.writer.write { db in try record.save(db) }
    }

    /// Hands the transfer to the system rather than counting bytes in Swift.
    ///
    /// See `DownloadTransfer` for why: the loop this replaces consumed
    /// `URLSession.bytes`, an `AsyncSequence` of `UInt8`, one await per byte. It
    /// measured 0.8 MB/s against 213 MB/s here — CPU-bound, so no amount of network
    /// or disk made it faster, and a 2 GB episode took forty-three minutes.
    private func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Int64 {
        var request = URLRequest(url: url)
        for (key, value) in await client.streamingHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await DownloadTransfer().run(
            request: request, to: destination, onProgress: onProgress
        )
    }
}

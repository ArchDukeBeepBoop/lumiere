import Foundation
import GRDB

/// Watch progress made while the server was away, waiting to be told.
///
/// Playing offline already worked and already recorded a position — but only in
/// this cache. The report to Jellyfin was a `try?` that failed silently, so an
/// evening watched away from the server was an evening no other client would know
/// about; and because the next sync overwrites local watch state with the server's,
/// the progress was not merely unshared, it was overwritten by a stale zero.
///
/// One row per item, not per report. Only the newest position for a title is worth
/// sending, so `positionTicks` is overwritten as playback continues and the queue
/// stays the size of the number of things watched, not the number of ten-second
/// ticks. See `LibraryDatabase` migration `v21_playback_outbox`.
public struct PlaybackOutboxRecord: Codable, Sendable, Hashable,
                                    FetchableRecord, PersistableRecord {

    public static let databaseTableName = "playbackOutbox"

    public var itemId: String
    public var positionTicks: Int64
    public var played: Bool
    /// Which file the position is of. Jellyfin's progress endpoint wants it and it
    /// cannot be derived from the cache later.
    public var mediaSourceId: String?
    public var recordedAt: Date

    public init(
        itemId: String,
        positionTicks: Int64,
        played: Bool,
        mediaSourceId: String?,
        recordedAt: Date
    ) {
        self.itemId = itemId
        self.positionTicks = positionTicks
        self.played = played
        self.mediaSourceId = mediaSourceId
        self.recordedAt = recordedAt
    }

    public var positionSeconds: Double { Double(positionTicks) / 10_000_000 }
}

public extension LibraryRepository {

    /// Records that this position has not reached the server.
    ///
    /// Called on the offline path only. Doing it unconditionally would mean a queue
    /// that fills during ordinary online playback and has to be drained behind
    /// reports the server has already accepted — the same work twice, and a window
    /// where a crash replays a position the server knows better than.
    func enqueuePlayback(
        itemId: String,
        positionSeconds: Double,
        played: Bool,
        mediaSourceId: String?
    ) async throws {
        try await database.writer.write { db in
            try PlaybackOutboxRecord(
                itemId: itemId,
                positionTicks: Int64(positionSeconds * 10_000_000),
                played: played,
                mediaSourceId: mediaSourceId,
                recordedAt: Date()
            ).save(db)
        }
    }

    /// Everything waiting, oldest first.
    ///
    /// Oldest first so a title watched twice offline reaches the server in the order
    /// it happened, and the last write is the one that stands.
    func pendingPlayback() async throws -> [PlaybackOutboxRecord] {
        try await database.writer.read { db in
            try PlaybackOutboxRecord
                .order(Column("recordedAt"))
                .fetchAll(db)
        }
    }

    /// Drops one item once the server has taken it.
    ///
    /// By item and by position: if playback carried on while the flush was in
    /// flight, the row has already been overwritten with a newer position and
    /// deleting it would throw that away. Comparing what was sent leaves the newer
    /// row in place for the next pass.
    func clearPendingPlayback(itemId: String, sentTicks: Int64) async throws {
        _ = try await database.writer.write { db in
            try PlaybackOutboxRecord
                .filter(Column("itemId") == itemId)
                .filter(Column("positionTicks") == sentTicks)
                .deleteAll(db)
        }
    }

    /// How many titles are waiting. For the UI, which says so rather than flushing
    /// silently — progress that has not left this Mac is worth knowing about.
    func pendingPlaybackCount() async throws -> Int {
        try await database.writer.read { db in
            try PlaybackOutboxRecord.fetchCount(db)
        }
    }
}

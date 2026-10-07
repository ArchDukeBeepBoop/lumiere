import Foundation
import GRDB

/// How far one file's subtitles are out, remembered for that file alone.
///
/// The distinction this type exists to hold: a subtitle offset is not a setting.
/// It corrects a mismatch between a particular subtitle track and a particular
/// audio track — a fansub timed for a different release, a track that drifts a few
/// frames — and the next episode is a different file with a different track and
/// very often no problem at all. A single number applied everywhere fixes one
/// episode and breaks the rest, so this is keyed by item.
///
/// Zero is not stored. "In sync" is the absence of a correction, not a correction
/// of nothing, and keeping the table to the files that actually needed one means a
/// reset genuinely forgets rather than pinning a zero over some future default.
public struct SubtitleOffset: Codable, Sendable, FetchableRecord, PersistableRecord {

    public static let databaseTableName = "subtitleOffset"

    public var itemId: String
    /// Positive shows subtitles later, negative earlier — mpv's sign convention,
    /// so a number copied from another player means the same thing here.
    public var seconds: Double
    public var updatedAt: Date

    public init(itemId: String, seconds: Double, updatedAt: Date = Date()) {
        self.itemId = itemId
        self.seconds = seconds
        self.updatedAt = updatedAt
    }
}

public extension LibraryRepository {

    /// This file's saved offset, or nil where it never needed one.
    func subtitleOffset(itemId: String) async throws -> Double? {
        try await database.writer.read { db in
            try SubtitleOffset.fetchOne(db, key: itemId)?.seconds
        }
    }

    /// Saves an offset, or forgets it when the file is put back in sync.
    func saveSubtitleOffset(_ seconds: Double, itemId: String) async throws {
        try await database.writer.write { db in
            guard seconds != 0 else {
                _ = try SubtitleOffset.deleteOne(db, key: itemId)
                return
            }
            try SubtitleOffset(itemId: itemId, seconds: seconds).save(db)
        }
    }
}

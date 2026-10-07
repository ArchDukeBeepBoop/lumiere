import Foundation
import GRDB

/// The stored form of a learned intro. See `IntroLearning` for the rules.
public struct IntroSkipRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "introSkip"

    public var seriesId: String
    public var start: Double
    public var end: Double
    public var samples: Int
    public var updatedAt: Date

    public init(seriesId: String, skip: IntroSkip, updatedAt: Date = Date()) {
        self.seriesId = seriesId
        self.start = skip.start
        self.end = skip.end
        self.samples = skip.samples
        self.updatedAt = updatedAt
    }

    public var skip: IntroSkip {
        IntroSkip(start: start, end: end, samples: samples)
    }
}

public extension LibraryRepository {

    /// What has been learned about a series' intro, if anything.
    func learnedIntro(seriesId: String) async throws -> IntroSkip? {
        try await database.writer.read { db in
            try IntroSkipRecord.fetchOne(db, key: seriesId)?.skip
        }
    }

    /// Records one observed skip and returns what is now known.
    ///
    /// Read-modify-write in one transaction: two episodes finishing at once is
    /// not a real case, but a lost sample would silently set the count back and
    /// the offer needs two to appear at all.
    @discardableResult
    func recordIntroSkip(
        seriesId: String, from: Double, to: Double
    ) async throws -> IntroSkip {
        try await database.writer.write { db in
            let known = try IntroSkipRecord.fetchOne(db, key: seriesId)?.skip
            let merged = IntroLearning.merge(known, from: from, to: to)
            try IntroSkipRecord(seriesId: seriesId, skip: merged).save(db)
            return merged
        }
    }

    /// Forgets what was learned about a series.
    func forgetIntro(seriesId: String) async throws {
        _ = try await database.writer.write { db in
            try IntroSkipRecord.deleteOne(db, key: seriesId)
        }
    }
}

import Foundation
import GRDB

/// One offline copy of an item.
public struct DownloadRecord: Codable, Sendable, Identifiable, Hashable,
                              FetchableRecord, PersistableRecord {

    public static let databaseTableName = "download"

    public enum State: String, Codable, Sendable, CaseIterable {
        case queued
        case downloading
        case complete
        case failed
    }

    public var itemId: String
    public var serverId: String
    public var state: State
    /// Absolute path. Stored rather than derived so a file already on disk stays
    /// findable if the naming scheme ever changes.
    public var localPath: String?
    public var totalBytes: Int64?
    public var receivedBytes: Int64
    public var errorMessage: String?
    public var requestedAt: Date
    public var completedAt: Date?

    public var id: String { itemId }

    public init(
        itemId: String,
        serverId: String,
        state: State = .queued,
        localPath: String? = nil,
        totalBytes: Int64? = nil,
        receivedBytes: Int64 = 0,
        errorMessage: String? = nil,
        requestedAt: Date,
        completedAt: Date? = nil
    ) {
        self.itemId = itemId
        self.serverId = serverId
        self.state = state
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.errorMessage = errorMessage
        self.requestedAt = requestedAt
        self.completedAt = completedAt
    }

    /// Nil when the size is not yet known — Jellyfin does not always send
    /// Content-Length for a direct stream, and a progress bar that invents a
    /// denominator lies about how long is left.
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }

    /// Whether the file is actually still there.
    ///
    /// Checked rather than trusted: these live in Application Support, and a user
    /// clearing space or a failed move leaves a row claiming a file that is gone.
    /// A "Downloaded" badge over a missing file is worse than no badge.
    public var isPlayableOffline: Bool {
        guard state == .complete, let localPath else { return false }
        return FileManager.default.fileExists(atPath: localPath)
    }
}

public extension JellyfinClient {
    /// The URL for fetching an item's original file.
    ///
    /// `static=true` is what makes Jellyfin serve the bytes on disk rather than
    /// starting a transcode — the same flag direct play relies on. A download that
    /// quietly transcoded would store a worse copy than the one on the server.
    nonisolated func downloadURL(itemId: String) -> URL {
        session.serverURL
            .appendingPathComponent("Videos/\(itemId)/stream")
            .appending(queryItems: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: itemId),
            ])
    }
}

/// Why a download could not even be attempted.
public enum DownloadError: LocalizedError {
    /// The server's own id for the item is not usable as a filename.
    ///
    /// Its own error rather than a silent skip: an id that fails this check means
    /// the server sent something no Jellyfin server should, and that is worth
    /// saying rather than swallowing.
    case unusableItemId(String)

    public var errorDescription: String? {
        switch self {
        case .unusableItemId:
            return "The server gave this item an id Lumiere will not write to disk."
        }
    }
}

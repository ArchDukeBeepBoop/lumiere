import Foundation

/// Subtitles the library does not have, and making them land on the line.
///
/// The server does both: it holds the provider key, it has ffmpeg, and it
/// can write beside the video. The client asks, shows what came back, and
/// applies the offset the sync found.

/// One subtitle a provider offers.
public struct RemoteSubtitle: Decodable, Sendable, Identifiable, Equatable {
    public let fileId: Int
    public let release: String
    public let language: String
    public let downloads: Int
    public let rating: Double
    public let fromTrusted: Bool
    public let hearingImpaired: Bool
    /// Machine and AI translations read badly. Shown rather than hidden: a
    /// list that quietly includes them is a list that recommends them.
    public let machineTranslated: Bool
    public let aiTranslated: Bool
    public let format: String

    public var id: Int { fileId }

    enum CodingKeys: String, CodingKey {
        case fileId = "FileId", release = "Release", language = "Language"
        case downloads = "Downloads", rating = "Rating", fromTrusted = "FromTrusted"
        case hearingImpaired = "HearingImpaired", machineTranslated = "MachineTranslated"
        case aiTranslated = "AiTranslated", format = "Format"
    }
}

/// What a sync found: how far to shift, and how sure it is.
public struct SubtitleSync: Decodable, Sendable, Equatable {
    public let offset: Double
    public let confidence: Double
    /// Whether the server would act on this without being asked. Below it the
    /// answer is offered rather than applied — a confident wrong shift is
    /// worse than a subtitle left alone.
    public let trusted: Bool

    enum CodingKeys: String, CodingKey {
        case offset = "Offset", confidence = "Confidence", trusted = "Trusted"
    }

    public init(offset: Double, confidence: Double, trusted: Bool) {
        self.offset = offset
        self.confidence = confidence
        self.trusted = trusted
    }
}

/// What the server can do about subtitles at all.
public struct SubtitleCapabilities: Decodable, Sendable, Equatable {
    public let hasKey: Bool
    public let canSync: Bool

    enum CodingKeys: String, CodingKey {
        case hasKey = "HasKey", canSync = "CanSync"
    }

    public init(hasKey: Bool, canSync: Bool) {
        self.hasKey = hasKey
        self.canSync = canSync
    }
}

public extension JellyfinClient {

    func subtitleCapabilities() async throws -> SubtitleCapabilities {
        try await send(SubtitleCapabilities.self, path: "Subtitles/Status")
    }

    func setSubtitleKey(_ key: String) async throws {
        try await sendVoid(
            path: "Subtitles/Key",
            body: try JSONSerialization.data(withJSONObject: ["Key": key])
        )
    }

    func findSubtitles(itemId: String, language: String) async throws -> [RemoteSubtitle] {
        struct Response: Decodable, Sendable { let Results: [RemoteSubtitle] }
        return try await send(
            Response.self, path: "Items/\(itemId)/RemoteSubtitles",
            query: [.init(name: "language", value: language)]
        ).Results
    }

    /// Downloads one, optionally syncing it in the same call — which is the
    /// usual case: a subtitle cut for another release is why you went
    /// looking, and a fetch that does not also check the timing hands you a
    /// file to fix by hand.
    @discardableResult
    func downloadSubtitle(
        itemId: String, fileId: Int, language: String, sync: Bool, maxShiftSeconds: Int = 60
    ) async throws -> DownloadedSubtitle {
        try await send(
            DownloadedSubtitle.self,
            path: "Items/\(itemId)/RemoteSubtitles/\(fileId)",
            method: "POST",
            query: [
                .init(name: "language", value: language),
                .init(name: "sync", value: sync ? "true" : "false"),
                .init(name: "maxShift", value: String(maxShiftSeconds)),
            ]
        )
    }

    /// Aligns a subtitle the library already holds against this file's audio.
    func syncSubtitle(
        itemId: String, index: Int, maxShiftSeconds: Int = 60
    ) async throws -> SubtitleSync {
        try await send(
            SubtitleSync.self,
            path: "Items/\(itemId)/Subtitles/\(index)/Sync",
            method: "POST",
            query: [.init(name: "maxShift", value: String(maxShiftSeconds))]
        )
    }
}

/// The subtitle that was fetched, and where it landed.
public struct DownloadedSubtitle: Decodable, Sendable, Equatable {
    public let index: Int
    public let offset: Double?
    public let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case index = "Index", offset = "Offset", confidence = "Confidence"
    }
}

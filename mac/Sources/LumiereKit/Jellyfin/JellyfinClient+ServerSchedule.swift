import Foundation

/// Lumiere's server: its own settings and background work. A real Jellyfin
/// has none of this and answers 404, which reads as nil.
public struct ServerSchedule: Codable, Sendable, Equatable {
    public var watchedPercent: Int
    public var resumeWeeks: Int
    public var scanEveryHours: Int
    public var quietFrom: Int
    public var quietTo: Int
    public var makesPreviews: Bool
    public var listensOnNetwork: Bool?
    /// Collections made from the movie database's film series, room by room.
    public var autoCollections: Bool?
    public var addresses: [String]?
    /// Home-network devices refused before sign-in.
    public var blockedAddresses: [String]?
    public var previewsMade: Int?
    public var previewsTotal: Int?
    public var working: String?
    public var lastAutoScan: String?
    public var waiting: String?

    enum CodingKeys: String, CodingKey {
        case watchedPercent = "WatchedPercent", resumeWeeks = "ResumeWeeks"
        case scanEveryHours = "ScanEveryHours", quietFrom = "QuietFrom", quietTo = "QuietTo"
        case makesPreviews = "MakesPreviews", previewsMade = "PreviewsMade"
        case previewsTotal = "PreviewsTotal", working = "Working"
        case lastAutoScan = "LastAutoScan", waiting = "Waiting"
        case autoCollections = "AutoCollections", listensOnNetwork = "ListensOnNetwork", addresses = "Addresses"
        case blockedAddresses = "BlockedAddresses"
    }
}

public extension JellyfinClient {
    func serverSchedule() async -> ServerSchedule? {
        try? await send(ServerSchedule.self, path: "Lumiere/Server")
    }

    func setServerSchedule(_ schedule: ServerSchedule) async -> ServerSchedule? {
        guard let body = try? JSONEncoder().encode(schedule) else { return nil }
        return try? await send(ServerSchedule.self, path: "Lumiere/Server", method: "POST", body: body)
    }

    func makePreviewsNow() async {
        try? await sendVoid(path: "Lumiere/Server/Previews", method: "POST")
    }
}

import Foundation

/// One kind of library damage, as the server counts it.
public struct LibraryHealthIssue: Decodable, Sendable, Identifiable, Equatable {
    public let kind: String
    public let count: Int
    public let samples: [Sample]
    /// The count at the server's last nightly snapshot, where it has one.
    public var since: Int? = nil

    public var id: String { kind }

    /// "3 new since yesterday", "2 fewer since yesterday", or nil.
    public var changeSinceYesterday: String? {
        guard let since, since != count else { return nil }
        let delta = count - since
        return delta > 0 ? "\(delta) new since yesterday" : "\(-delta) fewer since yesterday"
    }

    public struct Sample: Decodable, Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let path: String
        /// Pieces that can be dealt with one at a time — a show's seasons.
        public let parts: [Part]?

        enum CodingKeys: String, CodingKey { case id = "ID", name = "Name", path = "Path", parts = "Parts" }
    }

    public struct Part: Decodable, Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        enum CodingKeys: String, CodingKey { case id = "ID", name = "Name" }
    }

    enum CodingKeys: String, CodingKey {
        case kind = "Kind", count = "Count", samples = "Samples", since = "Since"
    }
}

public extension LibraryHealthIssue {
    /// The kinds that went up since `seen`. A count that fell is progress,
    /// not news; a kind never seen before counts from zero.
    static func grown(_ issues: [LibraryHealthIssue], since seen: [String: Int]) -> Set<String> {
        Set(issues.filter { $0.count > (seen[$0.kind] ?? 0) }.map(\.kind))
    }
}

public extension JellyfinClient {
    /// What is wrong with the library. Lumiere's own server only; a Jellyfin
    /// server throws, and the card says there is nothing to show.
    func libraryHealth() async throws -> [LibraryHealthIssue] {
        struct Response: Decodable, Sendable { let Issues: [LibraryHealthIssue] }
        return try await send(Response.self, path: "Library/Health").Issues
    }

    /// Leaves one finding alone from now on (a show, for missing episodes).
    func dismissHealth(kind: String, key: String) async throws {
        try await sendVoid(
            path: "Library/Health/Dismiss",
            body: try JSONSerialization.data(withJSONObject: ["Kind": kind, "Key": key])
        )
    }

    /// Brings every ignored finding back.
    func restoreHealth() async throws {
        try await sendVoid(path: "Library/Health/Restore", method: "POST")
    }

    /// Moves a misfiled episode into its season's folder. Returns the folder.
    func moveMisfiled(itemId: String) async throws -> String {
        struct Moved: Decodable, Sendable { let Folder: String }
        return try await send(
            Moved.self, path: "Library/Health/MoveMisfiled", method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["Id": itemId])
        ).Folder
    }

    /// Moves several misfiled episodes at once; one undo puts them all back.
    func moveMisfiled(itemIds: [String]) async throws -> Int {
        struct Moved: Decodable, Sendable { let Episodes: Int }
        return try await send(
            Moved.self, path: "Library/Health/MoveMisfiled", method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["Ids": itemIds])
        ).Episodes
    }

    /// Puts the last move back.
    func undoMisfiledMove() async throws {
        try await sendVoid(path: "Library/Health/UndoMove", method: "POST")
    }

    /// Takes a frame for every file with no picture, in the background.
    func takeMissingFrames() async throws {
        try await sendVoid(path: "Metadata/Frames", method: "POST")
    }
}

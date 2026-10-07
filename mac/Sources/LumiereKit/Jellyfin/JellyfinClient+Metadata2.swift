import Foundation

/// What the server's own naming pass is doing.
public struct ServerMetadataStatus: Decodable, Sendable, Equatable {
    public let Running: Bool
    public let Named: Int
    public let Missed: Int
    /// Titles with no synopsis and no artwork, waiting to be looked up.
    public let Pending: Int
    public let Current: String?
    public let Error: String?
    /// Whether the server holds a provider key of its own. Without one there is
    /// nothing to run, which is a different message from "nothing to do".
    public let HasKey: Bool

    public init(
        Running: Bool, Named: Int = 0, Missed: Int = 0, Pending: Int = 0,
        Current: String? = nil, Error: String? = nil, HasKey: Bool = false
    ) {
        self.Running = Running
        self.Named = Named
        self.Missed = Missed
        self.Pending = Pending
        self.Current = Current
        self.Error = Error
        self.HasKey = HasKey
    }
}

public extension JellyfinClient {

    func serverMetadataStatus() async throws -> ServerMetadataStatus {
        try await send(ServerMetadataStatus.self, path: "Metadata/Status")
    }

    /// Hands the server a provider key of its own.
    ///
    /// A copy, not a move: Lumiere keeps its own for identify, and the server
    /// needs one to name what it scans with no app open. Two copies of a
    /// credential is a real cost and it is the price of the server being able
    /// to work unattended — which is the whole point of it scanning its own
    /// disk. An empty token clears the server's copy.
    func setServerMetadataKey(_ token: String) async throws {
        try await sendVoid(
            path: "Metadata/Key",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["Token": token])
        )
    }

    /// Names the titles the server has scanned but cannot describe.
    func runServerMetadata() async throws {
        try await sendVoid(path: "Metadata/Run", method: "POST")
    }
}

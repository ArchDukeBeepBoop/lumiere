import Foundation

/// One of the server's own maintenance jobs.
///
/// Only enough of Jellyfin's `TaskInfo` to find a task and say what it is doing.
/// The full shape carries triggers, categories and last-execution records that
/// nothing here has a use for.
public struct ScheduledTask: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let key: String?
    /// "Idle", "Running", "Cancelling".
    public let state: String?
    /// 0–100 while running, absent otherwise.
    public let currentProgressPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case key = "Key"
        case state = "State"
        case currentProgressPercentage = "CurrentProgressPercentage"
    }

    public var isRunning: Bool { state == "Running" }
}

public extension JellyfinClient {

    /// Jellyfin's key for the job that builds scrubbing preview sheets.
    ///
    /// Matched on the key rather than the display name, which is localised.
    static let trickplayTaskKey = "RefreshTrickplayImages"

    func scheduledTasks() async throws -> [ScheduledTask] {
        try await send([ScheduledTask].self, path: "ScheduledTasks")
    }

    /// The trickplay job, if this server has one.
    ///
    /// Absent on Jellyfin before 10.9, which had no trickplay at all — worth
    /// distinguishing from "present and never run", because the two need different
    /// things said to the user.
    func trickplayTask() async throws -> ScheduledTask? {
        try await scheduledTasks().first { $0.key == Self.trickplayTaskKey }
    }

    /// Asks the server to run a task now.
    ///
    /// The generation happens on the server, for every client, which is the whole
    /// reason to do it this way: previews built here would be previews only this Mac
    /// could ever see, and the app's rule is that Jellyfin owns the media.
    func startScheduledTask(id: String) async throws {
        try await sendVoid(path: "ScheduledTasks/Running/\(id)", method: "POST")
    }

    /// Asks the server to look at the disk for media it has not indexed yet.
    ///
    /// The step above everything this app's own sync can do. Lumiere reads what
    /// Jellyfin's index contains, so a file dropped into a watched folder is
    /// invisible here until the server has scanned it — no amount of syncing on this
    /// side can find something the server has not catalogued. Measured on this
    /// library: a show added to disk was absent from the newest 400 items the server
    /// returned, sorted newest first, which is the server saying it does not know
    /// about it.
    ///
    /// Returns nothing and completes immediately: the scan runs on the server, for
    /// as long as it takes, and reports through its own progress rather than here.
    func refreshServerLibrary() async throws {
        try await sendVoid(path: "Library/Refresh", method: "POST")
    }

    /// Whether a server-side scan is still going, and when the last one ended.
    ///
    /// Jellyfin reports this through `/ScheduledTasks`, which is a list of every
    /// task the server has and a shape this app has no other use for. Lumiere's
    /// own server answers a question instead. A server that has neither — an
    /// actual Jellyfin — throws, and the caller falls back to what it always
    /// did: say the scan runs there and stop waiting on it.
    func serverScanStatus() async throws -> ServerScanStatus {
        try await send(ServerScanStatus.self, path: "Library/Refresh/Status")
    }
}

/// What the server's own library scan is doing.
///
/// The server walks the media roots itself now rather than mirroring Jellyfin,
/// so this is a real progress report rather than a flag: which library, how far
/// through, and what has been found. The panel draws it directly.
public struct ServerScanStatus: Decodable, Sendable, Equatable {
    public let Running: Bool
    /// The library being scanned right now. Absent between libraries and when
    /// nothing is running.
    public let Library: String?
    public let Index: Int?
    public let Total: Int?
    /// Media files seen on disk, across the whole pass.
    public let Files: Int
    /// Items the scan added that the library did not have.
    public let Added: Int
    /// Catalogued files no longer on disk. Reported, never deleted — a drive
    /// that failed to mount looks exactly like a library that was emptied.
    public let Missing: Int
    public let Probed: Int
    public let Started: String?
    public let Ended: String?
    /// A library that could not be read at all, usually an unmounted volume.
    public let Error: String?
    /// Episodes whose release links an opening or ending the library does not
    /// hold — they play without it, as they would in VLC, but here it is said.
    public var UnresolvedLinks: Int? = nil
    /// When the server last rewrote rows a client may already hold — a film
    /// folded into a show, a clip unfolded into its folder. An incremental
    /// sync sees new ids only; a stamp newer than the last full read says
    /// there is more to see. See `SyncTrigger.repairedSince`.
    public var RepairedAt: String? = nil
    /// Moves whenever watch state or the catalogue changes on the server, from
    /// any writer. See `AppModel+ChangeWatch`. Nil from older servers.
    public var Changed: String? = nil

    public init(
        Running: Bool, Library: String? = nil, Index: Int? = nil, Total: Int? = nil,
        Files: Int = 0, Added: Int = 0, Missing: Int = 0, Probed: Int = 0,
        Started: String? = nil, Ended: String? = nil, Error: String? = nil,
        UnresolvedLinks: Int = 0
    ) {
        self.UnresolvedLinks = UnresolvedLinks
        self.Running = Running
        self.Library = Library
        self.Index = Index
        self.Total = Total
        self.Files = Files
        self.Added = Added
        self.Missing = Missing
        self.Probed = Probed
        self.Started = Started
        self.Ended = Ended
        self.Error = Error
    }

    /// What a caller waiting on the scan compares against. See `ServerScanWait`.
    public var LastFinished: String? { Ended }
}

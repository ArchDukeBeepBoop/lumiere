import Foundation

/// A library as its owner manages it on Lumiere's server: a name, a kind, and
/// the folders on disk that fill it. See the server's `LibrariesHandler`.
public struct ServerLibrary: Decodable, Sendable, Identifiable, Hashable {
    public struct Folder: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let path: String
        enum CodingKeys: String, CodingKey { case id = "Id", path = "Path" }
    }

    public let id: String
    public let name: String
    public let collectionType: String
    public let folders: [Folder]
    public let itemCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", collectionType = "CollectionType"
        case folders = "Folders", itemCount = "ItemCount"
    }
}

/// The kinds a library can declare, in the order a picker offers them.
public enum LibraryKind: String, CaseIterable, Identifiable, Sendable {
    case movies, tvshows, music, homevideos, mixed
    case folders = ""

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .movies: return "Films"
        case .tvshows: return "TV Shows & Anime"
        case .music: return "Music"
        case .homevideos: return "Home Videos"
        case .mixed: return "Mixed Films & Shows"
        case .folders: return "Plain Folders"
        }
    }

    public var explanation: String {
        switch self {
        case .movies: return "One film per file or folder. Posters, cast and collections are looked up."
        case .tvshows: return "A folder per show, seasons inside. Episodes are matched and named."
        case .music: return "Albums and artists from the files' tags, with lyrics."
        case .homevideos: return "Your own clips, named by their files. Nothing is looked up."
        case .mixed: return "Films and shows side by side in one place."
        case .folders: return "Browse the folders as they are on disk."
        }
    }

    public var icon: String {
        switch self {
        case .movies: return "film"
        case .tvshows: return "tv"
        case .music: return "music.note"
        case .homevideos: return "video"
        case .mixed: return "square.stack"
        case .folders: return "folder"
        }
    }
}

/// One folder on the server's disk, for picking where a library lives from a
/// device that cannot open a picker there.
public struct ServerFolderListing: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable, Identifiable {
        public let name: String
        public let path: String
        public var id: String { path }
        enum CodingKeys: String, CodingKey { case name = "Name", path = "Path" }
    }
    public let path: String
    public let parent: String
    public let folders: [Entry]
    enum CodingKeys: String, CodingKey { case path = "Path", parent = "Parent", folders = "Folders" }
}

public extension JellyfinClient {
    private struct LibraryList: Decodable, Sendable {
        let libraries: [ServerLibrary]
        enum CodingKeys: String, CodingKey { case libraries = "Libraries" }
    }

    private struct Created: Decodable, Sendable {
        let id: String
        enum CodingKeys: String, CodingKey { case id = "Id" }
    }

    func serverLibraries() async throws -> [ServerLibrary] {
        try await send(LibraryList.self, path: "Lumiere/Libraries").libraries
    }

    @discardableResult
    func createLibrary(name: String, kind: LibraryKind, paths: [String]) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "Name": name, "CollectionType": kind.rawValue, "Paths": paths,
        ])
        return try await send(Created.self, path: "Lumiere/Libraries", method: "POST", body: body).id
    }

    func updateLibrary(_ id: String, name: String? = nil, kind: LibraryKind? = nil) async throws {
        var fields: [String: Any] = [:]
        if let name { fields["Name"] = name }
        if let kind { fields["CollectionType"] = kind.rawValue }
        try await sendVoid(path: "Lumiere/Libraries/\(id)", method: "POST",
                           body: try JSONSerialization.data(withJSONObject: fields))
    }

    func removeLibrary(_ id: String) async throws {
        try await sendVoid(path: "Lumiere/Libraries/\(id)", method: "DELETE")
    }

    func addLibraryFolder(_ libraryId: String, path: String) async throws {
        try await sendVoid(path: "Lumiere/Libraries/\(libraryId)/Folders", method: "POST",
                           body: try JSONSerialization.data(withJSONObject: ["Path": path]))
    }

    func removeLibraryFolder(_ libraryId: String, folderId: String) async throws {
        try await sendVoid(path: "Lumiere/Libraries/\(libraryId)/Folders/\(folderId)", method: "DELETE")
    }

    func browseServerFolders(_ path: String = "") async throws -> ServerFolderListing {
        try await send(ServerFolderListing.self, path: "Lumiere/Browse",
                       query: path.isEmpty ? [] : [URLQueryItem(name: "path", value: path)])
    }

    func changePassword(current: String, new: String) async throws {
        try await sendVoid(path: "Lumiere/Account/Password", method: "POST",
                           body: try JSONSerialization.data(withJSONObject: ["Current": current, "New": new]))
    }
}

import Foundation

/// Taking content out of the library.
///
/// Two operations with two words, and they are kept apart on purpose: *remove*
/// leaves the file alone and can be undone from Settings; *delete* sends the
/// file to the Trash. Lumiere's own server is the only one that answers these
/// — see the server's RemovalHandler.
public extension JellyfinClient {

    struct RemovedItem: Decodable, Identifiable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let type: String
        public let path: String?
        public let removedAt: String
        public let members: Int
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", type = "Type", path = "Path"
            case removedAt = "RemovedAt", members = "Members"
        }
    }

    /// Out of the library, file untouched. Cascades to a show's seasons and
    /// episodes.
    func removeFromLibrary(itemId: String) async throws {
        try await sendVoid(path: "Items/\(itemId)", method: "DELETE")
    }

    /// To the Trash, and out of the library. The server refuses on a volume
    /// with no Trash rather than unlinking.
    func deleteToTrash(itemId: String) async throws {
        try await sendVoid(
            path: "Items/\(itemId)", method: "DELETE",
            query: [URLQueryItem(name: "permanent", value: "true")]
        )
    }

    /// Puts back the last Move to Trash, within ten minutes of it. Returns
    /// how many files came back; a scan then re-adds the items.
    @discardableResult
    func untrashLast() async throws -> Int {
        struct Restored: Decodable, Sendable { let Restored: Int }
        return try await send(Restored.self, path: "Items/Untrash", method: "POST").Restored
    }

    func restore(itemId: String) async throws {
        try await sendVoid(path: "Items/\(itemId)/Restore", method: "POST")
    }

    func removedItems() async throws -> [RemovedItem] {
        struct Page: Decodable { let Items: [RemovedItem] }
        return try await send(Page.self, path: "Items/Removed").Items
    }
}

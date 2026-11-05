import Foundation

/// A collection's watch order, shared through Lumiere's server so the Mac, the
/// phone, the TV and the headset agree on what comes next. The Mac's own store
/// (`collectionRank`) stays as the copy used offline; see
/// `LibraryRepository+Ranks.swift` for how the two are kept in step.
private struct WatchOrderBody: Codable, Sendable {
    let items: [String]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

extension JellyfinClient {
    /// The server's arrangement, first to last; nil from a server without the
    /// route (older than shared watch orders), which keeps the Mac's own.
    func watchOrder(collectionId: String) async throws -> [String]? {
        do {
            return try await send(WatchOrderBody.self, path: "Lumiere/WatchOrder/\(collectionId)").items
        } catch JellyfinError.httpError(let status, _) where status == 404 {
            return nil
        }
    }

    func setWatchOrder(collectionId: String, itemIds: [String]) async throws {
        try await sendVoid(path: "Lumiere/WatchOrder/\(collectionId)", method: "PUT",
                           body: try JSONEncoder().encode(WatchOrderBody(items: itemIds)))
    }
}

/// Collections whose arrangement changed here while the server couldn't be
/// told: sent at the next read, so the server's older order never replaces it.
enum WatchOrderPending {
    private static let key = "watchOrderPending"
    static func all() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func mark(_ id: String) { UserDefaults.standard.set(Array(all().union([id])), forKey: key) }
    static func clear(_ id: String) { UserDefaults.standard.set(Array(all().subtracting([id])), forKey: key) }
}

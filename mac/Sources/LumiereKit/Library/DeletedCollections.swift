import Foundation

/// The last collection deleted, so Undo can make it again.
///
/// A collection is its name and its members; everything else — the poster,
/// the order — comes back by itself or is the server's to remake. Only the
/// most recent is held, as every other Undo in the app holds one step.
public actor DeletedCollections {
    public static let shared = DeletedCollections()
    /// The change-feed reason a user's delete is announced with, which the app
    /// answers with the Undo toast.
    public static let reason = "collection deleted by you"

    public struct Snapshot: Sendable {
        public let name: String
        public let itemIds: [String]
    }

    private var last: Snapshot?

    func keep(_ snapshot: Snapshot) { last = snapshot }

    public func take() -> Snapshot? {
        defer { last = nil }
        return last
    }
}

extension LibraryRepository {
    /// Makes the last deleted collection again. Returns its name, or nil.
    public func restoreDeletedCollection() async throws -> String? {
        guard let snap = await DeletedCollections.shared.take() else { return nil }
        _ = try await createCollection(name: snap.name, itemIds: snap.itemIds)
        return snap.name
    }
}

import Foundation
import GRDB

/// The whole of a franchise, in the order it was released.
///
/// A show and its films are separate rows in separate libraries — *Ghost in the
/// Shell* is a series in Anime, four films in Anime Movies and an OVA line, and
/// nothing in the app says they are one thing. So the release order lives in the
/// viewer's head, and the part you have not seen is a search away rather than a
/// glance away.
///
/// Read from the collections that already exist rather than from a new grouping
/// pass: a BoxSet is exactly this statement, the app can already propose them
/// from `FranchiseGrouping`, and inventing a second answer would let the two
/// disagree about what belongs together.
public extension LibraryRepository {

    struct FranchisePart: Sendable, Identifiable {
        public let entry: LibraryEntry
        /// Whether this is the title being looked at.
        public let isCurrent: Bool
        public var id: String { entry.id }
    }

    struct Franchise: Sendable {
        public let name: String
        public let collectionId: String
        public let parts: [FranchisePart]
    }

    /// The franchise an item belongs to, if any.
    ///
    /// Ordered by release, not by name or by the order the collection was built
    /// in: a franchise is a sequence, and the only question its page answers is
    /// what comes next. Items with no year sort last rather than as year zero,
    /// which would put an unscraped OVA before the film that started everything.
    func franchise(for itemId: String) async throws -> Franchise? {
        let memberships: [ItemRecord] = try await database.writer.read { [serverId] db in
            try ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("type") == JellyfinItem.ItemType.boxSet.rawValue)
                .filter(sql: HiddenCollections.filterSQL)
                .fetchAll(db)
        }

        for collection in memberships {
            let members = try await collectionMembers(collectionId: collection.id)
            guard members.contains(where: { $0.id == itemId }) else { continue }
            // A pair is not a franchise. Two titles in a collection is a
            // double bill, and a strip saying so under one of them is noise.
            guard members.count >= 3 else { continue }

            let ordered = members.sorted { left, right in
                let a = left.item.productionYear ?? Int.max
                let b = right.item.productionYear ?? Int.max
                return a == b ? left.item.sortName < right.item.sortName : a < b
            }
            return Franchise(
                name: collection.name,
                collectionId: collection.id,
                parts: ordered.map {
                    FranchisePart(entry: $0, isCurrent: $0.id == itemId)
                }
            )
        }
        return nil
    }

    /// What is inside a collection.
    private func collectionMembers(collectionId: String) async throws -> [LibraryEntry] {
        try await entries(
            parentId: collectionId,
            types: LibraryRepository.topLevelTypes,
            sort: .releaseDate,
            limit: 100
        )
    }
}

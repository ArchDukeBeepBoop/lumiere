import Foundation

extension FranchiseGrouping {

    /// A proposed collection — a new one, or titles for one that exists.
    public struct Group: Sendable, Identifiable, Hashable {
        public init(
            name: String, itemIds: [String], reason: String,
            existingCollectionId: String? = nil, tmdbCollectionId: String? = nil,
            missing: [String] = [], isStrong: Bool = false
        ) {
            self.name = name
            self.itemIds = itemIds
            self.reason = reason
            self.existingCollectionId = existingCollectionId
            self.tmdbCollectionId = tmdbCollectionId
            self.missing = missing
            self.isStrong = isStrong
        }

        /// The metadata key the group was built from — "Fate", "Gen Urobuchi".
        public let name: String
        public let itemIds: [String]
        /// Shown next to the proposal so a wrong grouping is obvious before it is
        /// accepted rather than after. A suggestion nobody can check is a guess.
        public let reason: String
        /// Set when the titles belong in a collection that already exists:
        /// accepting adds them to it rather than making a second one.
        public let existingCollectionId: String?
        /// The movie database's film series, remembered on the collection so
        /// later passes recognise it.
        public let tmdbCollectionId: String?
        /// Films in the series this library does not have, "Alien³ (1992)".
        public let missing: [String]
        /// An exact source rather than an inference. Strong groups start ticked;
        /// the rest start unticked, to be checked before accepting.
        public let isStrong: Bool

        public var id: String { name + "|" + itemIds.joined(separator: ",") }
    }
}

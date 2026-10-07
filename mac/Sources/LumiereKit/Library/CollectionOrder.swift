import Foundation

/// The orders a collection's contents can be read in.
///
/// A collection is a viewing plan as much as a group, and which order it should be
/// in depends on what kind of plan it is. A franchise wants release order; a
/// long-running one often wants the order someone actually recommends watching it
/// in, which is neither alphabetical nor chronological.
///
/// Pure, so the ordering is testable without a database or a view.
public enum CollectionOrder: String, Sendable, CaseIterable, Identifiable {
    /// The order the collection itself holds, as arranged on the server. The
    /// default, because a hand-built collection's order is a decision someone
    /// already made and re-sorting it would throw that away.
    case manual
    case name
    case releaseDate
    case dateAdded
    case rating
    /// Release order, but with each series' entries kept together.
    ///
    /// What people mean by "watch order" far more often than a strict timeline: a
    /// franchise's TV run followed by its films, rather than a film from the middle
    /// of season two arriving between episodes. Films that belong to no series fall
    /// in by their own release date.
    case watchOrder
    /// The order you arranged yourself.
    ///
    /// Distinct from `.manual`, which is the server's arrangement of the BoxSet and
    /// the same for everyone using it. This one is local and personal: where *you*
    /// think a series belongs in the row, which for a franchise watched in a
    /// recommended order is the only ordering that is actually right.
    case personal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: return "Collection Order"
        case .name: return "Name"
        case .releaseDate: return "Year Released"
        case .dateAdded: return "Date Added"
        case .rating: return "Rating"
        case .watchOrder: return "Recommended Watch Order"
        case .personal: return "My Watch Order"
        }
    }

    /// - Parameter ranks: the personal arrangement, keyed by item id. Only
    ///   `.personal` reads it; every other order ignores it entirely.
    public static func sorted(
        _ entries: [LibraryEntry], by order: CollectionOrder, ranks: [String: Int] = [:]
    ) -> [LibraryEntry] {
        switch order {
        case .manual:
            return entries
        case .personal:
            // Anything not yet placed goes to the end in release order rather than
            // to the front. A title added to the collection last week has no
            // opinion attached to it, and dropping it in at position one would put
            // it ahead of an arrangement someone made deliberately.
            let ranked = entries.filter { ranks[$0.id] != nil }
                .sorted { (ranks[$0.id] ?? 0) < (ranks[$1.id] ?? 0) }
            let unranked = sorted(entries.filter { ranks[$0.id] == nil }, by: .releaseDate)
            return ranked + unranked
        case .name:
            return entries.sorted {
                $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
            }
        case .releaseDate:
            // Undated titles go last rather than to 1970: a missing year is unknown,
            // not ancient, and sorting them to the front buries everything real.
            return entries.sorted { left, right in
                switch (left.item.productionYear, right.item.productionYear) {
                case let (l?, r?): return l == r ? byName(left, right) : l < r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return byName(left, right)
                }
            }
        case .dateAdded:
            return entries.sorted { left, right in
                switch (left.item.dateCreated, right.item.dateCreated) {
                case let (l?, r?): return l > r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return byName(left, right)
                }
            }
        case .rating:
            return entries.sorted {
                ($0.item.communityRating ?? -1) > ($1.item.communityRating ?? -1)
            }
        case .watchOrder:
            return watchOrdered(entries)
        }
    }

    /// Release order, with a series' own entries held together.
    ///
    /// Each series is anchored at its earliest entry, so a franchise's parts stay
    /// adjacent and the groups themselves run oldest first. Standalone films sort
    /// among them by their own year — which is what makes this a watch order rather
    /// than a grouping.
    private static func watchOrdered(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        /// A group is a series and everything filed under it; anything else is its
        /// own group of one.
        var groups: [String: [LibraryEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let key = entry.item.seriesId ?? entry.item.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }

        var anchored: [(anchor: Int, name: String, items: [LibraryEntry])] = []
        for key in order {
            let items = groups[key] ?? []
            let anchor = items.compactMap { $0.item.productionYear }.min() ?? Int.max
            anchored.append((anchor, items.first?.item.name ?? "", items))
        }

        anchored.sort { left, right in
            if left.anchor != right.anchor { return left.anchor < right.anchor }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }

        // Inside a group, release order again — a series' own parts run oldest
        // first, then by name where they share a year.
        var result: [LibraryEntry] = []
        for group in anchored {
            result.append(contentsOf: sorted(group.items, by: .releaseDate))
        }
        return result
    }

    private static func byName(_ left: LibraryEntry, _ right: LibraryEntry) -> Bool {
        left.item.name.localizedStandardCompare(right.item.name) == .orderedAscending
    }
}

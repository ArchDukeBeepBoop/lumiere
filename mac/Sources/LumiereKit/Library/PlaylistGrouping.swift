import Foundation

/// One line in a playlist: a plain item, or a series standing in for several of
/// its episodes.
public enum PlaylistRow: Identifiable, Sendable {
    case item(LibraryEntry)
    case series(id: String, name: String, episodes: [LibraryEntry])

    public var id: String {
        switch self {
        case .item(let entry): return entry.id
        case .series(let id, _, _): return "series:\(id)"
        }
    }
}

/// Folds a playlist's episodes up under the shows they came from.
///
/// A playlist holding a whole season is 24 rows that all say the same series name
/// and differ only in a number — unreadable, and not what someone means when they
/// add a show to a playlist.
///
/// A series contributing exactly *one* episode is deliberately left alone. That is
/// the case where the episode was the point: someone picked that specific one, and
/// burying it under a series heading would hide the very thing they chose.
///
/// Pure, so the rule can be tested without a server or a view — the project keeps
/// its classification logic that way.
public enum PlaylistGrouping {

    public static func rows(for entries: [LibraryEntry]) -> [PlaylistRow] {
        var counts: [String: Int] = [:]
        for entry in entries {
            if let seriesId = entry.item.seriesId { counts[seriesId, default: 0] += 1 }
        }

        var rows: [PlaylistRow] = []
        var groupedAt: [String: Int] = [:]

        for entry in entries {
            guard let seriesId = entry.item.seriesId, counts[seriesId, default: 0] > 1 else {
                rows.append(.item(entry))
                continue
            }
            if let index = groupedAt[seriesId] {
                if case .series(let id, let name, var episodes) = rows[index] {
                    episodes.append(entry)
                    rows[index] = .series(id: id, name: name, episodes: episodes)
                }
            } else {
                // Position is the series' *first* appearance. A playlist is a
                // sequence, and re-ordering it would destroy the only thing it
                // actually encodes.
                groupedAt[seriesId] = rows.count
                rows.append(.series(
                    id: seriesId,
                    name: entry.item.seriesName ?? entry.item.name,
                    episodes: [entry]
                ))
            }
        }
        return rows
    }
}

import Foundation

/// The line of facts under a title, chosen by what the title is.
///
/// A film, a series and an anime were all drawn with the same line — year, or a
/// season count, or nothing — because one function served all three. They are not
/// read the same way. Deciding on a film you want the runtime and who made it;
/// deciding on a series you want to know how much is left; deciding on an anime
/// you want the studio, because in that library the studio is most of the
/// judgement.
///
/// Pure, so each variant can be checked against the facts it claims. The policy
/// question — *is this library anime* — is answered at the edge by
/// `LibraryKinds`, and arrives here as a flag.
public enum MetadataLine {

    public enum Kind: Sendable, Equatable {
        case film
        case series
        case anime
    }

    /// Which line to draw.
    ///
    /// The library decides anime, not the item: a show does not know what shelf
    /// it is on, and a title-based guess would call every series with a Japanese
    /// name anime and miss every one without.
    public static func kind(for item: ItemRecord, isAnimeLibrary: Bool) -> Kind {
        if isAnimeLibrary { return .anime }
        switch item.itemType {
        case .series, .season, .episode: return .series
        default: return .film
        }
    }

    /// The parts of the line, already in order. Empty where there is nothing
    /// worth saying — a caller draws nothing rather than an empty separator.
    public static func parts(
        for entry: LibraryEntry,
        kind: Kind,
        director: String? = nil,
        studio: String? = nil
    ) -> [String] {
        switch kind {
        case .film:
            return film(entry, director: director)
        case .series:
            return series(entry)
        case .anime:
            return anime(entry, studio: studio)
        }
    }

    public static func line(
        for entry: LibraryEntry,
        kind: Kind,
        director: String? = nil,
        studio: String? = nil
    ) -> String? {
        let parts = parts(for: entry, kind: kind, director: director, studio: studio)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - The three lines

    /// `1982 · 1 hr 57 · Ridley Scott`
    static func film(_ entry: LibraryEntry, director: String?) -> [String] {
        var parts: [String] = []
        if let year = entry.item.productionYear { parts.append(String(year)) }
        if let runtime = runtimeText(entry.item.runtimeSeconds) { parts.append(runtime) }
        if let director, !director.isEmpty { parts.append(director) }
        return parts
    }

    /// `2008 · 5 seasons · 12 unwatched`
    ///
    /// The unwatched count is the part that earns its place: it is the only fact
    /// here that changes, and the only one that answers "where am I".
    static func series(_ entry: LibraryEntry) -> [String] {
        var parts: [String] = []
        if let year = entry.item.productionYear { parts.append(String(year)) }
        if let seasons = entry.item.childCount, seasons > 0 {
            parts.append("\(seasons) season\(seasons == 1 ? "" : "s")")
        }
        if let unwatched = entry.userData?.unplayedItemCount, unwatched > 0 {
            parts.append("\(unwatched) unwatched")
        }
        return parts
    }

    /// `Bones · 2019 · 2 seasons · 6 unwatched`
    ///
    /// Studio first, deliberately. In an anime library it is the strongest
    /// signal about whether you will like something, and it is the one the
    /// existing line never showed at all.
    static func anime(_ entry: LibraryEntry, studio: String?) -> [String] {
        var parts: [String] = []
        if let studio, !studio.isEmpty { parts.append(studio) }
        if entry.item.itemType == .movie {
            if let year = entry.item.productionYear { parts.append(String(year)) }
            if let runtime = runtimeText(entry.item.runtimeSeconds) { parts.append(runtime) }
            return parts
        }
        if let year = entry.item.productionYear { parts.append(String(year)) }
        if let seasons = entry.item.childCount, seasons > 0 {
            parts.append("\(seasons) season\(seasons == 1 ? "" : "s")")
        }
        if let unwatched = entry.userData?.unplayedItemCount, unwatched > 0 {
            parts.append("\(unwatched) unwatched")
        }
        return parts
    }

    // MARK: - Cards

    /// The same judgement, at card length.
    ///
    /// A tile has one muted line of perhaps thirty characters under the title,
    /// so the page's full line does not fit — but the *choice* of what matters
    /// is the same choice, and making it twice is how the two drift apart. This
    /// keeps at most two facts: the one that identifies the title, and the one
    /// that changes.
    ///
    /// Cards drew `TitleFormatter.subtitle` for every kind of thing: a year for
    /// a film, a season count for a series, and a year for an anime — which is
    /// the least useful fact about it.
    public static func cardLine(
        for entry: LibraryEntry, kind: Kind, studio: String? = nil
    ) -> String? {
        var parts: [String] = []
        switch kind {
        case .film:
            if let year = entry.item.productionYear { parts.append(String(year)) }
            if let runtime = runtimeText(entry.item.runtimeSeconds) {
                parts.append(runtime)
            }
        case .series:
            if let seasons = entry.item.childCount, seasons > 0 {
                parts.append("\(seasons) season\(seasons == 1 ? "" : "s")")
            } else if let year = entry.item.productionYear {
                parts.append(String(year))
            }
            if let unwatched = entry.userData?.unplayedItemCount, unwatched > 0 {
                parts.append("\(unwatched) unwatched")
            }
        case .anime:
            // Studio first and, on a tile, often alone: in this library it is
            // the fact that decides whether you look further.
            if let studio, !studio.isEmpty { parts.append(studio) }
            if entry.item.itemType == .movie {
                if parts.isEmpty, let year = entry.item.productionYear {
                    parts.append(String(year))
                }
            } else if let unwatched = entry.userData?.unplayedItemCount, unwatched > 0 {
                parts.append("\(unwatched) unwatched")
            } else if let seasons = entry.item.childCount, seasons > 0 {
                parts.append("\(seasons) season\(seasons == 1 ? "" : "s")")
            }
        }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " · ")
    }

    /// The first studio named on a record, which is the one worth showing.
    ///
    /// `ItemRecord.studios` is newline-joined for the grid's filter; a tile has
    /// room for one name, and the first is the production house rather than the
    /// licensors that follow it.
    public static func primaryStudio(_ record: ItemRecord) -> String? {
        record.studios?.split(separator: "\n").first.map(String.init)
    }

    // MARK: - Phrasing

    /// `1 hr 57`, `48 min`. Never `0 min`, and never a bare number of minutes
    /// for something feature length — "117 min" is arithmetic, not information.
    public static func runtimeText(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 60 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest)"
    }

}

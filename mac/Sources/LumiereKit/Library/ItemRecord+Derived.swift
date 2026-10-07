import Foundation

/// What a cached row means, as opposed to what it stores.
///
/// Split from ItemRecord.swift for the project's 300-line rule. Everything here is
/// derived from columns rather than written to them: the typed item kind, the
/// newline-joined lists unpacked back into arrays, and the sort key the writer
/// computes on the way in.
public extension ItemRecord {

    var itemType: JellyfinItem.ItemType {
        JellyfinItem.ItemType(rawValue: type) ?? .unknown
    }

    /// Everyone credited on the track, falling back to the album's artist. A track
    /// with neither returns nothing rather than an empty string, so the row can
    /// leave the column out instead of printing a gap.
    var artistList: [String] {
        if let artists, !artists.isEmpty {
            return artists.components(separatedBy: "\n")
        }
        return [albumArtist].compactMap { $0 }.filter { !$0.isEmpty }
    }

    var genreList: [String] {
        guard let genres, !genres.isEmpty else { return [] }
        return genres.components(separatedBy: "\n")
    }

    var runtimeSeconds: Double? {
        guard let runTimeTicks, runTimeTicks > 0 else { return nil }
        return Double(runTimeTicks) / 10_000_000
    }

    /// Sorting key that matches what a person expects: leading articles ignored,
    /// case-insensitive, and episodes ordered by season then episode number
    /// rather than by title.
    static func sortKey(for item: JellyfinItem) -> String {
        if item.type == .episode {
            let season = item.parentIndexNumber ?? 0
            let episode = item.indexNumber ?? 0
            return String(format: "%04d%04d", season, episode)
        }
        return normalizedTitle(item.name)
    }

    static func normalizedTitle(_ title: String) -> String {
        let lowered = title.lowercased()
        for article in ["the ", "a ", "an "] where lowered.hasPrefix(article) {
            return String(lowered.dropFirst(article.count))
        }
        return lowered
    }
}

public extension ItemRecord {

    /// Carries `contentDate` across a rebuild of this row.
    ///
    /// `contentDate` is *derived*, not reported. For a series it is the date of its
    /// newest episode, which only `refreshContentDates` can work out — nothing in a
    /// server payload knows it — so rebuilding a row from JSON resets it to the
    /// series folder's own scan date and flattens the Latest shelf back to the order
    /// this column exists to replace.
    ///
    /// The sync's own pages are followed by a refresh, so they recover. Nothing else
    /// is: `cache(items:)` alone has nine callers — search results, similar titles,
    /// collection members, a series' episodes, a person's filmography — and every
    /// one of them writes series rows whenever you browse. Opening a search result
    /// was enough to undo the ranking for that show until the next sync.
    ///
    /// Only series carry it. For everything else `contentDate` *is* `dateCreated`,
    /// so the freshly reported value is the authoritative one and keeping the old one
    /// would be the bug instead.
    ///
    /// This is the same class of column as `libraryId` and `parentId`, which every
    /// write path already carries by hand for the same reason.
    mutating func carryContentDate(from existing: ItemRecord?) {
        guard type == JellyfinItem.ItemType.series.rawValue,
              let carried = existing?.contentDate else { return }
        contentDate = carried
    }
}

public extension ItemRecord {

    /// Sets `dateCreated` and the `contentDate` that shadows it.
    ///
    /// Exists because assigning `dateCreated` alone is silently wrong, and was, in
    /// two places: the initializer derives `contentDate` from the date the payload
    /// carried, so every later `record.dateCreated = x` left `contentDate` behind —
    /// nil on every row the local-folder scanner writes, and the wrong instant on
    /// every demo fixture. A row with a nil `contentDate` sorts last for ever,
    /// which on a Latest shelf means never appearing at all.
    ///
    /// Series are refined afterwards by `refreshContentDates`; for everything else
    /// the two are the same value by definition, which is what this keeps true.
    mutating func setDateCreated(_ date: Date?) {
        dateCreated = date
        contentDate = date
    }

    /// The studio to name in a metadata line: the first, not all of them.
    ///
    /// A line is one fact per slot. "Bones, Aniplex, TV Tokyo" is a credits
    /// list, and the one anybody recognises is the first.
    var primaryStudio: String? {
        guard let studios, !studios.isEmpty else { return nil }
        return studios.components(separatedBy: "\n").first
    }
}

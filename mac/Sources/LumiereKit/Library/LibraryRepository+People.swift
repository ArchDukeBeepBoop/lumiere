import Foundation

/// "What else is this person in?", answered by the server.
///
/// Deliberately not a cache query. `ItemRecord` has no people column and no join
/// table — the cast arrives inside a single item's `.detail` payload and is read
/// straight onto the page — so the only rows the cache could match against are the
/// handful of items whose detail pages happen to have been opened. Asking the
/// server with `PersonIds` is the difference between "three films you already
/// looked at" and the actual filmography.
///
/// The results still land in the cache on the way through (`page(from:)` calls
/// `cache(items:)`), so a card opened from a person page has its row locally and
/// the detail page it pushes to renders without a spinner, exactly like a card
/// opened from anywhere else.
public extension LibraryRepository {

    /// One window of the titles a person is credited on.
    ///
    /// `types` is the caller's, because a person page asks two different questions
    /// with the same query: films and series make a poster wall, episodes make a
    /// per-show strip, and the two want different sorts as well as different cards.
    func personAppearancesPage(
        personId: String,
        types: [JellyfinItem.ItemType],
        sortBy: [String] = ["SortName"],
        sortOrder: JellyfinClient.SortOrder = .ascending,
        offset: Int = 0,
        limit: Int = 60
    ) async throws -> MusicPage {
        let response = try await client.items(
            types: types,
            recursive: true,
            sortBy: sortBy,
            sortOrder: sortOrder,
            startIndex: offset,
            limit: limit,
            personIds: [personId]
        )
        return try await page(from: response)
    }

    /// Films and series, newest first.
    ///
    /// Release order rather than alphabetical, and descending: a filmography is
    /// read as a career, and the thing you are most likely to be looking for after
    /// recognising a face is the recent work. `SortName` is the tiebreak so titles
    /// sharing a year — and everything the server has no premiere date for, which
    /// sorts as one large clump — still come out in a stable order rather than
    /// shuffling between pages.
    func personTitlesPage(
        personId: String, offset: Int = 0, limit: Int = 60
    ) async throws -> MusicPage {
        try await personAppearancesPage(
            personId: personId,
            types: [.movie, .series],
            sortBy: ["PremiereDate", "SortName"],
            sortOrder: .descending,
            offset: offset,
            limit: limit
        )
    }

    /// Episode appearances, with each show's episodes contiguous and in order.
    ///
    /// `SeriesSortName` first is what makes the grouping on the page cheap and
    /// correct across pages: the client only ever appends, so as long as the server
    /// keeps a show's episodes together, a group can never be reopened by a later
    /// window. Then season and episode number, ascending — a guest run reads in
    /// broadcast order, not by title.
    func personEpisodesPage(
        personId: String, offset: Int = 0, limit: Int = 60
    ) async throws -> MusicPage {
        try await personAppearancesPage(
            personId: personId,
            types: [.episode],
            sortBy: ["SeriesSortName", "ParentIndexNumber", "IndexNumber"],
            sortOrder: .ascending,
            offset: offset,
            limit: limit
        )
    }
}

import Foundation
import GRDB

/// How a list is ordered.
///
/// Split from LibraryRepository.swift for the project's 300-line rule.
public extension LibraryRepository {

    enum Sort: String, Sendable, CaseIterable {
        case title
        case dateAdded
        case releaseDate
        case rating
        case runtime
        /// How much of it has been watched — a collection's or a show's share
        /// of titles seen, a film's watched or not. See `order(_:descending:)`.
        case watched
        /// Newest *content*, not newest row — a series ranks by its newest episode.
        ///
        /// What the home screen's Latest shelves use, and deliberately not offered
        /// in the grid's sort menu: in a grid "Date Added" is a fact about the title
        /// you are looking at, while on a shelf called Latest it is a claim about
        /// what is new to watch. See the `v18_content_date` migration.
        case latestContent

        var column: String {
            switch self {
            case .title: return "sortName"
            case .dateAdded: return "dateCreated"
            case .latestContent: return "contentDate"
            case .releaseDate: return "premiereDate"
            case .rating: return "communityRating"
            case .runtime: return "runTimeTicks"
            case .watched: return "childCount"
            }
        }

        /// Newest-first and highest-rated-first are what people mean by those
        /// sorts; alphabetical is the only one that ascends by default.
        public var defaultDescending: Bool {
            self != .title
        }

        /// The sorts a person can pick. `latestContent` is not one of them — it is
        /// what a shelf named "Latest" means, not a column anybody asks for.
        public static var userSelectable: [Sort] {
            allCases.filter { $0 != .latestContent }
        }
    }

    /// How much of each row to read.
    ///
    /// A grid holds every row it has paged in, and `ItemRecord` is forty columns
    /// wide — `overview` alone is most of a paragraph per row. Measured on the real
    /// Anime library, fully paged: **51.7 MB at 2,174 bytes a row for `SELECT *`,
    /// against 12.3 MB at 516 bytes for the columns a tile actually reads.** That is
    /// reachable in one gesture, not by patient scrolling: tapping Z on the A–Z rail
    /// pages all 24,938 rows in.
    ///
    /// No second record type and nothing rethreaded through the views: GRDB decodes
    /// an absent column as nil for an optional property, verified against the real
    /// database before this was written, so a narrowed row is an ordinary
    /// `ItemRecord` with the fields nobody drew left empty.
    /// Applies the sort. Most are one column; `watched` is a share, computed
    /// from the member count and the unwatched count the server sends.
    static func order(
        _ request: QueryInterfaceRequest<ItemRecord>, by sort: Sort, descending: Bool
    ) -> QueryInterfaceRequest<ItemRecord> {
        guard sort == .watched else {
            let column = Column(sort.column)
            return request.order(descending ? column.desc : column.asc)
        }
        let share = """
            (CASE WHEN COALESCE(item.childCount, 0) > 0 THEN
                (item.childCount - COALESCE((SELECT u.unplayedItemCount FROM userData u WHERE u.itemId = item.id), item.childCount)) * 1.0 / item.childCount
             ELSE COALESCE((SELECT u.played FROM userData u WHERE u.itemId = item.id), 0) END)
            """
        return request.order(sql: share + (descending ? " DESC" : " ASC") + ", item.sortName")
    }

    enum Projection: Sendable {
        /// Every column. What a detail page and anything that edits a row needs.
        case full
        /// What a tile and its context menu read.
        case tile

        /// `path` is in the list deliberately. It is not drawn, but Identify builds
        /// its search query from it and the "Original filename" title style *is* it,
        /// so dropping it would break two things quietly rather than loudly.
        static let tileColumns = [
            "id", "serverId", "type", "name", "sortName", "searchKey", "isFolder",
            "syncedAt", "seriesId", "seriesName", "seasonId", "primaryTag",
            "backdropTag", "thumbTag", "seriesPrimaryImageTag",
            "parentBackdropItemId", "parentBackdropTag", "productionYear",
            "runTimeTicks", "indexNumber", "parentIndexNumber", "childCount",
            "path", "extraType",
        ]
    }
}

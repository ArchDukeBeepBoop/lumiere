import Foundation

extension JellyfinClient {

    // `Sendable`: now crosses an actor boundary (repository to client).
    public enum SortOrder: String, Sendable {
        case ascending = "Ascending"
        case descending = "Descending"
    }

    // MARK: - Libraries

    /// The user's libraries — Movies, TV Shows, and so on.
    public func userViews() async throws -> [JellyfinItem] {
        let response = try await send(
            ItemsResponse.self,
            path: "UserViews",
            query: [URLQueryItem(name: "userId", value: session.userId)]
        )
        return response.items
    }

    // MARK: - Items

    public func items(
        parentId: String? = nil,
        types: [JellyfinItem.ItemType] = [],
        recursive: Bool = true,
        sortBy: [String] = ["SortName"],
        sortOrder: SortOrder = .ascending,
        startIndex: Int = 0,
        limit: Int = 100,
        searchTerm: String? = nil,
        filters: [String] = [],
        genres: [String] = [],
        years: [Int] = [],
        personIds: [String] = [],  // see LibraryRepository+People.swift
        ids: [String] = [],  // see LibraryRepository+ChangeFeed.swift
        fields: FieldSet = .list
    ) async throws -> ItemsResponse {
        var query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false"),
            URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ",")),
            URLQueryItem(name: "SortOrder", value: sortOrder.rawValue),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: fields.value),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            // Ask for exactly the artwork the grid renders. Without this the
            // server returns every image type it has, which bloats the payload.
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
        ]

        if let parentId { query.append(.init(name: "ParentId", value: parentId)) }
        if !types.isEmpty {
            query.append(.init(name: "IncludeItemTypes",
                               value: types.map(\.rawValue).joined(separator: ",")))
        }
        if let searchTerm, !searchTerm.isEmpty {
            query.append(.init(name: "SearchTerm", value: searchTerm))
        }
        if !filters.isEmpty {
            query.append(.init(name: "Filters", value: filters.joined(separator: ",")))
        }
        if !genres.isEmpty {
            query.append(.init(name: "Genres", value: genres.joined(separator: "|")))
        }
        if !years.isEmpty {
            query.append(.init(name: "Years", value: years.map(String.init).joined(separator: ",")))
        }
        // Comma, not the pipe `Genres` needs for names that contain one.
        if !ids.isEmpty {
            query.append(.init(name: "Ids", value: ids.joined(separator: ",")))
        }
        if !personIds.isEmpty {
            query.append(.init(name: "PersonIds", value: personIds.joined(separator: ",")))
        }

        return try await send(ItemsResponse.self, path: "Items", query: query)
    }

    /// A single item with everything the detail page needs.
    public func item(id: String) async throws -> JellyfinItem {
        try await send(
            JellyfinItem.self,
            path: "Users/\(session.userId)/Items/\(id)",
            query: [URLQueryItem(name: "Fields", value: FieldSet.detail.value)]
        )
    }

    // MARK: - Home shelves

    /// Partly-watched items, newest first. This is what the hero backdrop shows.
    public func resumeItems(limit: Int = 20) async throws -> [JellyfinItem] {
        let response = try await send(
            ItemsResponse.self,
            path: "UserItems/Resume",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
                URLQueryItem(name: "MediaTypes", value: "Video"),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
            ]
        )
        return response.items
    }

    /// The next unwatched episode of every series in progress, or of one series
    /// when `seriesId` is given.
    ///
    /// Filtering server-side rather than fetching everything and searching locally:
    /// this is how a series detail page finds which season and episode to open to,
    /// and that has to account for watch state on every device, not just this cache.
    public func nextUp(seriesId: String? = nil, limit: Int = 20) async throws -> [JellyfinItem] {
        var query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: FieldSet.list.value),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
        ]
        if let seriesId {
            query.append(URLQueryItem(name: "SeriesId", value: seriesId))
        }
        let response = try await send(
            ItemsResponse.self,
            path: "Shows/NextUp",
            query: query
        )
        return response.items
    }

    /// Recently added. Note this endpoint returns a bare array, not an `ItemsResponse`.
    public func latestItems(parentId: String? = nil, limit: Int = 20) async throws -> [JellyfinItem] {
        var query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: FieldSet.list.value),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
        ]
        if let parentId { query.append(.init(name: "ParentId", value: parentId)) }
        return try await send([JellyfinItem].self, path: "Items/Latest", query: query)
    }

    // MARK: - Series structure

    public func seasons(seriesId: String) async throws -> [JellyfinItem] {
        let response = try await send(
            ItemsResponse.self,
            path: "Shows/\(seriesId)/Seasons",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
            ]
        )
        return response.items
    }

    public func episodes(seriesId: String, seasonId: String? = nil) async throws -> [JellyfinItem] {
        var query = [
            URLQueryItem(name: "userId", value: session.userId),
            URLQueryItem(name: "Fields", value: FieldSet.list.value),
        ]
        if let seasonId { query.append(.init(name: "seasonId", value: seasonId)) }
        let response = try await send(
            ItemsResponse.self, path: "Shows/\(seriesId)/Episodes", query: query
        )
        return response.items
    }

    public func similar(to itemId: String, limit: Int = 12) async throws -> [JellyfinItem] {
        let response = try await send(
            ItemsResponse.self,
            path: "Items/\(itemId)/Similar",
            query: [
                URLQueryItem(name: "userId", value: session.userId),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: FieldSet.list.value),
            ]
        )
        return response.items
    }

    // MARK: - Watch state

    public func markPlayed(itemId: String, played: Bool) async throws {
        try await sendVoid(
            path: "UserPlayedItems/\(itemId)",
            method: played ? "POST" : "DELETE",
            query: [URLQueryItem(name: "userId", value: session.userId)]
        )
    }

    public func markFavorite(itemId: String, favorite: Bool) async throws {
        try await sendVoid(
            path: "UserFavoriteItems/\(itemId)",
            method: favorite ? "POST" : "DELETE",
            query: [URLQueryItem(name: "userId", value: session.userId)]
        )
    }
}

public extension JellyfinClient {
    /// An item's extras: trailers, featurettes, behind-the-scenes, deleted scenes.
    ///
    /// A separate endpoint because a recursive `/Items` query does not return them —
    /// which is why the ExtraType column came back empty on 40,000 rows. Extras are
    /// attached to a title rather than living in the library, so they have to be
    /// asked for per item, which is also why they are fetched when a detail page
    /// opens rather than during the library sync.
    func specialFeatures(itemId: String) async throws -> [JellyfinItem] {
        try await send(
            [JellyfinItem].self,
            path: "Users/\(session.userId)/Items/\(itemId)/SpecialFeatures"
        )
    }
}

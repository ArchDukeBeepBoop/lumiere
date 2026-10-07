import Foundation

/// One artwork option offered by the server's own metadata providers.
public struct RemoteImageOption: Decodable, Sendable, Identifiable, Hashable {
    public let providerName: String?
    public let url: String?
    public let type: String?
    public let width: Int?
    public let height: Int?
    public let communityRating: Double?
    public let language: String?

    public var id: String { url ?? UUID().uuidString }

    public var dimensions: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }

    enum CodingKeys: String, CodingKey {
        case providerName = "ProviderName", url = "Url", type = "Type"
        case width = "Width", height = "Height"
        case communityRating = "CommunityRating", language = "Language"
    }
}

private struct RemoteImageResponse: Decodable {
    let images: [RemoteImageOption]?
    enum CodingKeys: String, CodingKey { case images = "Images" }
}

/// Metadata refresh, through the server's providers rather than our own.
///
/// This is the whole design: Jellyfin already holds whatever provider credentials it
/// is configured with, so asking *it* to re-scrape needs no API key here and keeps
/// the project's rule intact — Jellyfin stays the only metadata source and Lumiere
/// never talks to TMDB or anyone else directly. It also means a refresh benefits
/// every other client on the server, not just this one.
public extension JellyfinClient {

    /// Applies a hand-made edit to an item and locks it against future refreshes.
    ///
    /// Reads the item's raw JSON, changes only the keys being edited, and posts the
    /// whole object back — which is what Jellyfin's own web client does, and what
    /// `POST /Items/{id}` requires: the endpoint replaces the item rather than
    /// patching it, so anything absent from the payload is cleared.
    ///
    /// Needs an administrator account. Jellyfin gates item editing behind elevated
    /// permissions, so an ordinary user gets 401 or 403 here however the request is
    /// formed — worth surfacing as itself rather than as "something went wrong".
    func updateItem(itemId: String, edit: ItemEdit) async throws {
        let data = try await sendData(
            path: "Users/\(session.userId)/Items/\(itemId)",
            query: [URLQueryItem(name: "Fields", value: FieldSet.detail.value)]
        )
        guard let current = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JellyfinError.httpError(status: 0, body: "The item did not decode as an object.")
        }

        try await sendVoid(
            path: "Items/\(itemId)",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: edit.applied(to: current))
        )
    }

    /// The lyrics the server holds for a track, as plain text.
    ///
    /// Jellyfin gained a lyrics endpoint in 10.9 and older servers answer 404, which
    /// is not an error worth surfacing — it means "this server has no lyrics
    /// support", and a track with no lyrics answers the same way.
    func lyrics(itemId: String) async throws -> String? {
        // Synced lyrics come back as LRC, so an edit keeps their timing; saving
        // flattened text would quietly unsync the file beside the track.
        guard let lines = await lyricLines(itemId: itemId) else { return nil }
        let text = LyricLine.lrc(lines)
        return text.isEmpty ? nil : text
    }

    /// Uploads lyrics for a track, as a .lrc or .txt payload.
    ///
    /// The content is whatever the user supplies — a file they already have. This
    /// app never generates or fetches lyrics itself.
    func uploadLyrics(itemId: String, text: String, format: String = "txt") async throws {
        try await sendVoid(
            path: "Audio/\(itemId)/Lyrics",
            method: "POST",
            query: [URLQueryItem(name: "fileName", value: "lyrics.\(format)")],
            body: Data(text.utf8),
            contentType: "text/plain"
        )
    }

    /// Asks the server to re-scrape this item.
    ///
    /// `replaceAllMetadata` is deliberately false by default: a refresh should fill
    /// gaps, not overwrite corrections the user has already made by hand.
    func refreshMetadata(
        itemId: String,
        replaceAllMetadata: Bool = false,
        replaceAllImages: Bool = false
    ) async throws {
        try await sendVoid(
            path: "Items/\(itemId)/Refresh",
            method: "POST",
            query: [
                URLQueryItem(name: "metadataRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "imageRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "replaceAllMetadata", value: replaceAllMetadata ? "true" : "false"),
                URLQueryItem(name: "replaceAllImages", value: replaceAllImages ? "true" : "false"),
            ]
        )
    }

    /// Artwork the server's providers can offer for this item.
    func remoteImages(itemId: String, type: String = "Primary") async throws -> [RemoteImageOption] {
        let response = try await send(
            RemoteImageResponse.self,
            path: "Items/\(itemId)/RemoteImages",
            query: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "includeAllLanguages", value: "true"),
            ]
        )
        return response.images ?? []
    }

    /// Applies one of those options as the item's image.
    func applyRemoteImage(itemId: String, url: String, type: String = "Primary") async throws {
        try await sendVoid(
            path: "Items/\(itemId)/RemoteImages/Download",
            method: "POST",
            query: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "imageUrl", value: url),
            ]
        )
    }

    /// Deletes an item's image of one type, leaving no image at all.
    ///
    /// Replacing was the only thing on offer before, and it is not the same act.
    /// A wrong poster you overwrite is still there if the next scrape prefers the
    /// original; a wrong poster you delete is gone, and the item shows the app's
    /// generated fallback until you choose something. That distinction is the whole
    /// difference between "I fixed this" and "I fixed this until Sunday".
    ///
    /// Deleting alone does not keep it deleted. Jellyfin will happily re-download
    /// on the next image refresh unless the item is locked — which is why the
    /// picker offers the lock in the same breath.
    func deleteImage(itemId: String, type: String) async throws {
        try await sendVoid(path: "Items/\(itemId)/Images/\(type)", method: "DELETE")
    }

    /// Uploads a file from this Mac as an item's artwork — for the case no
    /// provider has the right image at all, which is common for a Thumb: most
    /// scrapers never populate one, only Primary and Backdrop.
    ///
    /// Jellyfin's image endpoint is a documented quirk: the body is the image
    /// bytes *base64-encoded* rather than raw binary, with Content-Type set to the
    /// real image mime type rather than to the encoding actually on the wire.
    /// Every Jellyfin client does this the same way; it is not this app improvising.
    func uploadImage(itemId: String, type: String, data: Data, mimeType: String) async throws {
        try await sendVoid(
            path: "Items/\(itemId)/Images/\(type)",
            method: "POST",
            body: data.base64EncodedData(),
            contentType: mimeType
        )
    }
}

public extension JellyfinClient {
    /// Tells the server which title an item really is, then lets it scrape.
    ///
    /// This is the design decision that matters. Lumiere never imports metadata
    /// itself: it finds the right provider id and posts it here, and Jellyfin does the
    /// fetching with its own providers. The correction lands in the server's database,
    /// so every other client sees it, and this app never maintains a second divergent
    /// copy of metadata for the same library.
    ///
    /// `RemoteSearch/Apply` normally takes a result Jellyfin produced itself, but a
    /// hand-built one carrying only ProviderIds is enough — the ids are the part it
    /// acts on.
    func applyProviderMatch(
        itemId: String,
        providerKey: String,
        providerId: String,
        name: String,
        year: Int?,
        posterURL: URL? = nil,
        /// Anything else the server should know about the match — for a
        /// season, which season of that show it is (`TmdbSeason`).
        extraProviderIds: [String: String] = [:]
    ) async throws {
        // Through the same call as a server-side match, rather than a second POST
        // to the same endpoint. It is not tidiness: that endpoint needs a long
        // timeout and needs a dropped connection verified rather than reported as a
        // failure, and a copy here would have needed the fix applied twice — or, as
        // it was, once.
        //
        // Replace, because the point of identifying is that what is there now is
        // wrong; filling gaps would leave the bad title in place.
        try await applyRemoteSearchResult(
            itemId: itemId,
            result: RemoteSearchResult(
                name: name,
                productionYear: year,
                // The poster the search already found. It was being dropped here,
                // so identifying by hand fixed the title and left the wrong
                // picture above it — on a server that scrapes for itself that
                // corrected itself moments later, and on one that does not it
                // simply stayed wrong.
                imageURL: posterURL?.absoluteString,
                providerIds: [providerKey: providerId].merging(extraProviderIds) { _, new in new }
            )
        )
    }
}

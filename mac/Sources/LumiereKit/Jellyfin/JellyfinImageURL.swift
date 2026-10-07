import Foundation

/// Builds artwork URLs.
///
/// Pure and static so it can be unit-tested without a server, and so the image
/// pipeline can construct URLs without touching the client actor on every cell.
///
/// The `maxWidth` parameter is doing real work: Jellyfin resizes server-side, so
/// asking for a 300px-wide poster means downloading ~30 KB instead of ~800 KB.
/// Combined with downsampled decoding, that is most of the RAM story.
public enum JellyfinImageURL {

    public enum ImageKind: String, Sendable {
        case primary = "Primary"
        case backdrop = "Backdrop"
        case thumb = "Thumb"
        case logo = "Logo"
        case banner = "Banner"
    }

    /// - Parameters:
    ///   - maxWidth: on-screen width in *pixels*, already multiplied by screen scale.
    ///   - tag: the image tag from the item. Passing it makes the URL content-addressed,
    ///     so a changed poster busts the cache and an unchanged one stays cached forever.
    public static func url(
        serverURL: URL,
        itemId: String,
        kind: ImageKind,
        tag: String?,
        maxWidth: Int?,
        index: Int? = nil,
        quality: Int = 90
    ) -> URL? {
        var path = "Items/\(itemId)/Images/\(kind.rawValue)"
        if let index { path += "/\(index)" }

        guard var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        var query: [URLQueryItem] = []
        if let tag { query.append(.init(name: "tag", value: tag)) }
        if let maxWidth { query.append(.init(name: "maxWidth", value: String(maxWidth))) }
        query.append(.init(name: "quality", value: String(quality)))
        components.queryItems = query

        return components.url
    }

    /// A cache key that changes when the artwork changes but not when the layout
    /// does — the decode size is part of it, so a poster and a thumbnail of the
    /// same image are separate entries rather than one being resized twice.
    public static func cacheKey(
        itemId: String,
        kind: ImageKind,
        tag: String?,
        maxWidth: Int?
    ) -> String {
        "\(itemId)|\(kind.rawValue)|\(tag ?? "none")|\(maxWidth.map(String.init) ?? "full")"
    }
}

extension JellyfinItem {

    /// The best poster for this item, falling back to the series poster for
    /// episodes so a grid never shows a hole.
    public func posterSource() -> (itemId: String, tag: String?)? {
        if let tag = imageTags?["Primary"] {
            return (id, tag)
        }
        if let seriesId, let tag = seriesPrimaryImageTag {
            return (seriesId, tag)
        }
        return nil
    }

    /// The best wide image, used for episode cards and the hero backdrop.
    /// Order matters: an episode's own Thumb/Primary beats the series backdrop.
    public func backdropSource() -> (itemId: String, kind: JellyfinImageURL.ImageKind, tag: String?)? {
        if let tag = backdropImageTags?.first {
            return (id, .backdrop, tag)
        }
        if let tag = imageTags?["Thumb"] {
            return (id, .thumb, tag)
        }
        if type == .episode, let tag = imageTags?["Primary"] {
            return (id, .primary, tag)
        }
        if let parentId = parentBackdropItemId, let tag = parentBackdropImageTags?.first {
            return (parentId, .backdrop, tag)
        }
        return nil
    }

    public func logoSource() -> (itemId: String, tag: String)? {
        if let tag = imageTags?["Logo"] { return (id, tag) }
        return nil
    }

    /// "S2 E4" for episodes, the year for films, nil when neither applies.
    public var subtitleLine: String? {
        switch type {
        case .episode:
            return EpisodeCode.text(season: parentIndexNumber, episode: indexNumber) ?? seriesName
        case .movie:
            return productionYear.map(String.init)
        case .season:
            return name
        default:
            return productionYear.map(String.init)
        }
    }

    /// What a shelf card shows as its main label. Episodes lead with the series
    /// name, because a row of episode titles with no context is unreadable.
    public var displayTitle: String {
        if type == .episode, let seriesName { return seriesName }
        return name
    }
}

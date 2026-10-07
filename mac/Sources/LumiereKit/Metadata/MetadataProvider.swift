import Foundation

/// A third-party metadata source the user has supplied credentials for.
///
/// This reverses the project's original rule that Jellyfin is the only metadata
/// source. Worth stating why, because the rule existed for a reason: Jellyfin already
/// holds provider credentials and scrapes with them, so anything fetched server-side
/// benefits every client and needs no key here. A key entered in Lumiere only helps
/// where the server cannot or will not do the lookup — a real gap for anime, where
/// matching is often wrong and re-identifying by hand is the only fix.
///
/// So these are for *client-driven identification*, not for replacing the server's
/// scraping. Nothing fetches metadata behind the server's back.
public enum MetadataProvider: String, CaseIterable, Sendable, Identifiable {
    case tmdb
    case tvdb
    case myAnimeList
    case imdb

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tmdb: return "TMDB"
        case .tvdb: return "TheTVDB"
        case .myAnimeList: return "MyAnimeList"
        case .imdb: return "IMDb"
        }
    }

    /// Named as the provider names it. A field labelled "API key" when the site calls
    /// it a read access token wastes the user's time.
    public var credentialLabel: String {
        switch self {
        case .tmdb: return "API Read Access Token"
        case .tvdb: return "API Key"
        case .myAnimeList: return "Client ID"
        case .imdb: return "API Key"
        }
    }

    public var helpText: String {
        switch self {
        case .tmdb:
            return "themoviedb.org › Settings › API. The v4 read access token, not the v3 key."
        case .tvdb:
            return "thetvdb.com › Dashboard › API keys. A v4 key; some plans also need a PIN."
        case .myAnimeList:
            return "myanimelist.net › Preferences › API. The Client ID of a registered app."
        case .imdb:
            // IMDb itself publishes no search API. OMDb is a free, independent service
            // built on IMDb's own data and ids, which is the closest legitimate stand-in
            // — the same trade every other "IMDb integration" out there makes.
            return "omdbapi.com/apikey.aspx — a free key. IMDb has no public search API "
                 + "of its own; this is the closest legitimate substitute."
        }
    }

    /// The single host this provider may reach.
    ///
    /// Listed explicitly rather than derived, so the set of external hosts the app can
    /// contact stays auditable — until now it was exactly one, the user's own server.
    public var host: String {
        switch self {
        case .tmdb: return "api.themoviedb.org"
        case .tvdb: return "api4.thetvdb.com"
        case .myAnimeList: return "api.myanimelist.net"
        case .imdb: return "www.omdbapi.com"
        }
    }
}

/// Provider credentials, beside the Jellyfin token.
///
/// Moved out of the Keychain with it, and the same trade applies — see `TokenStore`
/// for what that costs and why. A third-party key is the user's property, so it gets
/// exactly the handling the session token gets: a file only its owner can read.
public enum MetadataCredentials {

    public static func store(_ key: String, for provider: MetadataProvider) throws {
        try TokenStore.store(key, account: "metadata.\(provider.rawValue)")
    }

    public static func key(for provider: MetadataProvider) -> String? {
        TokenStore.value(account: "metadata.\(provider.rawValue)")
    }

    /// Whether a key exists, without reading it back.
    public static func hasKey(for provider: MetadataProvider) -> Bool {
        key(for: provider) != nil
    }

    @discardableResult
    public static func delete(_ provider: MetadataProvider) -> Bool {
        TokenStore.delete(account: "metadata.\(provider.rawValue)")
    }
}

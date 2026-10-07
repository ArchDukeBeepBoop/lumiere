import Foundation

/// The headers the media engines need, which fetch outside this URLSession.
///
/// Split from JellyfinClient.swift for the project's 300-line rule.
public extension JellyfinClient {

    /// The headers a media URL needs when handed to AVPlayer or mpv, which fetch
    /// outside this URLSession.
    ///
    /// `X-Emby-Token` rather than the full `MediaBrowser` value, and the reason is
    /// mpv: `--http-header-fields` is a *comma-separated list*, and the MediaBrowser
    /// scheme is itself comma-separated, so one header arrived as four fragments and
    /// the server answered 400. mpv's documented `%length%` escape does not rescue
    /// it — an escaped value goes out as a header literally named `%185%Authorization`
    /// and is rejected just the same, which is verifiable from the mpv CLI.
    ///
    /// This header carries only the token, contains no commas, and Jellyfin accepts
    /// it as equivalent. It also keeps the token out of the URL, so it stays out of
    /// the server's access log — which is why this is a header at all.
    var streamingHeaders: [String: String] {
        // Through `accessToken` rather than the stored property: the token is
        // private to JellyfinClient.swift, and moving this out for the line limit
        // should not widen it.
        ["X-Emby-Token": Self.headerSafeValue(accessToken)]
    }
}

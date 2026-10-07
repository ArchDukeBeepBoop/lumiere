import Foundation

/// Turns a decision into a URL.
///
/// Pure, so the URL a given decision produces is unit-testable without a server.
/// Credentials are never placed in the query string — every engine here can send
/// an `Authorization` header, and a token in a URL ends up in server logs,
/// shell history and screenshots.
public enum StreamBuilder {

    public struct Stream: Sendable, Equatable {
        public let url: URL
        public let headers: [String: String]
        /// Nil for direct play: the file is already what it is.
        public let playSessionId: String?

        public init(url: URL, headers: [String: String], playSessionId: String?) {
            self.url = url
            self.headers = headers
            self.playSessionId = playSessionId
        }
    }

    public static func stream(
        for decision: PlaybackDecision,
        serverURL: URL,
        itemId: String,
        mediaSourceId: String,
        playSessionId: String?,
        headers: [String: String],
        maxBitrate: Int? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) -> Stream? {
        let url: URL?
        switch decision.route {
        case .directPlay:
            url = directPlayURL(
                serverURL: serverURL, itemId: itemId,
                mediaSourceId: mediaSourceId, playSessionId: playSessionId
            )
        case .remux:
            url = remuxURL(
                serverURL: serverURL, itemId: itemId,
                mediaSourceId: mediaSourceId, playSessionId: playSessionId,
                audioStreamIndex: audioStreamIndex
            )
        case .transcode:
            url = transcodeURL(
                serverURL: serverURL, itemId: itemId,
                mediaSourceId: mediaSourceId, playSessionId: playSessionId,
                maxBitrate: maxBitrate,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )
        }

        guard let url else { return nil }
        return Stream(url: url, headers: headers, playSessionId: playSessionId)
    }

    /// A playable URL for one audio track.
    ///
    /// `Audio/{id}/universal` rather than the video path and the decision engine
    /// behind it: the server picks a container this client can take and copies the
    /// stream whenever it already can, which for music is nearly always. Music has
    /// none of the things that make video playback a *decision* — no subtitle
    /// burn-in, no HDR tone mapping, no 40 GB remux — so putting it through that
    /// machinery would be ceremony for no gain.
    ///
    /// The container list is what AVFoundation opens natively; anything outside it
    /// the server transcodes down to AAC.
    /// - Note: no credential here, and the parameter is gone rather than ignored so
    ///   it cannot creep back. The token goes in `X-Emby-Token` via
    ///   `AVURLAssetHTTPHeaderFieldsKey`, which is what the video path has always
    ///   done — the comment that used to sit here claimed AVPlayer could not send
    ///   headers, and `AVPlayerEngine` two files over disproves it.
    ///
    ///   It mattered: a token in the query string is written to the server's access
    ///   log and to any proxy log in front of it, and on a plain-HTTP LAN server it
    ///   crosses the wire in clear text on every track. Jellyfin tokens do not
    ///   expire on their own.
    public static func audioStreamURL(
        serverURL: URL,
        itemId: String,
        deviceId: String
    ) -> URL? {
        url(
            serverURL: serverURL,
            path: "Audio/\(itemId)/universal",
            query: [
                URLQueryItem(name: "container", value: "mp3,aac,m4a,m4b,flac,alac,wav"),
                URLQueryItem(name: "audioCodec", value: "aac"),
                URLQueryItem(name: "deviceId", value: deviceId),
            ]
        )
    }

    /// The original bytes. `static=true` is what makes Jellyfin's dashboard say
    /// "Direct Play" and its CPU stay flat.
    static func directPlayURL(
        serverURL: URL, itemId: String, mediaSourceId: String, playSessionId: String?
    ) -> URL? {
        var query = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
        ]
        if let playSessionId {
            query.append(.init(name: "playSessionId", value: playSessionId))
        }
        return url(serverURL: serverURL, path: "Videos/\(itemId)/stream", query: query)
    }

    /// Same streams, new container. The server copies rather than re-encodes, so
    /// its CPU stays near idle even though the dashboard says "Direct Stream".
    static func remuxURL(
        serverURL: URL, itemId: String, mediaSourceId: String,
        playSessionId: String?, audioStreamIndex: Int?
    ) -> URL? {
        var query = [
            URLQueryItem(name: "static", value: "false"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "videoCodec", value: "copy"),
            URLQueryItem(name: "audioCodec", value: "copy"),
        ]
        if let playSessionId { query.append(.init(name: "playSessionId", value: playSessionId)) }
        if let audioStreamIndex {
            query.append(.init(name: "audioStreamIndex", value: String(audioStreamIndex)))
        }
        return url(serverURL: serverURL, path: "Videos/\(itemId)/stream.mp4", query: query)
    }

    /// HLS, re-encoded by the server. The path that should almost never be taken.
    static func transcodeURL(
        serverURL: URL, itemId: String, mediaSourceId: String, playSessionId: String?,
        maxBitrate: Int?, audioStreamIndex: Int?, subtitleStreamIndex: Int?
    ) -> URL? {
        var query = [
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            // H.264 and AAC rather than anything cleverer: this path exists to
            // work, not to be efficient, and every decoder takes these.
            URLQueryItem(name: "videoCodec", value: "h264"),
            URLQueryItem(name: "audioCodec", value: "aac"),
            URLQueryItem(name: "transcodingContainer", value: "ts"),
            URLQueryItem(name: "transcodingProtocol", value: "hls"),
        ]
        if let playSessionId { query.append(.init(name: "playSessionId", value: playSessionId)) }
        if let maxBitrate {
            query.append(.init(name: "maxStreamingBitrate", value: String(maxBitrate)))
            query.append(.init(name: "videoBitRate", value: String(maxBitrate)))
        }
        if let audioStreamIndex {
            query.append(.init(name: "audioStreamIndex", value: String(audioStreamIndex)))
        }
        if let subtitleStreamIndex {
            query.append(.init(name: "subtitleStreamIndex", value: String(subtitleStreamIndex)))
            // Burned in, because a transcode is already the fallback path and
            // client-side rendering of a bitmap track would defeat the point.
            query.append(.init(name: "subtitleMethod", value: "Encode"))
        }
        return url(serverURL: serverURL, path: "Videos/\(itemId)/main.m3u8", query: query)
    }

    /// An external subtitle file, for tracks the server stores separately.
    public static func subtitleURL(
        serverURL: URL, itemId: String, mediaSourceId: String,
        streamIndex: Int, format: String = "srt"
    ) -> URL? {
        url(
            serverURL: serverURL,
            path: "Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/Stream.\(format)",
            query: []
        )
    }

    /// The direct URL of another file, for a linked segment. Always direct:
    /// mpv reads the borrowed file's header and ranges itself, and a remux
    /// would rewrite the segment UID it is looking for.
    public static func linkedFileURL(serverURL: URL, itemId: String) -> URL? {
        directPlayURL(
            serverURL: serverURL, itemId: itemId, mediaSourceId: itemId, playSessionId: nil
        )
    }

    private static func url(serverURL: URL, path: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(
            url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        ) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }
}

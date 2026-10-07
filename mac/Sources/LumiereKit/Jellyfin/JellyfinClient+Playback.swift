import Foundation

/// The server's answer about how an item can be played, plus the session id that
/// every subsequent progress report must carry.
public struct PlaybackInfoResponse: Codable, Sendable {
    public let mediaSources: [MediaSource]
    public let playSessionId: String?
    public let errorCode: String?

    public enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
        case errorCode = "ErrorCode"
    }
}

extension JellyfinClient {

    /// Opens a playback session.
    ///
    /// Lumiere sends a device profile claiming direct play for everything, because
    /// mpv genuinely can take it. Jellyfin uses the profile to decide whether to
    /// offer a transcode; understating our capability here is exactly how other
    /// clients end up cooking a server for no reason.
    public func playbackInfo(
        itemId: String,
        mediaSourceId: String? = nil,
        maxBitrate: Int? = nil
    ) async throws -> PlaybackInfoResponse {
        var body: [String: Any] = [
            "UserId": session.userId,
            "DeviceProfile": Self.permissiveDeviceProfile,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "AllowVideoStreamCopy": true,
            "AllowAudioStreamCopy": true,
            "AutoOpenLiveStream": true,
        ]
        if let mediaSourceId { body["MediaSourceId"] = mediaSourceId }
        if let maxBitrate { body["MaxStreamingBitrate"] = maxBitrate }

        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(
            PlaybackInfoResponse.self,
            path: "Items/\(itemId)/PlaybackInfo",
            method: "POST",
            query: [URLQueryItem(name: "userId", value: session.userId)],
            body: data
        )
    }

    /// A profile that says yes to everything, because with mpv behind us it is
    /// true. The real gate is `PlaybackPlanner`, on the client, where it can be
    /// tested.
    /// Built per call rather than stored: `[String: Any]` is not Sendable, and a
    /// shared static of it is a genuine data race, not a technicality.
    static var permissiveDeviceProfile: [String: Any] { [
        "MaxStreamingBitrate": 400_000_000,
        "MaxStaticBitrate": 400_000_000,
        "MusicStreamingTranscodingBitrate": 384_000,
        "DirectPlayProfiles": [
            [
                "Container": "mp4,m4v,mkv,mov,avi,ts,m2ts,webm,flv,wmv,ogv,3gp",
                "Type": "Video",
                "VideoCodec": "h264,hevc,av1,vp8,vp9,mpeg2video,vc1,mpeg4,theora",
                "AudioCodec": "aac,ac3,eac3,dts,dtshd,truehd,flac,alac,mp3,opus,vorbis,pcm",
            ],
            [
                "Container": "mp3,flac,m4a,ogg,opus,wav,aac",
                "Type": "Audio",
            ],
        ],
        "TranscodingProfiles": [
            [
                "Container": "ts",
                "Type": "Video",
                "VideoCodec": "h264",
                "AudioCodec": "aac",
                "Protocol": "hls",
                "Context": "Streaming",
                "MaxAudioChannels": "6",
            ],
        ],
        "SubtitleProfiles": [
            ["Format": "srt", "Method": "External"],
            ["Format": "ass", "Method": "Embed"],
            ["Format": "ssa", "Method": "Embed"],
            ["Format": "pgssub", "Method": "Embed"],
            ["Format": "subrip", "Method": "Embed"],
            ["Format": "vtt", "Method": "External"],
        ],
        "CodecProfiles": [],
        "ContainerProfiles": [],
    ] }

    // MARK: - Progress reporting

    /// Tells the server playback has started. Without this the item never appears
    /// as "now playing" and the server cannot resume it elsewhere.
    public func reportPlaybackStart(
        itemId: String,
        mediaSourceId: String,
        playSessionId: String?,
        positionSeconds: Double
    ) async throws {
        try await postPlayState(
            path: "Sessions/Playing",
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionSeconds: positionSeconds,
            isPaused: false,
            eventName: nil
        )
    }

    public func reportPlaybackProgress(
        itemId: String,
        mediaSourceId: String,
        playSessionId: String?,
        positionSeconds: Double,
        isPaused: Bool,
        eventName: String? = "timeupdate"
    ) async throws {
        try await postPlayState(
            path: "Sessions/Playing/Progress",
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionSeconds: positionSeconds,
            isPaused: isPaused,
            eventName: eventName
        )
    }

    /// The important one: this is what writes your resume position. It runs on
    /// stop, on window close, and on quit — losing it means losing your place.
    public func reportPlaybackStopped(
        itemId: String,
        mediaSourceId: String,
        playSessionId: String?,
        positionSeconds: Double
    ) async throws {
        var body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
            "PositionTicks": Int64(max(0, positionSeconds) * 10_000_000),
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }

        try await sendVoid(
            path: "Sessions/Playing/Stopped",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    private func postPlayState(
        path: String,
        itemId: String,
        mediaSourceId: String,
        playSessionId: String?,
        positionSeconds: Double,
        isPaused: Bool,
        eventName: String?
    ) async throws {
        var body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
            "PositionTicks": Int64(max(0, positionSeconds) * 10_000_000),
            "IsPaused": isPaused,
            "IsMuted": false,
            "CanSeek": true,
            "PlayMethod": "DirectPlay",
            "RepeatMode": "RepeatNone",
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }
        if let eventName { body["EventName"] = eventName }

        try await sendVoid(
            path: path,
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }
}

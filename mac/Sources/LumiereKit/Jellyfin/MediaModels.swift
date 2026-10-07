import Foundation

/// One playable file behind an item. A movie can have several — 4K and 1080p
/// versions of the same title — which is why the detail page needs a version picker.
public struct MediaSource: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let name: String?
    public let path: String?
    public let container: String?
    public let size: Int64?
    public let bitrate: Int?
    public let runTimeTicks: Int64?
    public let mediaStreams: [MediaStream]?

    /// What the *server* thinks is possible. Lumiere largely ignores these:
    /// Jellyfin computes them from the device profile we send, and our real
    /// capability is mpv, which is broader than any profile can express.
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let supportsTranscoding: Bool?
    public let transcodingUrl: String?
    public let transcodingSubProtocol: String?

    public enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", path = "Path", container = "Container"
        case size = "Size", bitrate = "Bitrate", runTimeTicks = "RunTimeTicks"
        case mediaStreams = "MediaStreams"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case transcodingSubProtocol = "TranscodingSubProtocol"
    }

    public var videoStream: MediaStream? {
        mediaStreams?.first { $0.type == .video }
    }

    public var audioStreams: [MediaStream] {
        mediaStreams?.filter { $0.type == .audio } ?? []
    }

    public var subtitleStreams: [MediaStream] {
        mediaStreams?.filter { $0.type == .subtitle } ?? []
    }

    public var defaultAudioStream: MediaStream? {
        audioStreams.first { $0.isDefault == true } ?? audioStreams.first
    }
}

/// A single video, audio, or subtitle track. This is the raw material
/// `PlaybackDecision` reasons over, so every field it needs lives here.
public struct MediaStream: Codable, Sendable, Hashable, Identifiable {

    public let index: Int
    public let type: StreamType
    public let codec: String?
    public let language: String?
    public let title: String?
    public let displayTitle: String?
    public let isDefault: Bool?
    public let isForced: Bool?
    public let isExternal: Bool?

    // Video
    public let width: Int?
    public let height: Int?
    public let bitDepth: Int?
    public let videoRange: String?
    public let videoRangeType: String?
    public let videoDoViTitle: String?
    public let dvProfile: Int?
    public let dvLevel: Int?
    public let profile: Int?
    public let averageFrameRate: Double?
    public let realFrameRate: Double?

    // Audio
    public let channels: Int?
    public let sampleRate: Int?
    public let channelLayout: String?

    public let bitRate: Int?

    public var id: Int { index }

    public enum CodingKeys: String, CodingKey {
        case index = "Index", type = "Type", codec = "Codec", language = "Language"
        case title = "Title", displayTitle = "DisplayTitle"
        case isDefault = "IsDefault", isForced = "IsForced", isExternal = "IsExternal"
        case width = "Width", height = "Height", bitDepth = "BitDepth"
        case videoRange = "VideoRange", videoRangeType = "VideoRangeType"
        case videoDoViTitle = "VideoDoViTitle"
        case dvProfile = "DvProfile", dvLevel = "DvLevel"
        case profile = "Profile"
        case averageFrameRate = "AverageFrameRate", realFrameRate = "RealFrameRate"
        case channels = "Channels", sampleRate = "SampleRate", channelLayout = "ChannelLayout"
        case bitRate = "BitRate"
    }

    public enum StreamType: String, Codable, Sendable {
        case video = "Video"
        case audio = "Audio"
        case subtitle = "Subtitle"
        case embeddedImage = "EmbeddedImage"
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = StreamType(rawValue: raw) ?? .unknown
        }
    }

    /// Jellyfin reports `Profile` for video as a string on some versions and an
    /// int on others, and `DvProfile` is absent entirely on older servers. This
    /// decoder tolerates both rather than failing the item.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? -1
        type = try c.decodeIfPresent(StreamType.self, forKey: .type) ?? .unknown
        codec = try c.decodeIfPresent(String.self, forKey: .codec)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault)
        isForced = try c.decodeIfPresent(Bool.self, forKey: .isForced)
        isExternal = try c.decodeIfPresent(Bool.self, forKey: .isExternal)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth)
        videoRange = try c.decodeIfPresent(String.self, forKey: .videoRange)
        videoRangeType = try c.decodeIfPresent(String.self, forKey: .videoRangeType)
        videoDoViTitle = try c.decodeIfPresent(String.self, forKey: .videoDoViTitle)
        dvProfile = try c.decodeIfPresent(Int.self, forKey: .dvProfile)
        dvLevel = try c.decodeIfPresent(Int.self, forKey: .dvLevel)
        averageFrameRate = try c.decodeIfPresent(Double.self, forKey: .averageFrameRate)
        realFrameRate = try c.decodeIfPresent(Double.self, forKey: .realFrameRate)
        channels = try c.decodeIfPresent(Int.self, forKey: .channels)
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate)
        channelLayout = try c.decodeIfPresent(String.self, forKey: .channelLayout)
        bitRate = try c.decodeIfPresent(Int.self, forKey: .bitRate)

        if let intProfile = try? c.decodeIfPresent(Int.self, forKey: .profile) {
            profile = intProfile
        } else if let stringProfile = try? c.decodeIfPresent(String.self, forKey: .profile) {
            profile = Int(stringProfile)
        } else {
            profile = nil
        }
    }
}

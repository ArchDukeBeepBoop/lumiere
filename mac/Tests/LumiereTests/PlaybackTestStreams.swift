import Foundation
import TestKit
import LumiereKit

// Stream fixtures shared by the playback decision tests. Split out for the
// 300-line rule.
// MARK: - Builders

@MainActor
func decodeStream(_ json: [String: Any]) -> MediaStream {
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JellyfinClient.decoder.decode(MediaStream.self, from: data)
}

@MainActor
func video(
    codec: String?, bitDepth: Int? = 8, range: String? = nil,
    dvProfile: Int? = nil, width: Int = 1920, height: Int = 1080
) -> MediaStream {
    var json: [String: Any] = ["Index": 0, "Type": "Video", "Width": width, "Height": height]
    if let codec { json["Codec"] = codec }
    if let bitDepth { json["BitDepth"] = bitDepth }
    if let range { json["VideoRangeType"] = range }
    if let dvProfile { json["DvProfile"] = dvProfile }
    return decodeStream(json)
}

@MainActor
func h264() -> MediaStream { video(codec: "h264") }

@MainActor
func hevc(
    bitDepth: Int? = 10, range: String? = nil, dvProfile: Int? = nil,
    width: Int = 1920, height: Int = 1080
) -> MediaStream {
    video(codec: "hevc", bitDepth: bitDepth, range: range,
          dvProfile: dvProfile, width: width, height: height)
}

@MainActor
func audio(codec: String, channels: Int = 6) -> MediaStream {
    decodeStream([
        "Index": 1, "Type": "Audio", "Codec": codec,
        "Channels": channels, "IsDefault": true,
    ])
}

@MainActor
func aac() -> MediaStream { audio(codec: "aac", channels: 2) }

@MainActor
func ac3() -> MediaStream { audio(codec: "ac3") }

@MainActor
func eac3() -> MediaStream { audio(codec: "eac3") }

@MainActor
func truehd() -> MediaStream { audio(codec: "truehd", channels: 8) }

@MainActor
func subtitle(index: Int, codec: String) -> MediaStream {
    decodeStream(["Index": index, "Type": "Subtitle", "Codec": codec])
}

@MainActor
func source(
    container: String,
    video: MediaStream?,
    audio: MediaStream?,
    subtitles: [MediaStream] = [],
    bitrate: Int? = nil
) -> MediaSource {
    var json: [String: Any] = ["Id": "src", "Container": container]
    if let bitrate { json["Bitrate"] = bitrate }

    var streams: [[String: Any]] = []
    let encoder = JSONEncoder()
    for stream in [video, audio].compactMap({ $0 }) + subtitles {
        let data = try! encoder.encode(stream)
        streams.append(try! JSONSerialization.jsonObject(with: data) as! [String: Any])
    }
    json["MediaStreams"] = streams

    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JellyfinClient.decoder.decode(MediaSource.self, from: data)
}

import Foundation
import TestKit
import LumiereKit

@MainActor
func registerStreamBuilderTests(_ t: TestRunner) {
    let server = URL(string: "http://192.168.60.40:8096")!
    let headers = ["Authorization": "MediaBrowser Token=\"secret-token\""]

    func stream(
        route: PlaybackDecision.Route,
        maxBitrate: Int? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) -> StreamBuilder.Stream? {
        StreamBuilder.stream(
            for: PlaybackDecision(route: route, engine: .mpv, reason: .nativelySupported),
            serverURL: server,
            itemId: "item42",
            mediaSourceId: "src7",
            playSessionId: "session9",
            headers: headers,
            maxBitrate: maxBitrate,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    t.suite("Stream URLs") { t in

        t.test("direct play asks for the original bytes") {
            let url = stream(route: .directPlay)?.url.absoluteString ?? ""
            t.expect(url.contains("/Videos/item42/stream"), url)
            // static=true is precisely what makes the Jellyfin dashboard report
            // Direct Play rather than spinning up ffmpeg.
            t.expect(url.contains("static=true"), url)
            t.expect(url.contains("mediaSourceId=src7"), url)
            t.expect(url.contains("playSessionId=session9"), url)
        }

        t.test("remux copies both streams into a new container") {
            let url = stream(route: .remux)?.url.absoluteString ?? ""
            t.expect(url.contains("/Videos/item42/stream.mp4"), url)
            t.expect(url.contains("videoCodec=copy"), url)
            t.expect(url.contains("audioCodec=copy"), url)
            t.expect(url.contains("static=false"), url)
        }

        t.test("transcode requests HLS with codecs every decoder takes") {
            let url = stream(route: .transcode)?.url.absoluteString ?? ""
            t.expect(url.contains("/Videos/item42/main.m3u8"), url)
            t.expect(url.contains("videoCodec=h264"), url)
            t.expect(url.contains("audioCodec=aac"), url)
            t.expect(url.contains("transcodingProtocol=hls"), url)
        }

        t.test("a bitrate limit reaches the transcode URL") {
            let url = stream(route: .transcode, maxBitrate: 8_000_000)?.url.absoluteString ?? ""
            t.expect(url.contains("maxStreamingBitrate=8000000"), url)
            t.expect(url.contains("videoBitRate=8000000"), url)
        }

        t.test("a transcode burns in the chosen subtitle") {
            let url = stream(route: .transcode, subtitleStreamIndex: 3)?.url.absoluteString ?? ""
            t.expect(url.contains("subtitleStreamIndex=3"), url)
            t.expect(url.contains("subtitleMethod=Encode"), url)
        }

        t.test("a chosen audio track reaches remux and transcode URLs") {
            t.expect(stream(route: .remux, audioStreamIndex: 2)?
                .url.absoluteString.contains("audioStreamIndex=2") == true)
            t.expect(stream(route: .transcode, audioStreamIndex: 2)?
                .url.absoluteString.contains("audioStreamIndex=2") == true)
        }
    }

    t.suite("Credentials never enter the URL") { t in

        t.test("no route puts the token in the query string") {
            // A token in a URL ends up in server logs, shell history and
            // screenshots. Every engine here can send a header instead.
            for route in [PlaybackDecision.Route.directPlay, .remux, .transcode] {
                let built = stream(route: route)
                let url = built?.url.absoluteString ?? ""
                t.expect(!url.contains("secret-token"), "\(route.rawValue) leaked the token: \(url)")
                t.expect(!url.lowercased().contains("api_key"), "\(route.rawValue) used api_key")
                t.expect(!url.lowercased().contains("token="), "\(route.rawValue) used token=")
            }
        }

        t.test("the token is carried as a header instead") {
            let built = stream(route: .directPlay)
            t.expectEqual(built?.headers["Authorization"], headers["Authorization"])
        }
    }

    t.suite("Subtitle URLs") { t in

        t.test("an external subtitle resolves to a stream file") {
            let url = StreamBuilder.subtitleURL(
                serverURL: server, itemId: "item42", mediaSourceId: "src7", streamIndex: 3
            )?.absoluteString ?? ""
            t.expect(url.contains("/Videos/item42/src7/Subtitles/3/Stream.srt"), url)
        }

        t.test("the subtitle format is selectable") {
            let url = StreamBuilder.subtitleURL(
                serverURL: server, itemId: "i", mediaSourceId: "s",
                streamIndex: 1, format: "vtt"
            )?.absoluteString ?? ""
            t.expect(url.hasSuffix("Stream.vtt"), url)
        }
    }

    t.suite("Playback session identity") { t in

        t.test("a missing play session id simply omits the parameter") {
            let built = StreamBuilder.stream(
                for: PlaybackDecision(route: .directPlay, engine: .mpv, reason: .nativelySupported),
                serverURL: server, itemId: "i", mediaSourceId: "s",
                playSessionId: nil, headers: headers
            )
            let url = built?.url.absoluteString ?? ""
            t.expect(!url.contains("playSessionId"), url)
            t.expectNil(built?.playSessionId)
        }

        t.test("a server on a subpath keeps it") {
            let subpath = URL(string: "https://example.com/jellyfin")!
            let built = StreamBuilder.stream(
                for: PlaybackDecision(route: .directPlay, engine: .mpv, reason: .nativelySupported),
                serverURL: subpath, itemId: "i", mediaSourceId: "s",
                playSessionId: nil, headers: [:]
            )
            t.expect(built?.url.absoluteString.hasPrefix("https://example.com/jellyfin/Videos/") == true,
                     built?.url.absoluteString ?? "nil")
        }
    }
}

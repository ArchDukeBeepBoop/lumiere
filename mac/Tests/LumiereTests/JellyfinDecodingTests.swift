import Foundation
import TestKit
import LumiereKit

/// Decoding tests against realistic Jellyfin payloads. These exist because the
/// server's JSON varies between versions in small, silent ways — a field that is
/// a string on 10.8 and an int on 10.10 — and a decode failure loses a whole
/// library page, not one field.
@MainActor
func registerJellyfinDecodingTests(_ t: TestRunner) {

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JellyfinClient.decode(type, from: Data(json.utf8), context: "test")
    }

    t.suite("Jellyfin decoding") { t in

        t.test("decodes a movie with media streams") {
            let item = try decode(JellyfinItem.self, movieJSON)
            t.expectEqual(item.name, "Blade Runner 2049")
            t.expectEqual(item.type, .movie)
            t.expectEqual(item.productionYear, 2017)
            t.expectEqual(item.runtimeSeconds, 9840)
            t.expectEqual(item.mediaSources?.count, 1)

            let video = item.mediaSources?.first?.videoStream
            t.expectEqual(video?.codec, "hevc")
            t.expectEqual(video?.width, 3840)
            t.expectEqual(video?.bitDepth, 10)
            t.expectEqual(video?.videoRangeType, "DOVI")
            t.expectEqual(video?.dvProfile, 5)

            let audio = item.mediaSources?.first?.defaultAudioStream
            t.expectEqual(audio?.codec, "truehd")
            t.expectEqual(audio?.channels, 8)
        }

        t.test("video profile decodes whether the server sends a string or an int") {
            let asInt = try decode(MediaStream.self, #"{"Index":0,"Type":"Video","Profile":120}"#)
            t.expectEqual(asInt.profile, 120)

            let asString = try decode(MediaStream.self, #"{"Index":0,"Type":"Video","Profile":"120"}"#)
            t.expectEqual(asString.profile, 120)

            let asName = try decode(MediaStream.self, #"{"Index":0,"Type":"Video","Profile":"Main 10"}"#)
            t.expectNil(asName.profile, "an unparseable profile should be nil, not a crash")
        }

        t.test("an unknown item type decodes as unknown rather than failing") {
            let item = try decode(JellyfinItem.self, #"{"Id":"1","Name":"X","Type":"MusicVideo"}"#)
            t.expectEqual(item.type, .unknown)
        }

        t.test("an unknown stream type decodes as unknown") {
            let stream = try decode(MediaStream.self, #"{"Index":3,"Type":"Lyric"}"#)
            t.expectEqual(stream.type, .unknown)
        }

        t.test("dates with and without fractional seconds both parse") {
            let withFraction = try decode(
                JellyfinItem.self,
                #"{"Id":"1","Name":"X","Type":"Movie","DateCreated":"2024-03-01T12:30:00.1234567Z"}"#
            )
            t.expectNotNil(withFraction.dateCreated)

            let withoutFraction = try decode(
                JellyfinItem.self,
                #"{"Id":"1","Name":"X","Type":"Movie","DateCreated":"2024-03-01T12:30:00Z"}"#
            )
            t.expectNotNil(withoutFraction.dateCreated)
        }

        t.test("a paged items response reports its total") {
            let response = try decode(
                ItemsResponse.self,
                #"{"Items":[{"Id":"1","Name":"A","Type":"Movie"}],"TotalRecordCount":412,"StartIndex":0}"#
            )
            t.expectEqual(response.items.count, 1)
            t.expectEqual(response.totalRecordCount, 412)
        }

        t.test("resume state converts ticks to seconds") {
            let item = try decode(
                JellyfinItem.self,
                #"{"Id":"1","Name":"X","Type":"Movie","UserData":{"PlaybackPositionTicks":43240000000,"Played":false}}"#
            )
            t.expectEqual(item.userData?.resumeSeconds, 4324)
            t.expectEqual(item.userData?.isInProgress, true)
        }

        t.test("a finished item is not in progress even with a stored position") {
            let item = try decode(
                JellyfinItem.self,
                #"{"Id":"1","Name":"X","Type":"Movie","UserData":{"PlaybackPositionTicks":43240000000,"Played":true}}"#
            )
            t.expectEqual(item.userData?.isInProgress, false)
        }

        t.test("an item with no media streams decodes without throwing") {
            let item = try decode(JellyfinItem.self, #"{"Id":"1","Name":"X","Type":"Series"}"#)
            t.expectNil(item.mediaSources)
            t.expectNil(item.userData)
        }

        t.test("media source separates video, audio and subtitle streams") {
            let item = try decode(JellyfinItem.self, movieJSON)
            let source = item.mediaSources!.first!
            t.expectEqual(source.audioStreams.count, 2)
            t.expectEqual(source.subtitleStreams.count, 1)
            t.expectEqual(source.subtitleStreams.first?.codec, "pgssub")
        }

        t.test("chapter start ticks convert to seconds") {
            let item = try decode(
                JellyfinItem.self,
                #"{"Id":"1","Name":"X","Type":"Movie","Chapters":[{"StartPositionTicks":6000000000,"Name":"Opening"}]}"#
            )
            t.expectEqual(item.chapters?.first?.startSeconds, 600)
        }

        t.test("authentication result decodes") {
            let result = try decode(
                AuthenticationResult.self,
                #"{"User":{"Id":"u1","Name":"alex"},"AccessToken":"tok","ServerId":"s1"}"#
            )
            t.expectEqual(result.user.name, "alex")
            t.expectEqual(result.accessToken, "tok")
        }

        t.test("quick connect result decodes before approval") {
            let result = try decode(
                QuickConnectResult.self,
                #"{"Secret":"abc","Code":"123456","Authenticated":false}"#
            )
            t.expectEqual(result.code, "123456")
            t.expectEqual(result.authenticated, false)
        }
    }
}

private let movieJSON = """
{
  "Id": "a1b2c3",
  "Name": "Blade Runner 2049",
  "Type": "Movie",
  "ProductionYear": 2017,
  "RunTimeTicks": 98400000000,
  "CommunityRating": 8.0,
  "OfficialRating": "R",
  "Genres": ["Science Fiction", "Drama"],
  "ImageTags": { "Primary": "ptag", "Logo": "ltag" },
  "BackdropImageTags": ["btag"],
  "UserData": { "PlaybackPositionTicks": 43240000000, "Played": false, "IsFavorite": true },
  "MediaSources": [
    {
      "Id": "src1",
      "Container": "mkv",
      "Size": 64424509440,
      "Bitrate": 52000000,
      "MediaStreams": [
        {
          "Index": 0, "Type": "Video", "Codec": "hevc", "Width": 3840, "Height": 2160,
          "BitDepth": 10, "VideoRange": "HDR", "VideoRangeType": "DOVI",
          "DvProfile": 5, "DvLevel": 6, "Profile": "Main 10", "AverageFrameRate": 23.976
        },
        {
          "Index": 1, "Type": "Audio", "Codec": "truehd", "Channels": 8,
          "Language": "eng", "IsDefault": true, "ChannelLayout": "7.1"
        },
        {
          "Index": 2, "Type": "Audio", "Codec": "ac3", "Channels": 6,
          "Language": "eng", "IsDefault": false
        },
        {
          "Index": 3, "Type": "Subtitle", "Codec": "pgssub",
          "Language": "eng", "IsDefault": false, "IsForced": false
        }
      ]
    }
  ]
}
"""

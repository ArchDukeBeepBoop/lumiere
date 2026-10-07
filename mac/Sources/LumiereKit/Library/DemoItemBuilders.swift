import Foundation

/// Builders for the demo library. Kept beside `DemoFixtures` and out of the
/// production model so `JellyfinItem` stays a pure decode target.
extension JellyfinItem {

    static func demoMovie(
        id: String, name: String, year: Int, runtimeMinutes: Int, genres: [String]
    ) -> JellyfinItem {
        decodeDemo([
            "Id": id,
            "Name": name,
            "Type": "Movie",
            "ProductionYear": year,
            "RunTimeTicks": Int64(runtimeMinutes) * 60 * 10_000_000,
            "Genres": genres,
        ])
    }

    static func demoSeries(
        id: String, name: String, year: Int, seasons: Int, genres: [String]
    ) -> JellyfinItem {
        decodeDemo([
            "Id": id,
            "Name": name,
            "Type": "Series",
            "ProductionYear": year,
            "ChildCount": seasons,
            "Genres": genres,
            "IsFolder": true,
        ])
    }

    static func demoSeason(
        id: String, name: String, seriesId: String, seriesName: String, number: Int
    ) -> JellyfinItem {
        decodeDemo([
            "Id": id,
            "Name": name,
            "Type": "Season",
            "SeriesId": seriesId,
            "SeriesName": seriesName,
            "IndexNumber": number,
            "IsFolder": true,
        ])
    }

    static func demoEpisode(
        id: String, name: String, seriesId: String, seriesName: String,
        season: Int, episode: Int, runtimeMinutes: Int
    ) -> JellyfinItem {
        decodeDemo([
            "Id": id,
            "Name": name,
            "Type": "Episode",
            "SeriesId": seriesId,
            "SeriesName": seriesName,
            "ParentIndexNumber": season,
            "IndexNumber": episode,
            "RunTimeTicks": Int64(runtimeMinutes) * 60 * 10_000_000,
        ])
    }

    /// A full detail payload: media sources, streams, cast, chapters.
    ///
    /// The four source shapes cycled through here are the ones that actually
    /// decide behaviour later — a Dolby Vision TrueHD MKV that only mpv can take,
    /// a plain MP4 that AVPlayer can, an HDR10 EAC3 MKV, and a title with two
    /// versions so the version picker has something to pick.
    static func demoDetail(
        base: JellyfinItem,
        index: Int,
        overview: String,
        cast: [(String, String)],
        chapters: Int,
        fixturePath: String? = nil
    ) -> JellyfinItem {
        var json: [String: Any] = [
            "Id": base.id,
            "Name": base.name,
            "Type": base.type.rawValue,
            "Overview": overview,
            "Genres": base.genres ?? [],
            "Taglines": ["Everyone already knows the ending."],
            "People": cast.enumerated().map { position, person in
                [
                    "Id": "person-\(index)-\(position)",
                    "Name": person.0,
                    "Role": person.1,
                    "Type": position < 2 ? "Actor" : (position == 2 ? "Director" : "Writer"),
                ]
            },
            "Chapters": (0..<chapters).map { chapter in
                [
                    "StartPositionTicks": Int64(chapter) * 8 * 60 * 10_000_000,
                    "Name": chapter == 0 ? "Opening" : "Chapter \(chapter + 1)",
                ] as [String: Any]
            },
        ]
        if let year = base.productionYear { json["ProductionYear"] = year }

        // A Series is a folder: Jellyfin returns no media sources and no runtime
        // for it, only for its episodes. Emitting them here would put a "4K
        // TrueHD" badge on a show, which no real server ever does.
        if base.type != .series {
            if let ticks = base.runTimeTicks { json["RunTimeTicks"] = ticks }
            var sources = mediaSources(index: index, runTimeTicks: base.runTimeTicks ?? 0)
            if let fixturePath {
                for position in sources.indices { sources[position]["Path"] = fixturePath }
            }
            json["MediaSources"] = sources
        }
        return decodeDemo(json)
    }

    private static func mediaSources(index: Int, runTimeTicks: Int64) -> [[String: Any]] {
        switch index % 4 {
        case 0:
            return [uhdDolbyVisionTrueHD(runTimeTicks: runTimeTicks)]
        case 1:
            return [hd264AAC(runTimeTicks: runTimeTicks)]
        case 2:
            return [uhdHDR10EAC3(runTimeTicks: runTimeTicks)]
        default:
            // Two files for one title: the version picker's reason to exist.
            return [
                uhdHDR10EAC3(runTimeTicks: runTimeTicks),
                hd264AAC(runTimeTicks: runTimeTicks),
            ]
        }
    }

    private static func uhdDolbyVisionTrueHD(runTimeTicks: Int64) -> [String: Any] {
        [
            "Id": "src-uhd-dv", "Name": "4K Dolby Vision", "Container": "mkv",
            "Size": 61_000_000_000, "Bitrate": 54_000_000, "RunTimeTicks": runTimeTicks,
            "Path": "/media/movies/title.2160p.DV.TrueHD.Atmos.mkv",
            "MediaStreams": [
                [
                    "Index": 0, "Type": "Video", "Codec": "hevc", "Width": 3840, "Height": 2160,
                    "BitDepth": 10, "VideoRange": "HDR", "VideoRangeType": "DOVI",
                    "DvProfile": 5, "DvLevel": 6, "AverageFrameRate": 23.976,
                    "IsDefault": true,
                ],
                [
                    "Index": 1, "Type": "Audio", "Codec": "truehd", "Channels": 8,
                    "ChannelLayout": "7.1", "Language": "eng", "SampleRate": 48000,
                    "IsDefault": true,
                ],
                [
                    "Index": 2, "Type": "Audio", "Codec": "ac3", "Channels": 6,
                    "ChannelLayout": "5.1", "Language": "eng", "SampleRate": 48000,
                    "BitRate": 640000,
                ],
                [
                    "Index": 3, "Type": "Subtitle", "Codec": "pgssub",
                    "Language": "eng", "IsDefault": false,
                ],
                [
                    "Index": 4, "Type": "Subtitle", "Codec": "pgssub",
                    "Language": "eng", "IsForced": true,
                ],
            ],
        ]
    }

    private static func hd264AAC(runTimeTicks: Int64) -> [String: Any] {
        [
            "Id": "src-hd-h264", "Name": "1080p", "Container": "mp4",
            "Size": 8_400_000_000, "Bitrate": 9_800_000, "RunTimeTicks": runTimeTicks,
            "Path": "/media/movies/title.1080p.mp4",
            "MediaStreams": [
                [
                    "Index": 0, "Type": "Video", "Codec": "h264", "Width": 1920, "Height": 1080,
                    "BitDepth": 8, "VideoRange": "SDR", "AverageFrameRate": 23.976,
                    "IsDefault": true,
                ],
                [
                    "Index": 1, "Type": "Audio", "Codec": "aac", "Channels": 2,
                    "ChannelLayout": "stereo", "Language": "eng", "SampleRate": 48000,
                    "BitRate": 192000, "IsDefault": true,
                ],
                [
                    "Index": 2, "Type": "Subtitle", "Codec": "subrip",
                    "Language": "eng", "IsExternal": true,
                ],
            ],
        ]
    }

    private static func uhdHDR10EAC3(runTimeTicks: Int64) -> [String: Any] {
        [
            "Id": "src-uhd-hdr10", "Name": "4K HDR", "Container": "mkv",
            "Size": 34_000_000_000, "Bitrate": 31_000_000, "RunTimeTicks": runTimeTicks,
            "Path": "/media/movies/title.2160p.HDR.mkv",
            "MediaStreams": [
                [
                    "Index": 0, "Type": "Video", "Codec": "hevc", "Width": 3840, "Height": 2160,
                    "BitDepth": 10, "VideoRange": "HDR", "VideoRangeType": "HDR10",
                    "AverageFrameRate": 23.976, "IsDefault": true,
                ],
                [
                    "Index": 1, "Type": "Audio", "Codec": "eac3", "Channels": 6,
                    "ChannelLayout": "5.1", "Language": "eng", "SampleRate": 48000,
                    "BitRate": 768000, "IsDefault": true,
                ],
                [
                    "Index": 2, "Type": "Subtitle", "Codec": "ass", "Language": "eng",
                ],
            ],
        ]
    }

    /// Round-trips through the real decoder, so fixtures exercise the same path
    /// server responses do and cannot drift from it.
    private static func decodeDemo(_ json: [String: Any]) -> JellyfinItem {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
    }
}

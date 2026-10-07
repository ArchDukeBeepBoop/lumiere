import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Seeds a synthetic library so the UI can be built and measured without a
/// server.
///
/// This is not a mock layer: it writes real rows into the real cache and real
/// JPEGs into the real disk cache, so the grid renders through the actual decode
/// path, the actual bounded caches, and the actual cancellation. That makes it a
/// genuine memory measurement, not a drawing of one.
///
/// Enabled with `LUMIERE_DEMO=1`. Never runs otherwise.
public enum DemoFixtures {

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LUMIERE_DEMO"] == "1"
    }

    public static let serverId = "demo-server"
    public static let serverURL = URL(string: "http://demo.local")!

    /// Where `Scripts/make-fixtures.sh` put the test media. Demo media sources
    /// point at these, so playing something in demo mode drives the real engine
    /// over a real file rather than proving nothing.
    public static var fixturesDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["LUMIERE_FIXTURES"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("fixtures")
    }

    /// Maps a demo item onto whichever fixture matches the source shape its
    /// detail payload claims. Keeping these in step matters: a file whose
    /// container disagrees with its metadata would make the decision engine look
    /// wrong when it is right.
    public static func fixturePath(forIndex index: Int) -> String {
        let name: String
        switch index % 4 {
        case 0: name = "sample_hevc_ac3.mkv"
        case 1: name = "sample_h264.mp4"
        case 2: name = "sample_4k_hdr10.mkv"
        default: name = "sample_h264.mkv"
        }
        return fixturesDirectory.appendingPathComponent(name).path
    }

    /// Widths the app actually asks for, resolved to ladder rungs. Seeding these
    /// exactly is what makes the fixture images hit rather than miss.
    /// 120 and 140/150 are the shelf and grid sizes; 180 is the detail page's
    /// larger poster, which lands on a different ladder rung.
    static let posterDisplayWidths: [CGFloat] = [120, 132, 140, 150, 180]
    /// 64 is the compact resume thumbnail, 150 the episode-row still, 240 the
    /// hero-layout card, 340 the classic layout's wide continue card.
    static let wideDisplayWidths: [CGFloat] = [64, 150, 240, 340, 384]
    /// The hero fills the window, so it lands on a large rung that varies with
    /// window width. All four are seeded rather than guessing one.
    static let heroRungs = [1280, 1920, 2560, 3840]

    public static func seed(
        database: LibraryDatabase,
        pipeline: ImagePipeline,
        movieCount: Int = 180,
        seriesCount: Int = 60
    ) async throws {
        let now = Date()

        let libraries = [
            ("demo-movies", "Movies", "movies"),
            ("demo-tv", "TV Shows", "tvshows"),
        ]

        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM item")
            try db.execute(sql: "DELETE FROM userData")
            try db.execute(sql: "DELETE FROM library")

            for (index, library) in libraries.enumerated() {
                try db.execute(
                    sql: "INSERT INTO library (id, serverId, name, collectionType, sortIndex, itemCount) "
                       + "VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [library.0, serverId, library.1, library.2, index, nil]
                )
            }
        }

        var records: [(ItemRecord, UserDataRecord?)] = []

        for index in 0..<movieCount {
            let title = movieTitle(index)
            var record = ItemRecord(
                from: JellyfinItem.demoMovie(
                    id: "movie-\(index)",
                    name: title,
                    year: 1995 + (index % 30),
                    runtimeMinutes: 88 + (index % 70),
                    genres: genres(index)
                ),
                serverId: serverId,
                syncedAt: now
            )
            record.parentId = "demo-movies"
            record.path = fixturePath(forIndex: index)
            record.primaryTag = "tag-movie-\(index)"
            record.backdropTag = "backdrop-movie-\(index)"
            record.setDateCreated(now.addingTimeInterval(-Double(index) * 3600))
            record.communityRating = Double(55 + (index * 7) % 45) / 10
            record.officialRating = ["PG", "PG-13", "R", "12A"][index % 4]
            record.overview = overview(title)

            // Roughly one in seven part-watched, so continue-watching has content
            // without the whole library looking half-finished.
            var userData: UserDataRecord?
            if index % 7 == 3 {
                let runtime = record.runTimeTicks ?? 0
                userData = UserDataRecord(itemId: record.id, from: nil, updatedAt: now)
                userData?.playbackPositionTicks = Int64(Double(runtime) * Double(15 + index % 70) / 100)
            } else if index % 5 == 0 {
                userData = UserDataRecord(itemId: record.id, from: nil, updatedAt: now)
                userData?.played = true
            }
            records.append((record, userData))
        }

        for index in 0..<seriesCount {
            let title = seriesTitle(index)
            var record = ItemRecord(
                from: JellyfinItem.demoSeries(
                    id: "series-\(index)",
                    name: title,
                    year: 2005 + (index % 20),
                    seasons: 1 + (index % 6),
                    genres: genres(index + 3)
                ),
                serverId: serverId,
                syncedAt: now
            )
            record.parentId = "demo-tv"
            record.primaryTag = "tag-series-\(index)"
            record.backdropTag = "backdrop-series-\(index)"
            // The first six get two real seasons seeded below; the rest keep the
            // generated count. Disagreeing with the seasons that exist would be a
            // fixture that lies about itself.
            if index < 6 { record.childCount = 2 }
            record.setDateCreated(now.addingTimeInterval(-Double(index) * 7200))
            record.communityRating = Double(60 + (index * 11) % 40) / 10
            record.overview = overview(title)
            records.append((record, nil))
        }

        // Real season and episode structure for the first few series, so the
        // season picker and episode list have something to exercise. Bounded on
        // purpose: every series would be 700+ rows to prove the same thing.
        for seriesIndex in 0..<6 {
            let seriesId = "series-\(seriesIndex)"
            for seasonNumber in 1...2 {
                let seasonId = "\(seriesId)-s\(seasonNumber)"
                var season = ItemRecord(
                    from: JellyfinItem.demoSeason(
                        id: seasonId,
                        name: "Season \(seasonNumber)",
                        seriesId: seriesId,
                        seriesName: seriesTitle(seriesIndex),
                        number: seasonNumber
                    ),
                    serverId: serverId,
                    syncedAt: now
                )
                season.parentId = seriesId
                season.primaryTag = "tag-\(seasonId)"
                records.append((season, nil))

                for episodeNumber in 1...6 {
                    let episodeId = "\(seasonId)-e\(episodeNumber)"
                    var episode = ItemRecord(
                        from: JellyfinItem.demoEpisode(
                            id: episodeId,
                            name: episodeTitle(seriesIndex + episodeNumber),
                            seriesId: seriesId,
                            seriesName: seriesTitle(seriesIndex),
                            season: seasonNumber,
                            episode: episodeNumber,
                            runtimeMinutes: 44 + (episodeNumber % 12)
                        ),
                        serverId: serverId,
                        syncedAt: now
                    )
                    episode.parentId = seasonId
                    episode.seasonId = seasonId
                    episode.path = fixturePath(forIndex: episodeNumber)
                    episode.primaryTag = "tag-\(episodeId)"
                    episode.backdropTag = "backdrop-\(episodeId)"
                    episode.overview = overview(episodeTitle(seriesIndex + episodeNumber))
                    episode.setDateCreated(now.addingTimeInterval(
                        -Double(seriesIndex * 100 + seasonNumber * 10 + episodeNumber) * 900
                    ))

                    // Part of season 1 watched, so the list shows the mix of
                    // watched, in-progress and untouched that a real season has.
                    var userData: UserDataRecord?
                    if seasonNumber == 1 && episodeNumber <= 2 {
                        userData = UserDataRecord(itemId: episodeId, from: nil, updatedAt: now)
                        userData?.played = true
                    } else if seasonNumber == 1 && episodeNumber == 3 {
                        userData = UserDataRecord(itemId: episodeId, from: nil, updatedAt: now)
                        userData?.playbackPositionTicks =
                            Int64(Double(episode.runTimeTicks ?? 0) * 0.42)
                    }
                    records.append((episode, userData))
                }
            }
        }

        // One show with no seasons at all — episodes straight under the show,
        // the shape 103 real shows have and that once listed nothing. Dated
        // long ago so it stays off the recent shelves the screenshots compare.
        for episodeNumber in 1...3 {
            let episodeId = "series-6-e\(episodeNumber)"
            var episode = ItemRecord(
                from: JellyfinItem.demoEpisode(
                    id: episodeId, name: episodeTitle(60 + episodeNumber),
                    seriesId: "series-6", seriesName: seriesTitle(6),
                    season: 0, episode: episodeNumber, runtimeMinutes: 30
                ),
                serverId: serverId, syncedAt: now
            )
            episode.parentId = "series-6"
            episode.seasonId = nil
            episode.parentIndexNumber = nil
            episode.path = fixturePath(forIndex: episodeNumber)
            episode.setDateCreated(now.addingTimeInterval(-400 * 86400))
            records.append((episode, nil))
        }

        // A handful of episodes so the continue row shows the series-plus-SxEy
        // shape, which is where the layout is easiest to get wrong.
        for index in 0..<8 {
            let seriesIndex = index * 3
            var record = ItemRecord(
                from: JellyfinItem.demoEpisode(
                    id: "episode-\(index)",
                    name: episodeTitle(index),
                    seriesId: "series-\(seriesIndex)",
                    seriesName: seriesTitle(seriesIndex),
                    season: 1 + (index % 3),
                    episode: 1 + (index % 9),
                    runtimeMinutes: 42 + (index % 18)
                ),
                serverId: serverId,
                syncedAt: now
            )
            record.parentId = "demo-tv"
            record.primaryTag = "tag-episode-\(index)"
            record.backdropTag = "backdrop-episode-\(index)"
            record.setDateCreated(now.addingTimeInterval(-Double(index) * 1800))

            var userData = UserDataRecord(itemId: record.id, from: nil, updatedAt: now)
            userData.playbackPositionTicks = Int64(
                Double(record.runTimeTicks ?? 0) * Double(20 + index * 9) / 100
            )
            records.append((record, userData))
        }

        let seeded = records
        try await database.writer.write { db in
            for (record, userData) in seeded {
                try record.insert(db)
                if let userData { try userData.insert(db) }
            }
        }

        try await seedDetails(for: seeded.map(\.0), database: database)
        await seedArtwork(for: seeded.map(\.0), pipeline: pipeline)
    }
}

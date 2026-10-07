import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Detail payloads, artwork and titles for the demo library.
///
/// Split from DemoFixtures.swift for the project's 300-line limit. Fixture data is
/// the least interesting code in the project and the easiest to let sprawl, which
/// is exactly why the rule should apply to it too.
extension DemoFixtures {

    // MARK: - Detail payloads

    /// Writes full payloads into the same `itemDetail` table the server path uses,
    /// so detail pages render real streams, cast and chapters with no special
    /// casing anywhere in the repository or the views.
    static func seedDetails(
        for records: [ItemRecord], database: LibraryDatabase
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var payloads: [(String, String)] = []
        for (index, record) in records.enumerated() where record.itemType != .season {
            // Preserve the real type: a Series detail must not be built as a
            // Movie, or it inherits a runtime and a media source it should not have.
            let base = record.itemType == .series
                ? JellyfinItem.demoSeries(
                    id: record.id, name: record.name,
                    year: record.productionYear ?? 2000,
                    seasons: record.childCount ?? 1, genres: record.genreList
                  )
                : JellyfinItem.demoMovie(
                    id: record.id, name: record.name,
                    year: record.productionYear ?? 2000,
                    runtimeMinutes: Int((record.runtimeSeconds ?? 5400) / 60),
                    genres: record.genreList
                  )
            let detail = JellyfinItem.demoDetail(
                base: base,
                index: index,
                overview: record.overview ?? "",
                cast: castList(index),
                chapters: record.itemType == .episode ? 4 : 12,
                fixturePath: fixturePath(forIndex: index)
            )
            guard let json = String(data: try encoder.encode(detail), encoding: .utf8) else {
                continue
            }
            payloads.append((record.id, json))
        }

        let rows = payloads
        try await database.writer.write { db in
            for (id, json) in rows {
                try db.execute(
                    sql: "INSERT INTO itemDetail (itemId, json, fetchedAt) VALUES (?, ?, ?) "
                       + "ON CONFLICT(itemId) DO UPDATE SET json = excluded.json",
                    arguments: [id, json, Date()]
                )
            }
        }
    }

    static let people = [
        "Mara Ellison", "Tobias Vance", "Ingrid Osei", "Rafael Lindqvist",
        "Nadia Ferreira", "Callum Reyes", "Yusuf Adeyemi", "Beatrix Nowak",
    ]

    static func castList(_ index: Int) -> [(String, String)] {
        let roles = ["Harper", "Detective Voss", "Director", "Screenplay"]
        return (0..<4).map { position in
            (people[(index + position * 3) % people.count], roles[position])
        }
    }

    // MARK: - Artwork

    /// Generates a poster and a wide image per item, at exactly the ladder rungs
    /// the views will request, and writes them into the pipeline's disk cache.
    static func seedArtwork(for records: [ItemRecord], pipeline: ImagePipeline) async {
        let posterRungs = Set(posterDisplayWidths.map {
            Downsample.requestWidth(forDisplayWidth: $0, screenScale: 2)
        })
        let wideRungs = Set(wideDisplayWidths.map {
            Downsample.requestWidth(forDisplayWidth: $0, screenScale: 2)
        })

        for (index, record) in records.enumerated() {
            let hue = Double((index * 37) % 360) / 360

            if let tag = record.primaryTag {
                for rung in posterRungs {
                    guard let data = poster(hue: hue, width: rung, title: record.name) else { continue }
                    let key = JellyfinImageURL.cacheKey(
                        itemId: record.id, kind: .primary, tag: tag, maxWidth: rung
                    )
                    await pipeline.seedDiskCache(data, for: key)
                }
            }

            if let tag = record.backdropTag {
                // Large rungs are expensive to generate, so only items that can
                // actually become the hero get them: episodes, which lead the
                // resume list, plus the first few by date added.
                let canBeHero = index < 14 || record.itemType == .episode
                let rungs = canBeHero ? wideRungs.union(heroRungs) : wideRungs
                for rung in rungs {
                    guard let data = backdrop(hue: hue, width: rung) else { continue }
                    let key = JellyfinImageURL.cacheKey(
                        itemId: record.id, kind: .backdrop, tag: tag, maxWidth: rung
                    )
                    await pipeline.seedDiskCache(data, for: key)
                }
            }
        }
    }

    static func poster(hue: Double, width: Int, title: String) -> Data? {
        let height = Int(Double(width) / (2.0 / 3.0))
        return render(width: width, height: height) { context in
            fillBands(context, width: width, height: height, hue: hue, bands: 5)
        }
    }

    static func backdrop(hue: Double, width: Int) -> Data? {
        let height = Int(Double(width) / (16.0 / 9.0))
        return render(width: width, height: height) { context in
            fillBands(context, width: width, height: height, hue: hue, bands: 8)
        }
    }

    static func fillBands(
        _ context: CGContext, width: Int, height: Int, hue: Double, bands: Int
    ) {
        // Bands rather than a flat fill: a solid colour compresses to almost
        // nothing and would make the decode measurements meaningless.
        let bandHeight = max(1, height / bands)
        for band in 0..<bands {
            let shade = 0.18 + Double(band) / Double(bands) * 0.5
            context.setFillColor(
                CGColor(
                    red: shade * (0.5 + hue),
                    green: shade * 0.75,
                    blue: shade * (1.4 - hue),
                    alpha: 1
                )
            )
            context.fill(CGRect(
                x: 0, y: band * bandHeight, width: width, height: bandHeight
            ))
        }
    }

    static func render(
        width: Int, height: Int, draw: (CGContext) -> Void
    ) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        draw(context)

        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: - Titles

    static let firstWords = [
        "Silent", "Crimson", "Northern", "Broken", "Golden", "Hollow", "Distant",
        "Iron", "Pale", "Wandering", "Final", "Quiet", "Restless", "Amber", "Vanished",
    ]
    static let secondWords = [
        "Harbour", "Signal", "Archive", "Meridian", "Orchard", "Compass", "Lantern",
        "Verdict", "Corridor", "Threshold", "Passage", "Reckoning", "Hour", "Ledger",
    ]

    static func movieTitle(_ index: Int) -> String {
        "\(firstWords[index % firstWords.count]) \(secondWords[(index / 3) % secondWords.count])"
    }

    static func seriesTitle(_ index: Int) -> String {
        "The \(secondWords[index % secondWords.count])"
    }

    static func episodeTitle(_ index: Int) -> String {
        "\(firstWords[(index * 5) % firstWords.count]) Ground"
    }

    static func genres(_ index: Int) -> [String] {
        let pool = ["Drama", "Thriller", "Science Fiction", "Comedy", "Documentary", "Crime"]
        return [pool[index % pool.count], pool[(index + 2) % pool.count]]
    }

    static func overview(_ title: String) -> String {
        "\(title) follows a small crew through a season of bad weather and worse "
      + "decisions, in a place where everyone already knows the ending."
    }
}

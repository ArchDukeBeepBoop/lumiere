import Foundation
import GRDB

/// One series the scanner found, with what a repair would change.
public struct MergedSeries: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// Episodes whose season, number or title would change.
    public let changes: [MergedSeriesChange]
    /// Reasons files in this series will not be touched, one line per reason.
    public let skipped: [FilenameEpisodeRepair.Skip]
    /// The seasons the repair would produce, for the summary line — "1–16" reads
    /// very differently from "1–2" when deciding whether to trust it.
    public let seasons: [Int]
}

public struct MergedSeriesChange: Sendable, Identifiable, Hashable {
    public let id: String
    public let currentName: String
    public let currentSeason: Int?
    public let currentEpisode: Int?
    public let proposal: FilenameEpisodeRepair.Proposal
    public let filename: String
    /// So a generated thumbnail can be taken part-way in rather than at zero.
    public let runtimeSeconds: Double?
}

public extension LibraryRepository {

    /// Every series whose episodes collide, across the whole library.
    ///
    /// Reads the local cache rather than the server. The alternative is one
    /// `/Shows/{id}/Episodes` request per series — 1,861 of them on a real library,
    /// several minutes of waiting to answer a question the cache can already answer,
    /// since the sync has stored every episode's path since phase 2.
    ///
    /// Only series where `FilenameEpisodeRepair` had to *resolve* seasons come back.
    /// A series whose episode titles merely differ from its filenames is not
    /// broken, and offering to rewrite a thousand of those would bury the twenty
    /// that are.
    func mergedSeries() async throws -> [MergedSeries] {
        struct Row: Decodable, FetchableRecord {
            let id: String
            let name: String
            let seriesId: String
            let seriesName: String?
            let indexNumber: Int?
            let parentIndexNumber: Int?
            let path: String?
            let runTimeTicks: Int64?
        }

        let rows: [Row] = try await database.writer.read { [serverId] db in
            let request = ItemRecord
                .select(
                    Column("id"), Column("name"), Column("seriesId"), Column("seriesName"),
                    Column("indexNumber"), Column("parentIndexNumber"), Column("path"),
                    Column("runTimeTicks")
                )
                .filter(Column("serverId") == serverId)
                .filter(Column("type") == JellyfinItem.ItemType.episode.rawValue)
                .filter(Column("seriesId") != nil)
                .filter(Column("path") != nil)
            return try Row.fetchAll(db, request)
        }

        return Dictionary(grouping: rows, by: \.seriesId)
            .compactMap { seriesId, episodes -> MergedSeries? in
                let plan = FilenameEpisodeRepair.plan(
                    for: episodes.map { (id: $0.id, path: $0.path) }
                )
                guard plan.resolvedSeasons else { return nil }

                let byId = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
                // Only where the *numbering* changes. A sweep exists to unpick a
                // merge, and rewriting a title is not part of that: JoJo needed 13
                // episodes renumbered and would have taken 115 titles with it —
                // "The Evil Spirit" for "The Man Possessed by an Evil Spirit",
                // another translation rather than a correction. The single-series
                // sheet still rewrites titles, because there you asked for exactly
                // that and watched it happen.
                let changes = plan.proposals.compactMap { proposal -> MergedSeriesChange? in
                    guard let row = byId[proposal.id] else { return nil }
                    guard row.parentIndexNumber != proposal.season
                            || row.indexNumber != proposal.episode
                    else { return nil }
                    return MergedSeriesChange(
                        id: row.id,
                        currentName: row.name,
                        currentSeason: row.parentIndexNumber,
                        currentEpisode: row.indexNumber,
                        proposal: proposal,
                        filename: ((row.path ?? "") as NSString).lastPathComponent,
                        runtimeSeconds: row.runTimeTicks.map { Double($0) / 10_000_000 }
                    )
                }
                guard !changes.isEmpty else { return nil }

                return MergedSeries(
                    id: seriesId,
                    name: episodes.first?.seriesName ?? "Unknown series",
                    changes: changes,
                    skipped: plan.skipped,
                    seasons: Array(Set(plan.proposals.map(\.season))).sorted()
                )
            }
            // Most episodes first: the series worth looking at hardest are the ones
            // where the most is about to change.
            .sorted { ($0.changes.count, $1.name) > ($1.changes.count, $0.name) }
    }
}

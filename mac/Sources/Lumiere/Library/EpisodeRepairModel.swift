import Foundation
import LumiereKit
import Observation

/// Rebuilds a series' episode numbering and titles from the filenames on disk.
///
/// Written for the shape Monogatari arrived in: Jellyfin matched sixteen separate
/// arcs against one listing, so 118 files came back carrying fifteen distinct
/// names — sixteen files all called season 1 episode 1, every one of them named
/// after Bakemonogatari's opening episode. Nothing in the scraped metadata can
/// separate them, because the scraper is the thing that merged them.
///
/// The filenames were right the whole time. `FilenameEpisodeRepair` reads them;
/// this drives the reading against the server, shows what it would change before
/// changing anything, and locks each name so the next scrape cannot merge them
/// back. Nothing here is Monogatari-specific — any series whose files are named
/// properly and whose metadata is not can be put right the same way.
@MainActor
@Observable
final class EpisodeRepairModel {

    /// One episode, as it is now and as the filename says it should be.
    struct Row: Identifiable, Sendable {
        let id: String
        let currentName: String
        let currentSeason: Int?
        let currentEpisode: Int?
        let proposal: FilenameEpisodeRepair.Proposal
        let filename: String

        /// Whether applying this would change anything. Unchanged rows are still
        /// shown — seeing that most of a series is already right is what makes the
        /// handful that are wrong believable.
        var changes: Bool {
            currentName != proposal.title
                || currentSeason != proposal.season
                || currentEpisode != proposal.episode
        }

        var currentNumbering: String {
            guard let season = currentSeason, let episode = currentEpisode else {
                return "unnumbered"
            }
            return String(format: "S%02dE%02d", season, episode)
        }

        var proposedNumbering: String {
            String(format: "S%02dE%02d", proposal.season, proposal.episode)
        }
    }

    private let client: JellyfinClient
    private let repository: LibraryRepository
    private let seriesId: String

    var rows: [Row] = []
    /// Files the repair will not touch, with the reason. Shown, not swallowed: a
    /// count of what changed is only trustworthy next to a count of what did not.
    var skipped: [FilenameEpisodeRepair.Skip] = []
    var isLoading = true
    var isApplying = false
    /// How far an apply has got, for the progress line. Applying 118 episodes is
    /// over a hundred round trips, and a spinner with no count looks stuck.
    var applied = 0
    var message: String?
    /// Whether to ask the server to re-extract each episode's thumbnail.
    ///
    /// Off by default, and the default is the correction. It shipped on, so a
    /// repair — a request to fix *numbering* — also cut a new frame for every
    /// episode of the series and froze the item to keep it, which is a second,
    /// larger, irreversible change nobody asked for. Frame grabs are for the
    /// folder-browsed libraries, where there is no artwork to lose; a scraped
    /// show has stills worth keeping.
    ///
    /// Still offered, because it is genuinely the other half of a merged series:
    /// when the numbering was wrong, every thumb belonged to the wrong episode.
    /// Now it is asked for rather than assumed — and it remains the expensive
    /// half, one decoded frame per file against one cheap write.
    var refreshesThumbnails = false

    var changedRows: [Row] { rows.filter(\.changes) }

    /// Episode runtimes, so a generated thumbnail can be taken part-way in.
    private(set) var runtimes: [String: Double] = [:]

    init(seriesId: String, client: JellyfinClient, repository: LibraryRepository) {
        self.seriesId = seriesId
        self.client = client
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        message = nil

        do {
            let episodes = try await client.episodes(seriesId: seriesId)
            runtimes = Dictionary(
                uniqueKeysWithValues: episodes.compactMap { episode in
                    guard let ticks = episode.runTimeTicks, ticks > 0 else { return nil }
                    return (episode.id, Double(ticks) / 10_000_000)
                }
            )
            let plan = FilenameEpisodeRepair.plan(
                for: episodes.map { (id: $0.id, path: $0.path ?? $0.mediaSources?.first?.path) }
            )
            skipped = plan.skipped
            let byId = Dictionary(uniqueKeysWithValues: plan.proposals.map { ($0.id, $0) })

            rows = episodes.compactMap { episode in
                guard let proposal = byId[episode.id] else { return nil }
                let path = episode.path ?? episode.mediaSources?.first?.path ?? ""
                return Row(
                    id: episode.id,
                    currentName: episode.name,
                    currentSeason: episode.parentIndexNumber,
                    currentEpisode: episode.indexNumber,
                    proposal: proposal,
                    filename: (path as NSString).lastPathComponent
                )
            }
            .sorted {
                ($0.proposal.season, $0.proposal.episode) < ($1.proposal.season, $1.proposal.episode)
            }

            if rows.isEmpty {
                message = "None of this series' files are named in a way this can read. "
                        + "It looks for a season and episode marker like 1x04 in the filename."
            }
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    /// Writes the changed rows, one at a time.
    ///
    /// Serial on purpose. This is a hundred-odd writes plus a hundred-odd image
    /// extractions against a machine that is probably also streaming something, and
    /// firing them in parallel is how a media server becomes unresponsive mid-repair.
    /// It also means a failure stops at a known point rather than halfway through
    /// an unknown subset.
    func apply() async -> Bool {
        let targets = changedRows
        guard !targets.isEmpty else { return false }

        isApplying = true
        applied = 0
        message = nil
        defer { isApplying = false }

        let writer = EpisodeRepairWriter(
            client: client, repository: repository, refreshesThumbnails: refreshesThumbnails,
            runtimes: runtimes
        )

        for row in targets {
            if Task.isCancelled { break }
            if case .failed(let reason) = await writer.apply(row.proposal) {
                message = applied == 0 ? reason
                    : "Stopped after \(applied) of \(targets.count): \(reason)"
                await writer.refreshCache(ids: targets.prefix(applied).map(\.id))
                return applied > 0
            }
            applied += 1
        }

        // Only what was actually written. Re-reading the whole target list after a
        // cancellation costs a request per episode to confirm that nothing changed.
        await writer.refreshCache(ids: targets.prefix(applied).map(\.id))
        return applied > 0
    }
}

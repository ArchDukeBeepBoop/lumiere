import Foundation
import LumiereKit
import Observation

/// Finds every merged series in the library and repairs the ones you tick.
///
/// The single-series sheet answered "fix this one". This answers the question that
/// follows it: a library of 1,861 series had twenty in the same state as Monogatari,
/// and finding them by opening series pages one at a time is not a plan.
///
/// The scan is local and instant — the cache has held every episode's path since
/// the first sync. Only the applying talks to the server.
@MainActor
@Observable
final class MergedSeriesModel {

    private let repository: LibraryRepository
    private let client: JellyfinClient

    var found: [MergedSeries] = []
    /// Ticked for repair. Empty to begin with: nothing here should happen because
    /// a sheet was opened.
    var selected: Set<String> = []
    var isScanning = true
    var isApplying = false
    /// Which series is being written, and how far through, for the progress line.
    var progress: String?
    var message: String?
    var refreshesThumbnails = true
    /// Series repaired in this session, so the list can show what is already done
    /// rather than silently offering it again.
    var completed: Set<String> = []

    var selectedEpisodeCount: Int {
        found.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.changes.count }
    }

    init(repository: LibraryRepository, client: JellyfinClient) {
        self.repository = repository
        self.client = client
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        message = nil
        do {
            found = try await repository.mergedSeries()
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func selectAll() {
        selected = Set(found.map(\.id)).subtracting(completed)
    }

    /// Repairs each ticked series in turn.
    ///
    /// Stops at the first failure and says where. Carrying on past an error would
    /// mean reporting a number that is true of the requests and false of the
    /// library — and half a renumbered series is worse than none, because the half
    /// that landed no longer matches the half that did not.
    func apply() async -> Bool {
        let targets = found.filter { selected.contains($0.id) && !completed.contains($0.id) }
        guard !targets.isEmpty else { return false }

        isApplying = true
        message = nil
        defer { isApplying = false; progress = nil }

        let writer = EpisodeRepairWriter(
            client: client, repository: repository, refreshesThumbnails: refreshesThumbnails,
            runtimes: Dictionary(
                uniqueKeysWithValues: found.flatMap(\.changes).compactMap { change in
                    change.runtimeSeconds.map { (change.id, $0) }
                }
            )
        )
        var repaired = 0

        for series in targets {
            // Checked on the *outer* loop too. Breaking only the inner one meant a
            // cancellation mid-sweep fell straight through to "repaired" for this
            // series and every one after it: cancel during series 3 of 20 and all
            // twenty were recorded as done, with series 3 left half-renumbered —
            // the exact state this is serial to avoid.
            if Task.isCancelled { break }

            var written: [String] = []
            var cancelled = false
            for (index, change) in series.changes.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                progress = "\(series.name) — \(index + 1) of \(series.changes.count)"
                if case .failed(let reason) = await writer.apply(change.proposal) {
                    await writer.refreshCache(ids: written)
                    message = "Stopped in \(series.name) after \(written.count) "
                            + "of \(series.changes.count): \(reason)"
                    return repaired > 0
                }
                written.append(change.id)
            }
            await writer.refreshCache(ids: written)
            if cancelled {
                message = "Stopped in \(series.name) after \(written.count) of "
                        + "\(series.changes.count) episodes."
                break
            }
            repaired += 1
            completed.insert(series.id)
        }

        // Rescanned rather than assumed: the point of a repair is that the library
        // no longer has the problem, and the honest way to show that is to look
        // again. Anything still listed is something that did not resolve.
        await scan()
        selected.subtract(completed)
        return repaired > 0
    }
}

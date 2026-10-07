import Foundation
import LumiereKit

/// Starting, stopping, and refusing to start a second sync.
///
/// Split from AppModel+Sync.swift for the project's 300-line limit. The reading
/// itself — what a pass over the libraries actually does — stays there; this is the
/// gate in front of it.
@MainActor
extension AppModel {

    func startSelectedSync(depth: SyncSelection.Depth) {
        guard !isOffline else {
            refuseOffline("Syncing")
            return
        }
        guard !syncSelection.libraries(from: libraries).isEmpty else {
            report("No libraries are ticked, so there is nothing to scan.")
            return
        }
        startSync(full: depth == .full, userInitiated: true)
    }

    /// How long a library may go without a full read before one is forced.
    ///
    /// Incremental passes cannot see a deletion or a server-side edit — they only
    /// ever look at the newest rows — so something has to walk the whole library
    /// eventually or the cache drifts. A week is far longer than the gap that
    /// matters and short enough that nobody ever has to think about it.
    static let fullScanInterval: TimeInterval = 7 * 24 * 60 * 60

    /// The only way a sync starts.
    ///
    /// Launch, sign-in and retry used to call `syncEverything()` directly, which
    /// left `syncTask` nil — so the "one at a time" guard did not apply to them and
    /// Stop had nothing to cancel. Pressing Sync during the launch pass started a
    /// second full sync: two loops writing the same rows, both driving the progress
    /// panel, and both eligible to run the deletion sweep with different ideas of
    /// what they had seen.
    func startSync(full: Bool = false, userInitiated: Bool = false) {
        // Automatic passes wait for the film to end. See `deferSyncDuringPlayback`.
        if !userInitiated, deferSyncDuringPlayback(full: full) { return }
        guard syncTask == nil else { return }
        // Generation-stamped, so a finishing task can only clear *its own* handle.
        //
        // It used to nil `syncTask` unconditionally, which defeated the guard above
        // after a Stop: `cancelSync` nils the handle and a second press installs
        // task two, then task one finally unwinds and nils task two's handle on its
        // way out. A third press then passes the guard and runs a second sync
        // alongside the first — two loops writing the same rows, both driving the
        // progress panel, and both eligible for the deletion sweep with different
        // ideas of what they had seen. That last part is why this matters more than
        // a cosmetic double-run.
        //
        // `DownloadManager.clearWorker(generation:)` solves the identical hazard the
        // identical way; this is the same pattern, applied where it was missed.
        syncGeneration &+= 1
        let generation = syncGeneration
        syncTask = Task { @MainActor in
            await syncEverything(forceFull: full)
            if generation == syncGeneration { syncTask = nil }
            await afterSync()
        }
    }

    /// Starts a sync and waits for it, still through the one guard.
    ///
    /// For the callers that need the library on screen before they continue.
    func runSync(full: Bool = false, userInitiated: Bool = false) async {
        startSync(full: full, userInitiated: userInitiated)
        await syncTask?.value
    }

    func cancelSync() {
        // Bumped so the task being cancelled cannot clear a successor's handle.
        syncGeneration &+= 1
        syncTask?.cancel()
        syncTask = nil
        syncProgress = nil
    }

    /// What every sync ends with: the health dot, the subtitle notice and the
    /// weekly line. One fetch of each, shared — Library Health takes the
    /// server a couple of seconds, and it was asked for twice per sync.
    func afterSync() async {
        await offerInterruptedPlayback()
        guard let client else { return }
        let issues = try? await client.libraryHealth()
        let queue = try? await client.subtitleQueueStatus()
        if let issues { LibraryHealthWatch.shared.update(with: issues) }
        if let shows = queue?.shows { announceSubtitleArrivals(shows) }
        // Only on a real answer: counts of zero from a failed request would be
        // saved as the baseline and reported next week as everything "fixed".
        if let issues { weeklySummary(issues: issues, subtitlesDone: queue?.done ?? 0) }
    }

    /// Says once when queued subtitles have arrived, then remembers the counts.
    private func announceSubtitleArrivals(_ shows: [SubtitleQueueStatus.Show]) {
        let defaults = UserDefaults.standard
        // No record yet is a first run: today's counts are the baseline, not news.
        if let seen = defaults.dictionary(forKey: SubtitleArrivals.seenKey) as? [String: Int],
           let message = SubtitleArrivals.message(for: shows, seen: seen) {
            report(message)
        }
        defaults.set(Dictionary(uniqueKeysWithValues: shows.map { ($0.series, $0.done) }),
                     forKey: SubtitleArrivals.seenKey)
    }

    /// Once a week, one line on what changed. See `WeeklySummary`.
    private func weeklySummary(issues: [LibraryHealthIssue], subtitlesDone: Int) {
        var counts: [String: Int] = [:]
        for issue in issues { counts[issue.kind] = issue.count }
        counts["subtitlesDone"] = subtitlesDone
        let now = WeeklySummary.Snapshot(at: Date(), counts: counts)
        let defaults = UserDefaults.standard
        let last = defaults.data(forKey: WeeklySummary.storageKey)
            .flatMap { try? JSONDecoder().decode(WeeklySummary.Snapshot.self, from: $0) }
        guard last == nil || WeeklySummary.isDue(last: last) else { return }
        if let last, let message = WeeklySummary.message(from: last, to: now) { report(message) }
        defaults.set(try? JSONEncoder().encode(now), forKey: WeeklySummary.storageKey)
    }
}

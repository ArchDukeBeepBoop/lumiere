import Foundation
import LumiereKit

/// Telling the server what happened while it was away.
///
/// The half of offline playback that was missing. Watching without a server already
/// worked and already recorded a position, but only in this cache: the report was a
/// `try?` that failed silently, so no other Jellyfin client ever learned of it — and
/// because a sync overwrites local watch state with the server's, the next one
/// replaced the position with a stale zero. Progress made offline was not merely
/// unshared; it was destroyed by the reconnection.
///
/// See `PlaybackOutbox` for the queue itself.
@MainActor
extension AppModel {

    /// Sends everything waiting, oldest first.
    ///
    /// Runs before the catch-up sync rather than after, and that order is the whole
    /// point: the sync pulls the server's watch state down over the local rows, so a
    /// flush that ran afterwards would be sending positions the sync had already
    /// overwritten.
    ///
    /// Failures are left in the queue. A server that went away again mid-flush is
    /// the case this exists for, and the next reconnection tries the same rows.
    func flushPlaybackOutbox() async {
        guard let repository, let client else { return }
        await flushWrites(repository: repository, client: client)
        let pending = (try? await repository.pendingPlayback()) ?? []
        guard !pending.isEmpty else { return }
        Diagnostics.log("[outbox] \(pending.count) titles watched offline to report")

        var sent = 0
        for record in pending {
            do {
                try await client.reportPlaybackStopped(
                    itemId: record.itemId,
                    mediaSourceId: record.mediaSourceId ?? record.itemId,
                    playSessionId: nil,
                    positionSeconds: record.positionSeconds
                )
                // The local row is the newer truth until the next sync confirms it,
                // so it is refreshed here too — otherwise a sync running immediately
                // afterwards could still read a position the server has only just
                // been told about.
                try? await repository.applyLocalProgress(
                    itemId: record.itemId,
                    positionSeconds: record.positionSeconds,
                    played: record.played ? true : nil
                )
                try await repository.clearPendingPlayback(
                    itemId: record.itemId, sentTicks: record.positionTicks
                )
                sent += 1
            } catch {
                Diagnostics.log("[outbox] \(record.itemId) failed: \(error)")
                // Stop at the first transport failure rather than grinding through
                // the rest: the server is away again and every remaining row would
                // fail the same way, each one waiting out its own timeout.
                if ConnectionState.isUnreachable(error) { break }
            }
        }
        Diagnostics.log("[outbox] reported \(sent) of \(pending.count)")
        pendingOfflineProgress = (try? await repository.pendingPlaybackCount()) ?? 0
    }

    /// How many titles have progress this Mac has not managed to report.
    ///
    /// Surfaced rather than flushed in silence: progress that has not left the
    /// machine is worth knowing about, and a number that stays above zero is the
    /// only visible sign that a flush is failing.
    func refreshPendingOfflineCount() async {
        pendingOfflineProgress = (try? await repository?.pendingPlaybackCount()) ?? 0
    }

    /// Watched ticks and favourites made while the server was away, oldest
    /// first. A row the server refuses outright is dropped — the next sync
    /// then shows the server's answer — and a transport failure stops the
    /// flush with the rest kept for next time.
    private func flushWrites(repository: LibraryRepository, client: JellyfinClient) async {
        let writes = await repository.pendingWrites()
        guard !writes.isEmpty else { return }
        Diagnostics.log("[outbox] \(writes.count) ticks and favourites made offline to send")
        for write in writes {
            do {
                switch write.kind {
                case .played: try await client.markPlayed(itemId: write.itemId, played: write.value)
                case .favorite: try await client.markFavorite(itemId: write.itemId, favorite: write.value)
                }
                await repository.clearPendingWrite(write)
            } catch {
                if ConnectionState.isUnreachable(error) { break }
                Diagnostics.log("[outbox] \(write.itemId) refused: \(error)")
                await repository.clearPendingWrite(write)
            }
        }
    }
}

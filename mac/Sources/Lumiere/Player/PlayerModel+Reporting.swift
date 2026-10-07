import Foundation
import LumiereKit
import LumierePlayer

/// Progress reporting, trickplay, and the subtitle line under the title.
///
/// Split out of PlayerModel.swift to keep it under the project's 300-line limit.
/// These are the parts that talk *about* playback rather than driving it.
extension PlayerModel {
    // MARK: - Reporting

    func reportIfDue() {
        guard position - lastReportedAt >= reportInterval else { return }
        lastReportedAt = position
        Task { await report(force: false) }
    }

    func report(force: Bool) async {
        guard didStart, let mediaSourceId else { return }
        if force { lastReportedAt = position }
        let position = self.position

        // Locally as well as to the server, every ten seconds.
        //
        // This used to tell only the server, which meant the cache learned your
        // position exactly once — in `finish()`, on a clean stop. Anything that was
        // not a clean stop lost the lot: a crash, a force quit, the power going,
        // or the app being killed while `finish` waited on an unreachable server.
        // Two hours in and the row still said zero.
        //
        // One UPDATE against one row on a ten-second timer, which is nothing beside
        // the HTTP request it accompanies.
        // Not announced: see `applyLocalProgress`. This is a heartbeat, not a
        // change anyone is looking at.
        try? await repository.applyLocalProgress(
            itemId: itemId, positionSeconds: position, announce: false
        )

        do {
            try await client.reportPlaybackProgress(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                playSessionId: playSessionId,
                positionSeconds: position,
                isPaused: state == .paused
            )
            // Anything queued for this title from an earlier offline stretch is now
            // older than what the server has just been told.
            try? await repository.clearPendingPlayback(
                itemId: itemId, sentTicks: Int64(position * 10_000_000)
            )
        } catch {
            // This used to be a `try?`, and the silence was the bug. Watching
            // offline recorded a position in the cache and nowhere else — no other
            // Jellyfin client learned of it, and the next sync overwrote the local
            // row with the server's stale zero. See `PlaybackOutbox`.
            guard ConnectionState.isUnreachable(error) else { return }
            try? await repository.enqueuePlayback(
                itemId: itemId,
                positionSeconds: position,
                played: false,
                mediaSourceId: mediaSourceId
            )
        }
    }

    /// Trickplay metadata, if the server has generated any.
    ///
    /// Absent on most libraries — Jellyfin only builds it when asked — so this
    /// failing is normal and leaves the scrubber as a plain bar.
    func loadTrickplay(mediaSourceId: String) async {
        guard let sheets = try? await client.trickplay(itemId: itemId),
              let bySize = sheets[mediaSourceId] ?? sheets.values.first,
              !bySize.isEmpty else {
            return
        }
        // Prefer the widest sheet that is still small enough to decode instantly
        // while dragging; 320px is Jellyfin's usual default.
        let candidates = bySize.compactMap { key, value -> (Int, TrickplayInfo)? in
            Int(key).map { ($0, value) }
        }
        guard let chosen = candidates.filter({ $0.0 <= 480 }).max(by: { $0.0 < $1.0 })
            ?? candidates.min(by: { $0.0 < $1.0 }) else { return }

        trickplayWidth = chosen.0
        trickplay = chosen.1
    }

    func subtitleText(for entry: LibraryEntry) -> String? {
        if entry.item.itemType == .episode, let code = entry.item.episodeCode() {
            return "\(code) · \(entry.item.name)"
        }
        return entry.item.productionYear.map(String.init)
    }
}

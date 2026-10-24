import Foundation
import LumiereKit
import LumierePlayer

/// Playing a file that is simply on this Mac.
///
/// Split from PlayerModel+Session.swift for the project's 300-line rule, and it is
/// a clean seam: the other half exists to negotiate with a server — playback info,
/// a stream URL, a play session, a decision about who transcodes — and none of
/// that has any meaning here.
@MainActor
extension PlayerModel {

    /// Plays a file from disk.
    ///
    /// Always mpv, and no decision is computed. `PlaybackPlanner` answers "will the
    /// *server* have to transcode this", which is a question about a server; a file
    /// opened locally is read by the engine itself, and mpv opens everything the
    /// planner would have routed to it plus everything it would have routed to
    /// AVPlayer. Running the planner would mean probing the file first — work with
    /// no answer attached.
    ///
    /// Resume, watch state, subtitle offsets and track memory all still work,
    /// because they are keyed to the item id and the row is an ordinary cache row.
    /// What is genuinely absent is anything only a server knows: no chapters, no
    /// trickplay, no reporting to another client.
    func startLocal(file: URL, mpvAvailable: Bool) async {
        guard mpvAvailable else {
            state = .failed(
                "Local files are played by mpv, which is not available in this build."
            )
            return
        }
        let entry = await repository.entryWithServerPosition(id: itemId)
        title = entry?.item.name ?? file.deletingPathExtension().lastPathComponent
        subtitleLine = file.deletingLastPathComponent().lastPathComponent
        let resumeAt = entry?.userData?.resumeSeconds ?? 0

        let engine = MPVEngine()
        mpvEngine = engine
        self.engine = engine
        attachCallbacks(to: engine)

        do {
            try await engine.load(
                PlaybackRequest(url: file, startAt: resumeAt)
            )
        } catch {
            state = .failed(ConnectionState.message(for: error))
            return
        }

        subtitleDelay = (try? await repository.subtitleOffset(itemId: itemId)) ?? 0
        if subtitleDelay != 0 { await engine.setSubtitleDelay(subtitleDelay) }
        await restoreFlip()
        await restoreAudioDelay()
        await applyShowPreset()

        await engine.play()
        state = .playing
        duration = await engine.duration
        await waitForTracks()
        await loadLocalNeighbours()
        Diagnostics.log("[playback] \(itemId) local file via mpv")
    }

    /// Next and Previous for a file with no season: the files beside it in its
    /// folder, in Finder's name order. Opening episode 3 offers episode 4.
    func loadLocalNeighbours() async {
        let siblings = (try? await repository.localSiblings(of: itemId)) ?? []
        guard let index = siblings.firstIndex(where: { $0.id == itemId }) else { return }
        queue = siblings
        queueIndex = index
        previousEpisode = index > 0 ? siblings[index - 1] : nil
        nextEpisode = index + 1 < siblings.count ? siblings[index + 1] : nil
    }
}

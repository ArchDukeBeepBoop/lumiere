import Foundation
import LumiereKit
import LumierePlayer

/// Finding a subtitle mid-film, and making it land on the line.
///
/// The server does the work — it holds the provider key, it has ffmpeg, and
/// it writes beside the video. This is the half that knows what is playing,
/// hands the result to the engine, and says what happened.
@MainActor
extension PlayerModel {

    /// What a search or a sync is doing, for the panel to draw.
    enum SubtitleTask: Equatable {
        case idle
        case searching
        case downloading(Int)
        case syncing
        /// What just happened, for the panel to show until the next action.
        /// Not a `PlayerAction`: that type is a seek with a way back, and
        /// there is nothing to undo here that the delay control cannot.
        case done(String)
        case failed(String)
        /// A shift was found but below the owner's threshold: offered, not
        /// applied. A guess you can see and try is worth more than a refusal.
        case unsure(SubtitleSync)
        /// An unsure shift was tried; the delay before it, to go back to.
        case tried(previousDelay: Double)
        /// A shift is in force; offered for the rest of the season, since a
        /// fansub timed for another release is usually out by the same amount
        /// in every episode. Only offered — see `setSubtitleDelay`.
        case offerSeason(Double, message: String)
    }

    /// Asks the server what it can find for this file.
    func findSubtitles(language: String? = nil) async {
        subtitleTask = .searching
        subtitleResults = []
        let wanted = language ?? subtitleSearchLanguage
        do {
            subtitleResults = try await client.findSubtitles(itemId: itemId, language: wanted)
            subtitleTask = .idle
            if subtitleResults.isEmpty {
                subtitleTask = .failed("Nothing found for this episode.")
            }
        } catch {
            subtitleTask = .failed(Self.readable(error))
        }
    }

    /// Fetches one, loads it into the picture, and applies the shift the
    /// server measured — where it is sure enough to act on.
    ///
    /// Syncing is asked for in the same call because it is the same wish: a
    /// subtitle cut for another release is why anyone goes looking, and a
    /// fetch that leaves the timing alone hands back a file to fix by hand.
    func downloadSubtitle(_ candidate: RemoteSubtitle) async {
        subtitleTask = .downloading(candidate.fileId)
        do {
            let result = try await client.downloadSubtitle(
                itemId: itemId, fileId: candidate.fileId,
                language: candidate.language,
                sync: Preference.subtitleSyncOnDownload.value,
                maxShiftSeconds: Preference.subtitleSyncMaxShiftSeconds.value
            )
            await loadFetchedSubtitle(index: result.index, language: candidate.language)
            if let offset = result.offset, let confidence = result.confidence {
                await applySync(SubtitleSync(
                    offset: offset, confidence: confidence,
                    trusted: confidence >= Self.minimumSyncConfidence
                ))
            } else {
                subtitleTask = .done("Subtitle added.")
            }
        } catch {
            subtitleTask = .failed(Self.readable(error))
        }
    }

    /// Aligns whichever subtitle is showing against this file's audio.
    func syncCurrentSubtitle() async {
        guard let index = selectedSubtitleTrack else {
            subtitleTask = .failed("No subtitle is showing.")
            return
        }
        subtitleTask = .syncing
        do {
            await applySync(try await client.syncSubtitle(
                itemId: itemId, index: index,
                maxShiftSeconds: Preference.subtitleSyncMaxShiftSeconds.value
            ))
        } catch {
            subtitleTask = .failed(Self.readable(error))
        }
    }

    /// Applies a measured shift, or reports that it would be a guess.
    private func applySync(_ sync: SubtitleSync) async {
        // The owner's threshold, not the server's verdict: how sure is sure
        // enough is a preference, and Settings is where it is set.
        guard sync.confidence >= Self.minimumSyncConfidence else {
            if sync.confidence > 0, sync.offset != 0 {
                subtitleTask = .unsure(sync)
                return
            }
            subtitleTask = .failed(String(
                format: "Could not match the subtitle to the audio (%.0f%% sure of %+.1f s).",
                sync.confidence * 100, sync.offset
            ))
            return
        }
        await setSubtitleDelay(sync.offset)
        subtitleTask = .offerSeason(sync.offset, message: String(
            format: "Shifted %+.1f s to match the audio.", sync.offset
        ))
    }

    /// Applies a shift the sync was not sure of, keeping the way back.
    func tryUnsureSync(_ sync: SubtitleSync) async {
        let previous = subtitleDelay
        await setSubtitleDelay(sync.offset)
        subtitleTask = .tried(previousDelay: previous)
    }

    /// Saves the same shift against every other episode in this season's queue.
    func applyDelayToSeason(_ seconds: Double) async {
        let others = queue.map(\.id).filter { $0 != itemId }
        for id in others {
            try? await repository.saveSubtitleOffset(seconds, itemId: id)
        }
        subtitleTask = .done(String(
            format: "%+.1f s saved for %d more episodes.", seconds, others.count
        ))
    }

    /// Undoes `tryUnsureSync`.
    func revertTriedSync(to previous: Double) async {
        await setSubtitleDelay(previous)
        subtitleTask = .done(String(format: "Back to %+.1f s.", previous))
    }

    /// Hands the engine the subtitle the server just saved.
    ///
    /// By its path when this session is playing from disk — the server wrote
    /// it beside the video, so it is right there — and by the streaming URL
    /// otherwise. Either way mpv adds and selects it without reloading the
    /// file, so the picture does not jump back to the beginning.
    private func loadFetchedSubtitle(index: Int, language: String) async {
        guard let engine else { return }
        guard let url = StreamBuilder.subtitleURL(
            serverURL: client.session.serverURL, itemId: itemId,
            mediaSourceId: mediaSourceId ?? itemId, streamIndex: index
        ) else { return }
        let added = await engine.addSubtitle(
            url: url, title: "Downloaded", language: language
        )
        if !added {
            subtitleTask = .failed("This engine cannot add a subtitle mid-film.")
            return
        }
        await refreshTracks()
    }

    /// The language a search asks for: whatever this library prefers, else
    /// English — the same default the track picker uses.
    var subtitleSearchLanguage: String {
        let chosen = Preference.subtitleSearchLanguage.value.trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? "en" : chosen
    }

    /// How sure a sync must be before it is applied. Settings › Subtitles.
    static var minimumSyncConfidence: Double {
        Double(min(max(Preference.subtitleSyncTrustPercent.value, 10), 90)) / 100
    }

    private static func readable(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.isEmpty ? "The server could not answer." : text
    }
}

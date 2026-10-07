import Foundation
import LumiereKit
import LumierePlayer

/// Starting and ending a playback session: choosing an engine, handing it a
/// stream, and tearing it down.
///
/// Split from PlayerModel.swift for the project's 300-line limit, along the seam
/// that was already marked — this half decides *what* plays, where the rest is
/// what the views read while it does.
@MainActor
extension PlayerModel {

    // MARK: - Lifecycle

    func start(mpvAvailable: Bool) async {
        state = .preparing

        do {
            // A file on this Mac, opened directly. No PlaybackInfo, no stream URL,
            // no session with anything — the whole point of the local library is
            // that a server is not involved, so asking one anything here would be
            // a four-second timeout before every play.
            if let file = try? await repository.localFile(for: itemId) {
                await startLocal(file: file, mpvAvailable: mpvAvailable)
                return
            }

            let entry = await repository.entryWithServerPosition(id: itemId)
            if let item = entry?.item {
                preferenceKey = LibraryRepository.trackPreferenceKey(for: item)
                libraryPreferenceKey = item.libraryId.map(
                    LibraryRepository.libraryTrackPreferenceKey(libraryId:)
                )
            }
            title = entry?.item.seriesName ?? entry?.item.name ?? ""
            subtitleLine = entry.map(subtitleText(for:)) ?? nil
            logo = await logoFor(entry)
            // Not the raw position. See `LibraryEntry.resumeStart`.
            let resumeAt = entry?.resumeStart ?? 0
            // Only worth announcing if it is actually somewhere. A file resumed
            // twelve seconds in is a file that starts at the beginning as far as
            // anyone watching is concerned, and a notice about it is noise.
            resumedFrom = resumeAt > Self.resumeNoticeSeconds * 2 ? resumeAt : nil

            // Ask the server, but fall back to the cached detail payload if it is
            // unreachable. Without a play session the server cannot be told about
            // progress, but the decision and the technical panel still work —
            // which is the difference between "your server is asleep" and a blank
            // error screen.
            // Bounded, because someone is staring at a spinner. URLSession's own
            // 20-second timeout is right for a background sync and much too long
            // here when the cache already holds the answer.
            let cap = Self.bitrateCap
            let info = await Timeout.run(seconds: 4) { [client, itemId] in
                // The cap goes to the server too, not only into the local
                // decision: it is what makes Jellyfin's own answer about this
                // source honest rather than computed against an unlimited client.
                try? await client.playbackInfo(itemId: itemId, maxBitrate: cap)
            }
            var sources = info?.mediaSources ?? []
            if sources.isEmpty {
                sources = (try? await repository.detail(id: itemId))?.mediaSources ?? []
            }

            // The picked version where one was picked. Falling through to `first`
            // whenever it is missing keeps a stale id from making a title unplayable.
            let preferred = preferredSourceId.flatMap { id in
                sources.first { $0.id == id }
            }
            guard let source = preferred ?? sources.first else {
                state = .failed("No playable file for this item, and nothing cached to fall back on.")
                return
            }
            mediaSourceId = source.id
            playSessionId = info?.playSessionId

            // Which tracks this session starts on, resolved from the server's own
            // stream list before an engine exists. A transcode bakes them into the
            // stream, so they have to be known now rather than picked afterwards —
            // see `PreferredTracks`.
            let tracks = PreferredTracks.resolve(
                source: source,
                preference: await rememberedPreference(),
                subtitleKind: preferredSubtitleKind
            )
            self.startingTracks = tracks

            // The bitrate cap is a real input to the decision, not a display
            // preference: above it, no client can avoid a server transcode.
            //
            // The subtitle index is one too, and it had never been passed: rule 5
            // of the planner — "the chosen subtitle needs a renderer" — could not
            // fire, because nothing ever told it what had been chosen. A styled or
            // bitmap track in an MP4 went to AVPlayer, which cannot draw it.
            let decision = PlaybackPlanner.decide(
                source: source,
                capabilities: capabilities,
                options: .init(
                    mpvAvailable: mpvAvailable,
                    selectedSubtitleIndex: tracks.subtitleIndex,
                    maxBitrate: cap
                )
            )
            self.decision = decision
            self.videoWidth = source.videoStream?.width

            // Logged, not just shown. "Why is my server transcoding?" is the
            // question this app exists to answer, and the answer should be
            // greppable rather than requiring a screenshot of a badge.
            let videoCodec = source.videoStream?.codec ?? "none"
            let audioCodec = source.defaultAudioStream?.codec ?? "none"
            Diagnostics.log(
                "[playback] \(itemId) \(source.container ?? "?")/\(videoCodec)/\(audioCodec)"
                + " -> \(decision.route.rawValue) via \(decision.engine.rawValue)"
                + " (\(decision.reason.rawValue))"
                + (decision.toneMapDolbyVision ? " tone-mapped" : "")
                + (decision.softwareDecode ? " software-decode" : "")
            )

            guard let request = await playbackRequest(
                for: decision, source: source, resumeAt: resumeAt
            ) else {
                state = .failed("Couldn't build a playback URL for this file.")
                return
            }

            // Linked segments need mpv, whatever the decision said: AVFoundation
            // has no idea ordered chapters exist and would play the body alone.
            let engineKind = request.linkedFiles.isEmpty ? decision.engine : .mpv
            if engineKind != decision.engine {
                Diagnostics.log("[playback] \(itemId) switched to mpv for linked segments")
            }
            let engine: any PlayerEngine
            switch engineKind {
            case .avPlayer:
                let av = AVPlayerEngine()
                avEngine = av
                engine = av
            case .mpv:
                let mpv = MPVEngine()
                mpvEngine = mpv
                engine = mpv
            }
            self.engine = engine
            attachCallbacks(to: engine)

            // Bounded, like every other network call in this method. An unbounded
            // load against an unreachable server left the player on a bare spinner
            // forever — and until the Close button was drawn in that state too,
            // there was no way out of it.
            switch await Timeout.run(seconds: 30, operation: { () -> LoadOutcome? in
                do {
                    try await engine.load(request)
                    return .ok
                } catch PlayerEngineError.engineUnavailable(let detail) {
                    return .unavailable(detail)
                } catch {
                    return .failed(
                        (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }) {
            case .ok:
                break
            case .unavailable(let detail):
                // Named rather than shown as a raw mpv string. PlayerView has
                // carried a written explanation for this case since the engine
                // landed — "check that libmpv is installed" — and nothing ever
                // assigned the state, so the screen could not be reached and the
                // user got mpv's own wording for a problem about the app's bundle.
                Diagnostics.log("[playback] engine unavailable: \(detail)")
                state = .engineNotAvailable(decision)
                return
            case .failed(let message):
                state = .failed(message)
                return
            case nil:
                state = .failed("The file didn't start playing.")
                return
            }

            // Loop does not carry across files. Turning it on for one thing and
            // discovering the next one repeating is a player that will not stop,
            // with nothing on screen saying why.
            isLooping = false
            await engine.setLooping(false)

            // The remembered level, applied to the engine this session just
            // built: `volume` carries it across files, but a fresh engine starts
            // at whatever its own default is and would play the first file loud.
            await engine.setVolume(volume)
            await engine.setMuted(isMuted)

            let boost = UserDefaults.standard.double(forKey: "defaultVolumeBoost")
            if boost >= 100 {
                volumeBoost = boost
                await engine.setVolumeBoost(boost)
            }
            await engine.setAudioFilters(enhanceDialogue: Preference.enhancesDialogue.value,
                                         reduceLoud: Preference.reducesLoudSounds.value)

            // This file's own offset, if it ever needed one. Read here rather than
            // carried over, so playing the next episode starts from nothing and a
            // correction made for one badly-timed track stays with that track.
            subtitleDelay = (try? await repository.subtitleOffset(itemId: itemId)) ?? 0
            if subtitleDelay != 0 { await engine.setSubtitleDelay(subtitleDelay) }
            await restoreFlip(); await restoreAudioDelay()
            await engine.play()
            state = .playing
            duration = await engine.duration

            // Chapters and trickplay come from the cached detail payload, so they
            // are available even when the server is unreachable.
            if let detail = try? await repository.detail(id: itemId) {
                chapters = detail.chapters ?? []
            }
            await loadTrickplay(mediaSourceId: source.id)
            // Waits rather than reading once: the engine has usually not finished
            // parsing tracks at this point, and a single empty read is what left the
            // language menus blank until the file was reopened.
            await waitForTracks()
            // After the tracks are known, so the remembered language can be matched
            // against what this particular file actually contains.
            await applyRememberedTracks()
            await refreshStatistics()
            await loadEpisodeContext()

            try? await client.reportPlaybackStart(
                itemId: itemId,
                mediaSourceId: source.id,
                playSessionId: playSessionId,
                positionSeconds: resumeAt
            )
            didStart = true
        }
        // No catch: every failure inside now names itself — a missing engine, a
        // load that timed out, a server that refused — and a generic catch-all
        // would only be reachable by making one of those anonymous again.
    }

    // Not private: the local path in PlayerModel+Local.swift attaches the same
    // callbacks, and a second copy of them is a second place for a tick handler
    // to be forgotten.
    func attachCallbacks(to engine: any PlayerEngine) {
        engine.onTick = { [weak self, weak engine] seconds in
            guard let self else { return }
            // The first tick is the proof the engine is decoding rather than
            // merely initialised, which is the difference worth logging.
            if !self.didTick, seconds > 0 {
                self.didTick = true
                Diagnostics.log("[playback] first frame at \(String(format: "%.2f", seconds))s")
            }
            // A tick that arrives while a seek is out reports where the picture
            // was, not where it is going — and drawing it snaps the scrubber
            // back to the old place for a frame, which reads as the bar fighting
            // the hand.
            // Nor between two coalesced seeks: the count drops to zero for an
            // instant there, and a tick let through set the position to the
            // keyframe the last seek landed on, so a held key stepped from
            // there rather than from where it had asked to be — fifty presses
            // of "ten seconds on" added up to well under five hundred.
            if self.seeksInFlight == 0, !self.isScrubSeekInFlight, self.keyScan == nil { self.position = seconds }
            if self.duration == 0, let engine {
                Task { self.duration = await engine.duration }
            }
            self.reportIfDue()
            self.autoSkipIfDue()
        }
        engine.onEnded = { [weak self] in
            Task { await self?.finish(markPlayed: true); self?.endedCount += 1 }
        }
        engine.onError = { [weak self] error in
            self?.state = .failed(error.localizedDescription)
        }
    }

    /// The logo to lead the title bar with: the item's own, else its series'.
    private func logoFor(_ entry: LibraryEntry?) async -> (itemId: String, tag: String)? {
        guard let item = entry?.item else { return nil }
        if let tag = item.logoTag { return (item.id, tag) }
        guard let seriesId = item.seriesId,
              let series = try? await repository.entry(id: seriesId),
              let tag = series.item.logoTag
        else { return nil }
        return (seriesId, tag)
    }
}

/// How loading a file ended.
///
/// A named type rather than a thrown error, because the load runs inside
/// `Timeout.run`, whose closure cannot throw — and collapsing "libmpv is missing"
/// into the same string as "the server hung up" is what made the engine-missing
/// screen unreachable in the first place.
enum LoadOutcome: Sendable {
    case ok
    case failed(String)
    case unavailable(String)
}

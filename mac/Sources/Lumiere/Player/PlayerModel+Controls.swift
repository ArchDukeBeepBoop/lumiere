import Foundation
import LumiereKit
import LumierePlayer

/// Transport, tracks and video adjustments, split out of `PlayerModel` so the
/// lifecycle file stays about starting and stopping playback.
extension PlayerModel {

    // MARK: - Volume

    func setVolume(_ value: Double) async {
        volume = max(0, min(1, value))
        if volume > 0 && isMuted { isMuted = false }
        PlayerVolume.remember(volume)
        await engineRef?.setVolume(volume)
        await engineRef?.setMuted(isMuted)
    }

    func toggleMute() async {
        isMuted.toggle()
        await engineRef?.setMuted(isMuted)
    }

    func nudgeVolume(by delta: Double) async {
        await setVolume(volume + delta)
    }

    func setVolumeBoost(_ percent: Double) async {
        volumeBoost = percent
        await engineRef?.setVolumeBoost(percent)
    }

    /// Repeats the current file.
    ///
    /// Deliberately not persisted, and deliberately reset by loading anything
    /// new — see `PlayerModel.isLooping`. Both engines suppress their end
    /// callback while it is on, so nothing queues the next episode underneath.
    func toggleLooping() async {
        isLooping.toggle()
        await engineRef?.setLooping(isLooping)
        say(isLooping ? "Loop on" : "Loop off")
    }

    /// One frame at a time, while paused.
    ///
    /// The model stays paused afterwards on purpose: stepping is something you
    /// do while looking at a single frame, and a player that resumed after each
    /// step would carry you past the thing you were trying to see.
    func stepFrame(_ frames: Int) async {
        guard let engine = engineRef else { return }
        if isPlaying { pause() }
        await engine.step(frames: frames)
        position = await engine.position
    }

    // MARK: - Rate

    func setPlaybackSpeed(_ speed: Double) async {
        playbackSpeed = speed
        await engineRef?.setRate(speed)
        say(speed == 1 ? "Normal speed" : String(format: "Speed %.2g×", speed))
    }

    // MARK: - Tracks

    /// Reads the engine's live track list.
    ///
    /// Not the media source's stream list: mpv renumbers and can add external
    /// subtitle files, so selecting by the server's index would pick the wrong
    /// track on any file whose streams are not numbered consecutively.
    func refreshTracks() async {
        guard let engine = engineRef else { return }
        audioTracks = await engine.audioTracks
        subtitleTracks = await engine.subtitleTracks
    }

    /// Waits until the engine has actually parsed the file's tracks.
    ///
    /// Asking once, immediately after `play()`, is a race — and one that lost often
    /// enough to read as a bug. mpv reports nothing until it has demuxed the header,
    /// and AVFoundation loads its tracks asynchronously too, so that first read came
    /// back empty; nothing re-read them afterwards, so the language menus stayed
    /// empty and the remembered audio and subtitle choices had no track list to
    /// match against. Reopening the same file found it warm and worked, which is
    /// exactly the shape of a race.
    ///
    /// Polled rather than awaited on a notification, because the two engines signal
    /// readiness in completely different ways and neither exposes it through
    /// `PlayerEngine`. Bounded, so a genuinely track-less file costs a moment rather
    /// than hanging.
    func waitForTracks(timeout: Duration = .seconds(4)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            await refreshTracks()
            if !audioTracks.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
        }
        // One final read, so a file whose tracks appear right on the deadline is not
        // reported as having none.
        await refreshTracks()
    }

    func selectAudioTrack(_ id: Int?) async {
        selectedAudioTrack = id
        await engineRef?.selectAudioTrack(id: id)
        await rememberTrackChoice()
    }

    func selectSubtitleTrack(_ id: Int?) async {
        selectedSubtitleTrack = id
        await engineRef?.selectSubtitleTrack(id: id)
        await rememberTrackChoice()
    }

    /// Stores the choice against the series, by language.
    ///
    /// Saved on every change rather than at the end of playback: quitting mid-episode
    /// is the common case, and a preference only written on a clean exit is a
    /// preference that usually is not written.
    func rememberTrackChoice() async {
        guard let key = preferenceKey else { return }
        let audio = audioTracks.first { $0.id == selectedAudioTrack }?.language
        let subtitle = subtitleTracks.first { $0.id == selectedSubtitleTrack }?.language

        // Never write a nil audio language over a known one, and this is the whole
        // reason: `selectedAudioTrack` is nil until something explicitly sets it,
        // and nothing seeds it from what the engine is already playing. So turning
        // *subtitles* on — the single most common thing anyone does in this player —
        // wrote a series row saying "no audio preference". That row then shadows the
        // library default for good, and `TrackPreference.match(language: nil)` falls
        // through to the file's default track, which on an anime release is the
        // English dub. One tap on a subtitle track and the show was dubbed forever.
        var carriedAudio = audio
        if carriedAudio == nil {
            carriedAudio = (try? await repository.trackPreference(key: key))?.audioLanguage
            if carriedAudio == nil, let libraryKey = libraryPreferenceKey {
                carriedAudio = (try? await repository.trackPreference(
                    key: libraryKey
                ))?.audioLanguage
            }
        }

        try? await repository.saveTrackPreference(
            TrackPreference(
                key: key,
                audioLanguage: carriedAudio,
                subtitleLanguage: subtitle,
                // "Off" is a real choice and has to be distinguishable from
                // "never picked anything".
                subtitlesEnabled: selectedSubtitleTrack != nil
            )
        )
    }

    /// Applies the remembered languages to this file's tracks.
    ///
    /// Matched by language, never by index: the same series can number its Japanese
    /// track differently from one episode to the next, so a remembered index would
    /// eventually start playing the dub.
    /// Which kind of subtitle track to reach for, from Settings.
    ///
    // MARK: - Video adjustments

    var supportsVideoAdjustments: Bool {
        engineRef?.supportsVideoAdjustments ?? false
    }

    func setAspect(_ aspect: AspectOverride) async {
        aspectOverride = aspect
        await engineRef?.setAspectOverride(aspect)
    }

    func setVerticalShift(_ fraction: Double) async {
        verticalShift = fraction
        await engineRef?.setVerticalShift(fraction)
    }

    func setFlip(horizontal: Bool, vertical: Bool) async {
        flipHorizontal = horizontal
        flipVertical = vertical
        await engineRef?.setFlip(horizontal: horizontal, vertical: vertical)
        await rememberFlip()
    }

    func setUpscaling(_ mode: UpscalingMode) async {
        upscaling = mode
        await engineRef?.setUpscaling(mode)
    }

    var supportsSubtitleDelay: Bool {
        engineRef?.supportsSubtitleDelay ?? false
    }

    /// Shifts subtitles against the audio, and remembers it against this item.
    ///
    /// Against the item and nothing wider. The offset corrects a mismatch between
    /// one subtitle track and one audio track; the next episode is a different file
    /// with a different track, and applying this to it would break a track that was
    /// in sync. Setting it back to zero forgets the row — see `SubtitleOffset`.
    func setSubtitleDelay(_ seconds: Double) async {
        // A minute either way. Ten seconds was the range a hand would ever
        // nudge, and the syncer answers in whole half-minutes: a release cut
        // for a different master is thirty seconds out, not three.
        let clamped = max(-60, min(60, seconds))
        subtitleDelay = clamped
        await engineRef?.setSubtitleDelay(clamped)
        say(clamped == 0 ? "Subtitles in sync" : String(format: "Subtitles %+.1f s", clamped))
        try? await repository.saveSubtitleOffset(clamped, itemId: itemId)
    }

    /// Resizes subtitles now, and remembers it for the next file.
    func setSubtitleSize(_ size: SubtitleSize) async {
        subtitleSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "subtitleSize")
        await engineRef?.setSubtitleSize(size)
    }

    /// Restyles subtitles now, and remembers it for the next file.
    ///
    /// The same shape as the size above, and it should have existed alongside it
    /// from the start: the style was applied once when the engine started, so a
    /// preset chosen in Settings did nothing until the next file was opened. A
    /// preset you cannot see the effect of is one you cannot choose between.
    func setSubtitleStyle(_ style: SubtitleStyle) async {
        subtitleStyle = style
        UserDefaults.standard.set(style.id, forKey: "subtitleStyle")
        await engineRef?.setSubtitleStyle(style)
    }

    /// The z / Z bindings, and the panel's ± buttons. A tenth of a second: small
    /// enough to land on the right offset, large enough to hear the difference.
    func nudgeSubtitleDelay(_ direction: Double) async {
        await setSubtitleDelay(subtitleDelay + 0.1 * direction)
    }

    // MARK: - Chapters

    /// The chapter containing the current position.
    var currentChapter: Chapter? {
        chapters.last { $0.startSeconds <= position + 0.5 }
    }

    func jumpToChapter(_ chapter: Chapter) async {
        await seek(to: chapter.startSeconds)
    }

    // MARK: - Statistics

    func refreshStatistics() async {
        guard let engine = engineRef else { return }
        statistics = await engine.statistics
        // The scrub bar's buffered band comes off the same poll rather than a
        // second one: the cache depth is already in this payload, and asking the
        // engine twice a second for two views of one number is how a player ends
        // up stuttering its own overlay.
        bufferedSeconds = statistics.cacheSeconds.map { position + $0 }
    }

    // MARK: - Time formatting

    /// Elapsed, as `1:02:03` or `2:03`.
    var elapsedText: String { Self.timecode(position) }

    /// Remaining, negative-signed. Infuse shows time left rather than duration,
    /// which is the number you actually want mid-film.
    var remainingText: String {
        guard duration > 0 else { return "--:--" }
        return "-" + Self.timecode(max(0, duration - position))
    }

    var durationText: String { Self.timecode(duration) }

    /// Forwards to the one implementation. See `Timecode`.
    static func timecode(_ seconds: Double) -> String {
        Timecode.string(seconds)
    }
}

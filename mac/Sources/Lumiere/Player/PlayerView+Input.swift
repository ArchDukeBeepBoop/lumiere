import SwiftUI
import AppKit
import LumiereKit
import LumierePlayer

/// Everything that reacts to the user or the clock: chrome auto-hide, the
/// statistics and menu-bridge pollers, menu commands, and the keyboard grammar.
///
/// Split out of PlayerView.swift, which had grown well past the project's
/// 300-line limit. No state of its own — it reads PlayerView's.
extension PlayerView {
    // MARK: - Idle handling

    /// Shows the chrome and restarts the countdown to hiding it.
    /// How long movement is ignored after the pointer leaves the bar. Long enough
    /// for the gesture that left it to finish, short enough that a deliberate move
    /// a moment later still brings the controls back.
    static let wakeSuppression: TimeInterval = 0.5

    func wakeChrome() {
        // The bar was just dismissed by leaving it; the tail of that same gesture
        // must not bring it straight back. See `suppressWakeUntil`.
        if Date() < suppressWakeUntil { return }

        // Hover fires on every pointer sample, so tearing the countdown down and
        // rebuilding it each time would churn a Task per frame. Once the chrome is
        // already up, restarting the timer a few times a second is plenty.
        let now = Date()
        if showsChrome, now.timeIntervalSince(lastWake) < 0.2 { return }
        lastWake = now

        showsChrome = true
        showsGlance = false
        NSCursor.unhide()
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled else { return }
            // Never hide while a panel is open or playback is paused — the
            // pointer is idle, but the user is not done.
            // The tracks panel counts as an open panel for the same reason the
            // settings sheet does: it is drawn inside the chrome, so fading the
            // chrome would take a list the user is reading away with it.
            // Paused too, now: the controls give way to the pause card — see
            // `PlayerPauseCard` — rather than staying over a still frame.
            guard !showsSettings, openTab == nil, !showsQueue, !isPointerOnChrome,
                  model != nil else { return }
            showsChrome = false
            showsGlance = true
            // The pointer goes with the controls. `setHiddenUntilMouseMoves` brings
            // it back by itself on the next movement, so nothing has to track the
            // mouse to restore it — and the same movement wakes the chrome anyway.
            NSCursor.setHiddenUntilMouseMoves(true)
            // Then the glance goes too. See `PlayerGlance`.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsGlance = false
        }
    }

    /// The pointer entering or leaving one of the bars.
    ///
    /// Leaving restarts the countdown rather than waiting for the next pointer
    /// sample, which is what makes "one second after the mouse moves away" mean
    /// what it says: sliding off the bar and stopping dead still hides the chrome
    /// a second later, with no further movement needed to start the clock.
    func onChromeHover(_ isInside: Bool) {
        isPointerOnChrome = isInside
        guard !isInside else { return }

        // Gone now, not a second from now.
        //
        // Leaving the bar is an unambiguous statement that you are finished with it,
        // and waiting out an idle countdown after that reads as lag. The countdown
        // still exists for the other case — the pointer resting *on the picture*,
        // where nothing has been aimed at and the controls are simply in the way.
        //
        // Never while something is mid-interaction: a settings sheet, an open track
        // list, or a paused film all mean the person is not done, and the panels are
        // drawn inside this chrome so hiding it takes them with it.
        guard !showsSettings, openTab == nil, !showsQueue, model?.isPlaying == true else {
            lastWake = .distantPast
            wakeChrome()
            return
        }

        idleTask?.cancel()
        suppressWakeUntil = Date().addingTimeInterval(Self.wakeSuppression)
        showsChrome = false
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    /// The HUD is polled only while visible: statistics cost a round of property
    /// reads per tick and there is no reason to pay for them otherwise.
    ///
    /// The scrub bar's buffered band reads the same poll, so the chrome being up
    /// is a second reason to run it — but only on mpv. AVPlayer reports no cache
    /// depth at all, so a poll there would buy the scrubber nothing and cost an
    /// asynchronous track load every second for as long as the controls are shown.
    func startStatisticsPolling() {
        statsTask?.cancel()
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let model else { continue }
                let wantsBuffered = showsChrome && model.mpvEngine != nil
                guard model.showsStatisticsHUD || wantsBuffered else { continue }
                await model.refreshStatistics()
            }
        }
    }

    /// Mirrors the slice of player state the menu bar renders from.
    ///
    /// Polled rather than pushed on every property change: SwiftUI rebuilds the
    /// menus whenever the bridge changes, and publishing per frame tick would
    /// rebuild them four times a second for no benefit.
    func startBridgePublishing() {
        publishTask?.cancel()
        publishTask = Task {
            while !Task.isCancelled {
                if let model {
                    let snapshot = PlayerMenuState(model)
                    // Only assign on a real change: a new value re-evaluates the
                    // whole scene, menus included, and doing that four times a
                    // second for identical state is pure waste.
                    if snapshot != bridge.menuState {
                        bridge.menuState = snapshot
                        Diagnostics.log(
                            "[menu] published active=\(snapshot.isActive)"
                            + " audio=\(snapshot.audioTracks.count)"
                            + " subs=\(snapshot.subtitleTracks.count)"
                        )
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func perform(_ command: PlayerCommand) {
        guard let model else { return }
        wakeChrome()

        switch command {
        case .togglePlayPause: Task { await model.togglePlayPause() }
        case .skip(let seconds): Task { await model.skip(by: seconds) }
        case .seek(let seconds): Task { await model.seek(to: seconds) }
        case .chapter(let forward): Task { await model.skipChapter(forward: forward) }
        case .nudgeVolume(let delta): Task { await model.nudgeVolume(by: delta) }
        case .toggleMute: Task { await model.toggleMute() }
        case .toggleFullScreen: toggleFullScreen()
        case .setSpeed(let speed): Task { await model.setPlaybackSpeed(speed) }
        case .setAspect(let aspect): Task { await model.setAspect(aspect) }
        case .setUpscaling(let mode): Task { await model.setUpscaling(mode) }
        case .selectAudioTrack(let id): Task { await model.selectAudioTrack(id) }
        case .selectSubtitleTrack(let id): Task { await model.selectSubtitleTrack(id) }
        case .setAmbientMode(let on): model.ambientMode = on
        case .setStatisticsHUD(let on): model.showsStatisticsHUD = on
        case .setVolumeBoost(let percent): Task { await model.setVolumeBoost(percent) }
        case .setLooping: Task { await model.toggleLooping() }
        case .step(let frames): Task { await model.stepFrame(frames) }
        case .setSubtitleStyle(let id):
            Task { await model.setSubtitleStyle(SubtitleStyle.style(id: id)) }
        case .close: onClose()
        default: performExtra(command, model)
        }
    }

    func toggleFullScreen() {
        // `keyWindow` is whatever currently has focus, which during playback can be
        // a panel or nothing at all — and toggling a panel full screen does nothing
        // visible, so the command silently failed. The main window is the one the
        // player fills, so ask for it directly and fall back only if it is gone.
        let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first
        window?.toggleFullScreen(nil)
    }

    /// AVKit's Picture in Picture where the file plays through AVPlayer; the
    /// floating mini window where it plays through mpv.
    func togglePictureInPicture() {
        if model?.avEngine != nil { pip.toggle() } else { MiniPlayer.toggle() }
    }

    // MARK: - Scroll

    /// Two fingers left or right seek. See `ScrollSeek`.
    func handleScroll(seconds: Double) {
        guard let model, Preference.scrollSeeks.value else { return }
        wakeChrome()
        Task { await model.scrollSeek(by: seconds) }
    }

    // MARK: - Keyboard

    /// The bindings a video player is expected to have. Anyone who has used mpv
    /// or VLC will try these without reading anything.
    /// A held arrow let go: its scan lands.
    func handleKeyUp(_ key: PlayerKey) {
        guard let model, model.keyScan != nil else { return }
        switch key {
        case .left, .j, .right, .l, .shiftLeft, .shiftRight:
            Task { await model.keyRelease() }
        default: break
        }
    }

    func handle(_ key: PlayerKey) -> Bool {
        StillWatching.someoneIsHere()
        guard let model else { return false }
        wakeChrome()

        switch key {
        case .space, .k:
            Task { await model.togglePlayPause() }
        // One step a press; held, a scan that lands on release. See
        // PlayerModel+KeySeek.swift.
        case .left, .j, .right, .l, .shiftLeft, .shiftRight:
            let long = key == .shiftLeft || key == .shiftRight
            let size = Double(long ? Preference.seekLongStepSeconds.value : Preference.seekStepSeconds.value)
            let back = key == .left || key == .j || key == .shiftLeft
            let isRepeat = KeyCaptureNSView.isRepeat
            Task { await model.keyStep(by: back ? -size : size, isRepeat: isRepeat) }
        case .info:
            openTab = openTab == .info ? nil : .info
        case .pictureInPicture:
            togglePictureInPicture()
        case .digit(let tenth):
            Task { await model.jump(toTenth: tenth) }
        case .optionLeft:
            Task { await model.skipChapter(forward: false) }
        case .optionRight:
            Task { await model.skipChapter(forward: true) }
        case .up:
            Task { await model.nudgeVolume(by: 0.05) }
        case .down:
            Task { await model.nudgeVolume(by: -0.05) }
        case .m:
            Task { await model.toggleMute() }
        case .f:
            toggleFullScreen()
        case .home:
            Task { await model.seek(to: 0) }
        case .end:
            Task { await model.seek(to: max(0, model.duration - 1)) }
        // Paused, these step a frame; playing, they change speed.
        //
        // Both readings are conventional — mpv puts frame stepping on these two
        // keys, and this player has always had speed there — and they never
        // overlap in practice: stepping a frame of a running picture shows you
        // nothing, and nudging the speed of a paused one does nothing at all.
        // So the state decides, and neither binding had to be given up.
        case .comma:
            if model.isPlaying {
                Task { await model.setPlaybackSpeed(max(0.25, model.playbackSpeed - 0.25)) }
            } else {
                Task { await model.stepFrame(-1) }
            }
        case .period:
            if model.isPlaying {
                Task { await model.setPlaybackSpeed(min(4, model.playbackSpeed + 0.25)) }
            } else {
                Task { await model.stepFrame(1) }
            }
        case .subtitleEarlier:
            Task { await model.nudgeSubtitleDelay(-1) }
        case .subtitleLater:
            Task { await model.nudgeSubtitleDelay(1) }
        case .escape:
            onClose()
        }
        return true
    }

    /// Switches the player to another episode in place.
    ///
    /// The current session is finished properly first — that is what writes the
    /// resume position — and the whole model is rebuilt rather than reloaded, so the
    /// new episode goes through the same decision, engine choice and track matching
    /// as if it had been opened from the library.
    func play(_ entry: LibraryEntry) {
        let old = model
        Task {
            await old?.finish()
            let fresh = PlayerModel(
                itemId: entry.id, client: client,
                repository: repository, capabilities: capabilities
            )
            model = fresh
            await fresh.start(mpvAvailable: mpvAvailable)
            wakeChrome()
        }
    }

    func playNextEpisode(_ model: PlayerModel) {
        guard let next = model.nextEpisode else { return }
        play(next)
    }
}

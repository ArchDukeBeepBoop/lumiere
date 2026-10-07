import SwiftUI
import Foundation
import Observation
import LumiereKit
import LumierePlayer

/// What a menu item can ask the player to do.
enum PlayerCommand: Equatable, Sendable {
    case togglePlayPause
    case skip(Double)
    case seek(Double)
    case chapter(forward: Bool)
    case nudgeVolume(Double)
    case toggleMute
    case toggleFullScreen
    case setSpeed(Double)
    case setAspect(AspectOverride)
    case setUpscaling(UpscalingMode)
    case selectAudioTrack(Int?)
    case selectSubtitleTrack(Int?)
    case setAmbientMode(Bool)
    case setStatisticsHUD(Bool)
    case setVolumeBoost(Double)
    case setSubtitleStyle(String)
    case setLooping(Bool)
    case step(frames: Int)
    case close
    // The menu bar's extras — see `PlaybackMenuController+Extras`.
    case episode(forward: Bool)
    case nudgeSpeed(Double)
    case toggleFlip(horizontal: Bool)
    case screenshot
    /// The frame to the clipboard, for pasting into a message.
    case copyFrame
    /// ±1 nudges a tenth of a second; 0 resets.
    case nudgeAudioDelay(Double)
    case nudgeSubtitleDelay(Double)
    case addSubtitleFile(URL)
    case setSubtitleSize(SubtitleSize)
    case startOver
    case abLoop
    /// 0 after this episode, minutes, or -1 to cancel. See SleepTimer.
    case sleep(minutes: Int)
    case setAudioDevice(AudioOutputs.Device?)
}

/// A snapshot of the player state the menu bar renders from.
///
/// A value type, and that is the whole point. SwiftUI rebuilds `Commands` when a
/// *focused value* changes; handing it a reference type whose properties mutate
/// leaves the identity unchanged, the scene never re-evaluates, and every
/// playback menu stays greyed out exactly as it was at launch.
struct PlayerMenuState: Equatable {
    var isActive = false
    var isPlaying = false
    var isMuted = false
    var supportsVideoAdjustments = false
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var selectedAudioTrack: Int?
    var selectedSubtitleTrack: Int?
    var chapters: [Chapter] = []
    var playbackSpeed: Double = 1
    var aspectOverride: AspectOverride = .auto
    var upscaling: UpscalingMode = .auto
    var ambientMode = false
    var showsStatisticsHUD = false
    var volumeBoost: Double = 100
    var isLooping = false
    var subtitleStyleId: String = "default"
    var hasPreviousEpisode = false
    var hasNextEpisode = false
    var supportsSubtitleDelay = false
    var flipHorizontal = false
    var flipVertical = false
    var subtitleSize: SubtitleSize = .normal
    var audioDelay: Double = 0
    var subtitleDelay: Double = 0
    var duration: Double = 0
    /// 0 nothing set, 1 A set, 2 looping. Names the A-B item.
    var abStage = 0
    var audioDeviceUID: String?

    init() {}

    @MainActor
    init(_ model: PlayerModel) {
        isActive = true
        isPlaying = model.isPlaying
        isMuted = model.isMuted
        supportsVideoAdjustments = model.supportsVideoAdjustments
        audioTracks = model.audioTracks
        subtitleTracks = model.subtitleTracks
        selectedAudioTrack = model.selectedAudioTrack
        selectedSubtitleTrack = model.selectedSubtitleTrack
        chapters = model.chapters
        playbackSpeed = model.playbackSpeed
        aspectOverride = model.aspectOverride
        upscaling = model.upscaling
        ambientMode = model.ambientMode
        showsStatisticsHUD = model.showsStatisticsHUD
        volumeBoost = model.volumeBoost
        isLooping = model.isLooping
        subtitleStyleId = model.subtitleStyle.id
        hasPreviousEpisode = model.previousEpisode != nil
        hasNextEpisode = model.nextEpisode != nil
        supportsSubtitleDelay = model.engineRef?.supportsSubtitleDelay ?? false
        flipHorizontal = model.flipHorizontal
        flipVertical = model.flipVertical
        subtitleSize = model.subtitleSize
        audioDelay = model.audioDelay
        subtitleDelay = model.subtitleDelay
        // Whole seconds: the length settles once, unlike the position, which
        // is deliberately not here — it would be a change every publish.
        duration = model.duration.rounded(.down)
        audioDeviceUID = model.audioDeviceUID
        abStage = model.abLoop.b != nil ? 2 : (model.abLoop.a != nil ? 1 : 0)
    }
}
/// The abandoned `FocusedValues` plumbing that used to sit here is gone.
///
/// `AppCommands` records why: a `CommandMenu` is only re-evaluated when a
/// focused value changes, which never worked for a player that is a full-window
/// overlay rather than a focused control. The menus are built in AppKit now, by
/// `PlaybackMenuController`, and nothing ever read or set a focused value — the
/// keys and the extension were scaffolding for an approach that was replaced.

@Observable
final class PlayerBridge {

    /// Bumped on every command so that sending the same one twice still fires.
    /// Without it, "skip forward" twice in a row would be a no-op the second time.
    private(set) var token = 0
    private(set) var pending: PlayerCommand?

    /// The current player state, readable synchronously.
    ///
    /// The menu bar is AppKit, and AppKit asks for enablement at the moment a menu
    /// opens rather than being told in advance. So this needs no observation and no
    /// publishing — `PlaybackMenuController` simply reads it during validation.
    /// That is why the menus work now: the previous attempt pushed this same state
    /// into scene `@State`, which SwiftUI does not treat as a reason to rebuild
    /// `.commands`, so every item stayed greyed out no matter how faithfully the
    /// player published.
    var menuState = PlayerMenuState()

    func send(_ command: PlayerCommand) {
        token &+= 1
        pending = command
    }

}

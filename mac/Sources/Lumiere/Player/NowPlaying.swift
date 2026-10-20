import AppKit
import MediaPlayer
import LumiereKit

/// What is playing, told to macOS: Control Center's Now Playing, the
/// keyboard's media keys, AirPods and headphone buttons, and the menu bar's
/// Now Playing all show Lumiere's film with its picture, and all of them work.
///
/// Before this the media keys went to Music, which opened over the film.
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()

    private weak var model: PlayerModel?
    private var onNext: (() -> Void)?
    private var onPrevious: (() -> Void)?
    private var artworkFor: String?
    private var artwork: MPMediaItemArtwork?
    private var targets: [Any] = []
    /// What was last told to macOS, so the 0.4 s tick sends nothing new.
    /// Every send re-encoded the artwork as a JPEG — two and a half times a
    /// second, behind the film.
    private var sent: (key: String, position: Double, at: Date)?

    /// Takes the media keys for this film.
    func attach(_ model: PlayerModel, pipeline: ImagePipeline?, serverURL: URL,
                next: @escaping () -> Void, previous: @escaping () -> Void) {
        self.model = model
        onNext = next
        onPrevious = previous
        if targets.isEmpty { register() }
        if artworkFor != model.itemId, let pipeline {
            artworkFor = model.itemId
            artwork = nil
            let request = ImageRequest(serverURL: serverURL, itemId: model.itemId, kind: .primary,
                                       tag: nil, displayWidth: 300, aspectRatio: 16 / 9)
            Task { [weak self] in
                guard let image = await pipeline.image(for: request) else { return }
                self?.artwork = Self.artwork(image.cgImage)
                self?.update()
            }
        }
        update()
    }

    /// Built outside the main actor on purpose: MediaPlayer calls the closure
    /// on its own queue, and a closure that inherited this class's isolation
    /// tripped Swift's executor check there and crashed the player.
    nonisolated private static func artwork(_ cgImage: CGImage) -> MPMediaItemArtwork {
        let picture = NSImage(cgImage: cgImage, size: .zero)
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return MPMediaItemArtwork(boundsSize: size) { @Sendable _ in picture }
    }

    /// Called on the player's publishing tick: position, rate and title.
    func update() {
        guard let model else { return }
        let playing = model.state == .playing
        let key = "\(model.itemId)|\(model.title)|\(playing)|\(model.playbackSpeed)|\(artwork != nil)"
            + "|\(model.nextEpisode != nil)|\(model.previousEpisode != nil)"
        if let sent, sent.key == key {
            // Unchanged, unless the position jumped: macOS runs the clock
            // itself from the rate, so only a seek needs telling.
            let expected = sent.position + (playing ? Date().timeIntervalSince(sent.at) * model.playbackSpeed : 0)
            if abs(model.position - expected) < 2 { return }
        }
        sent = (key, model.position, Date())
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.title,
            MPMediaItemPropertyPlaybackDuration: model.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.position,
            MPNowPlayingInfoPropertyPlaybackRate: model.state == .playing ? model.playbackSpeed : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let line = model.subtitleLine { info[MPMediaItemPropertyArtist] = line }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = model.state == .playing ? .playing : .paused
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = model.nextEpisode != nil
        commands.previousTrackCommand.isEnabled = model.previousEpisode != nil
    }

    /// Gives the media keys back when the player closes.
    func detach() {
        model = nil
        sent = nil
        onNext = nil
        onPrevious = nil
        artwork = nil
        artworkFor = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func register() {
        let c = MPRemoteCommandCenter.shared()
        let step = Double(Preference.seekStepSeconds.value)
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: step)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: step)]
        func on(_ command: MPRemoteCommand, _ body: @escaping @MainActor @Sendable (Double?) -> Void) {
            targets.append(Self.target(command, body))
        }
        on(c.togglePlayPauseCommand) { [weak self] _ in self?.run { await $0.togglePlayPause() } }
        on(c.playCommand) { [weak self] _ in
            self?.run { model in if model.state != .playing { await model.togglePlayPause() } }
        }
        on(c.pauseCommand) { [weak self] _ in
            self?.run { model in if model.state == .playing { await model.togglePlayPause() } }
        }
        on(c.skipForwardCommand) { [weak self] _ in self?.run { await $0.skip(by: step) } }
        on(c.skipBackwardCommand) { [weak self] _ in self?.run { await $0.skip(by: -step) } }
        on(c.changePlaybackPositionCommand) { [weak self] position in
            guard let position else { return }
            self?.run { await $0.seek(to: position) }
        }
        on(c.nextTrackCommand) { [weak self] _ in self?.onNext?() }
        on(c.previousTrackCommand) { [weak self] _ in self?.onPrevious?() }
    }

    /// The handler is made outside the main actor — MediaPlayer may call it on
    /// any queue — and hops to the main actor itself.
    nonisolated private static func target(
        _ command: MPRemoteCommand, _ body: @escaping @MainActor @Sendable (Double?) -> Void
    ) -> Any {
        command.addTarget { @Sendable event in
            // Only the one value a handler needs crosses to the main actor;
            // the event object itself is not Sendable.
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            Task { @MainActor in body(position) }
            return .success
        }
    }

    private func run(_ action: @escaping @MainActor (PlayerModel) async -> Void) {
        guard let model else { return }
        Task { await action(model); update() }
    }
}

extension PlayerView {
    /// Control Center, the media keys and headphone buttons, for this film.
    func attachNowPlaying(_ model: PlayerModel) {
        NowPlaying.shared.attach(
            model, pipeline: pipeline, serverURL: client.session.serverURL,
            next: { playNextEpisode(model) },
            previous: { if let previous = model.previousEpisode { play(previous) } }
        )
    }
}

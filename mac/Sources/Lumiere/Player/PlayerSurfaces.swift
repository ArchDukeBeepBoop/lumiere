import SwiftUI
import AVKit
import AVFoundation
import LumierePlayer

/// Hosts an `AVPlayerLayer`.
///
/// A layer rather than `VideoPlayer` because the system control overlay cannot
/// be removed from `VideoPlayer`, and Lumiere draws its own.
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let pip: PictureInPictureBox

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        // The controller must be built against the layer that is actually on
        // screen; one built against a detached layer starts a session showing
        // nothing.
        pip.attach(to: view.playerLayer)
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

/// Hosts mpv's own view.
struct MPVSurface: NSViewRepresentable {
    let view: MPVVideoView

    func makeNSView(context: Context) -> MPVVideoView { view }
    func updateNSView(_ view: MPVVideoView, context: Context) {}
}

/// Owns the Picture in Picture session.
///
/// A class rather than a computed property because AVKit tears the session down
/// as soon as its controller is released — building one per call gives a button
/// that appears to work and never does.
@MainActor
final class PictureInPictureBox {
    private var controller: AVPictureInPictureController?

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        controller = AVPictureInPictureController(playerLayer: layer)
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }
}

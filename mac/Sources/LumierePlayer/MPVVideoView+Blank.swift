import Foundation
import AppKit
import OpenGL.GL3
import LumiereKit

/// The one report that turns a black window into a diagnosis.
///
/// Split from MPVVideoView.swift for the project's 300-line rule, and it is a
/// coherent piece on its own: everything else in that file exists to draw a
/// frame, and this exists to say when nothing has been.
extension MPVVideoView {

    /// Says so, once, if playback is running and nothing has been drawn.
    ///
    /// Called by the engine a few seconds after playback starts. Silence is not a
    /// diagnosis, so this turns the black-window case into a named condition with
    /// the video format beside it — which is what makes the next report of "no
    /// picture" a five-minute question rather than a day of guessing at texture
    /// formats and hardware decoders.
    func reportIfBlank(format: String) {
        guard drawCount == 0 else { return }
        Diagnostics.log(
            "[mpv] NO PICTURE: playing but no frame has been drawn."
            + " video=\(format) gl=\(Self.glString(GLenum(GL_VERSION)))"
        )
    }
}

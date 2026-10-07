import Foundation
import AppKit
import OpenGL.GL3
import CMPV
import LumiereKit

/// The surface mpv renders into, via libmpv's OpenGL render API.
///
/// This is the only embedding path libmpv supports on macOS. Handing mpv an
/// `NSView` through `wid` looks simpler and appears to work — mpv initialises,
/// accepts the file, emits `start-file` — and then never produces a frame,
/// because its Cocoa windowing code is not usable from libmpv. This build has no
/// Cocoa GPU context at all (`--gpu-context` offers only Vulkan), so the render
/// API with a host-provided GL context is the path that actually renders.
public final class MPVVideoView: NSOpenGLView {

    // Not private: the context lifecycle lives in MPVVideoView+Context.swift to
    // keep this file under the line limit, and Swift scopes `private` to the file.
    var renderContext: OpaquePointer?
    /// The +1 handed to mpv's update callback, released when the context goes.
    var callbackContext: UnsafeMutableRawPointer?

    /// Counts frames actually drawn. mpv can initialise, accept a file and report
    /// playback while never producing a picture — that failure mode is invisible
    /// without a screen, so under `LUMIERE_MPV_TRACE` this is the proof the
    /// decode path is really rendering.
    // Not private: MPVVideoView+Blank.swift reports on it, and Swift scopes
    // `private` to the file.
    var drawCount = 0

    /// Fires once the view is in a window and its GL context is usable.
    public var onReady: (() -> Void)?
    public private(set) var isReady = false

    /// 4.1 Core first, 3.2 Core only if the machine cannot give it.
    ///
    /// Asking for the profile we want rather than the minimum we can tolerate,
    /// and nothing more is claimed for it than that. It was added while chasing a
    /// missing HEVC picture, on the theory that 3.2 Core withholds the 16-bit
    /// texture formats a 10-bit plane needs — and that theory was wrong: on this
    /// hardware a 3.2 Core request already yields a GL 4.1 context, R16 and RG16
    /// textures create cleanly under both, and a 10-bit P010 IOSurface binds
    /// through `CGLTexImageIOSurface2D` exactly as an 8-bit NV12 one does. The
    /// real cause was a container question in the planner, not a texture one
    /// here; see `PlaybackDecision.avSupportsVideo`.
    ///
    /// The fallback is real rather than defensive tidiness: `NSOpenGLPixelFormat`
    /// returns nil when it cannot satisfy the attributes, and a Mac too old for
    /// 4.1 should still play video rather than fail to construct a view.
    private static func pixelFormat() -> (NSOpenGLPixelFormat, String)? {
        let profiles: [(UInt32, String)] = [
            (UInt32(NSOpenGLProfileVersion4_1Core), "4.1 Core"),
            (UInt32(NSOpenGLProfileVersion3_2Core), "3.2 Core"),
        ]
        for (profile, name) in profiles {
            let attributes: [NSOpenGLPixelFormatAttribute] = [
                UInt32(NSOpenGLPFAAccelerated),
                UInt32(NSOpenGLPFADoubleBuffer),
                UInt32(NSOpenGLPFAOpenGLProfile), profile,
                UInt32(NSOpenGLPFAColorSize), 24,
                UInt32(NSOpenGLPFAAlphaSize), 8,
                UInt32(NSOpenGLPFADepthSize), 0,
                0,
            ]
            if let format = NSOpenGLPixelFormat(attributes: attributes) {
                return (format, name)
            }
        }
        return nil
    }

    public init() {
        // A nil pixel format would mean no accelerated GL context of any profile,
        // which is not a state this app can render in. Named rather than left to
        // the force-unwrap that used to be here, which would have crashed with
        // nothing said about why.
        guard let (format, profileName) = Self.pixelFormat() else {
            fatalError("No accelerated OpenGL pixel format is available on this Mac.")
        }
        Diagnostics.log("[mpv] OpenGL profile: \(profileName)")
        super.init(frame: .zero, pixelFormat: format)!

        wantsBestResolutionOpenGLSurface = true
        // Video is opaque; blending it would only cost fill rate.
        openGLContext?.setValues([1], for: .swapInterval)
    }

    public required init?(coder: NSCoder) { fatalError("not used") }

    // No deinit teardown: `MPVEngine.stop()` calls `destroyRenderContext()`
    // explicitly, and it must happen before the mpv handle is destroyed anyway.
    // Freeing from a nonisolated deinit would also race the render callback.

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !isReady else { return }
        isReady = true
        onReady?()
        onReady = nil
    }

    /// Reads a GL string, or a placeholder rather than crashing on a null.
    // Not private: the blank-picture report reads the same string.
    static func glString(_ name: GLenum) -> String {
        guard let raw = glGetString(name) else { return "?" }
        return String(cString: raw)
    }

    // MARK: - Render context

    // MARK: - Drawing

    // Not fileprivate: mpv's update callback lives beside its registration in
    // MPVVideoView+Context.swift, and calls this from the main queue.
    func renderIfNeeded() {
        guard let renderContext else { return }
        let flags = mpv_render_context_update(renderContext)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }
        draw()
    }

    public override func draw(_ dirtyRect: NSRect) {
        draw()
    }

    private func draw() {
        guard let openGLContext, let renderContext else { return }
        openGLContext.makeCurrentContext()
        CGLLockContext(openGLContext.cglContextObj!)
        defer {
            CGLUnlockContext(openGLContext.cglContextObj!)
        }

        // Backing pixels, not points: on Retina these differ by 2x and getting
        // it wrong renders a quarter of the frame.
        let scale = window?.backingScaleFactor ?? 2
        var fbo = mpv_opengl_fbo(
            fbo: 0,
            w: Int32(bounds.width * scale),
            h: Int32(bounds.height * scale),
            internal_format: 0
        )
        // mpv's origin is top-left, OpenGL's is bottom-left.
        var flipY: CInt = 1

        // Same lifetime rule as the context params above: these pointers must
        // outlive the render call, not just the array literal.
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(fboPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(flipPointer)
                    ),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
        openGLContext.flushBuffer()
        mpv_render_context_report_swap(renderContext)

        drawCount += 1
        if drawCount == 1 {
            // The first frame, always, not only under a trace flag.
            //
            // A picture that never arrives is the hardest failure this app has to
            // explain, because everything else looks healthy: mpv initialises, the
            // file loads, the clock runs, the controls work and the audio plays.
            // The one fact that separates "decoding into a black window" from
            // "playing normally" is whether a frame was ever drawn, and it costs a
            // single line to say so.
            Diagnostics.log("[mpv] first frame drawn")
        } else if drawCount % 300 == 0 {
            Diagnostics.log("[mpv] drew \(drawCount) frames")
        }
    }

    public override func reshape() {
        super.reshape()
        draw()
    }

    /// Resolves GL entry points for mpv. `dlsym` on the OpenGL framework bundle
    /// is the documented way; the symbols are not linkable directly.
    static func glProcAddress(_ name: String) -> UnsafeMutableRawPointer? {
        guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
            return nil
        }
        return CFBundleGetFunctionPointerForName(bundle, name as CFString)
    }
}

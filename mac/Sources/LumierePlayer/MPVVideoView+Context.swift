import Foundation
import AppKit
import CMPV
import LumiereKit

/// Standing up mpv's render context against the host GL context, and tearing it
/// down in the one order that is safe.
///
/// Split from MPVVideoView.swift for the project's 300-line rule, and it is the
/// right seam: everything here is lifetime — who holds a reference to whom, and
/// which end of the teardown has to go first — which is a different concern from
/// drawing a frame.
extension MPVVideoView {

    /// Creates mpv's render context against this view's GL context.
    ///
    /// Must run after `mpv_initialize` and with the GL context current, which is
    /// why it lives here rather than in the engine.
    func createRenderContext(mpv: OpaquePointer) throws {
        guard let openGLContext else {
            throw PlayerEngineError.engineUnavailable("No OpenGL context for the video view.")
        }
        openGLContext.makeCurrentContext()

        // What the driver actually gave us, once, where it can be read back.
        // The profile asked for and the profile granted are different questions,
        // and the difference decides whether 10-bit video has anywhere to live —
        // so this is the line to look for when a picture is missing.
        Diagnostics.log(
            "[mpv] GL \(Self.glString(GLenum(GL_VERSION))) · "
            + "\(Self.glString(GLenum(GL_RENDERER)))"
        )

        var initParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                return MPVVideoView.glProcAddress(String(cString: name))
            },
            get_proc_address_ctx: nil
        )
        // Lets mpv tell us exactly when a frame is due rather than redrawing on a
        // timer and either tearing or wasting GPU.
        var advancedControl: CInt = 1
        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }

        // Every `data` pointer must stay valid until mpv_render_context_create
        // returns. Building the array with `&x` produces pointers that die at the
        // end of each element expression — a dangling read mpv would then follow.
        var context: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParams) { initPointer in
            withUnsafeMutablePointer(to: &advancedControl) { controlPointer in
                var params = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_API_TYPE,
                        data: UnsafeMutableRawPointer(apiType)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                        data: UnsafeMutableRawPointer(initPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_ADVANCED_CONTROL,
                        data: UnsafeMutableRawPointer(controlPointer)
                    ),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_create(&context, mpv, &params)
            }
        }
        guard status >= 0, let context else {
            let message = mpv_error_string(status).map { String(cString: $0) } ?? "error \(status)"
            throw PlayerEngineError.engineUnavailable("mpv render context: \(message)")
        }
        renderContext = context

        // The callback is a file-scope function, not a closure written here, and
        // that is load-bearing: a closure inside this main-actor-isolated class
        // is itself inferred main-actor, so Swift emits an executor assertion at
        // its entry. mpv calls it from vo_thread, the assertion fails, and the
        // process dies with SIGILL before a single line of the body runs.
        // Retained, not unretained, and released only after the callback is
        // unregistered below.
        //
        // mpv calls this from its own render thread and the callback hops to the
        // main queue to draw. Handing it an unretained pointer meant nothing kept
        // the view alive across that hop: close the player while a block is queued
        // — `stop()` unregisters and SwiftUI drops the representable — and the block
        // resurrects a freed object. A use-after-free is not a crash you can read
        // from a log, which is why it is worth the two lines of bookkeeping.
        let retained = Unmanaged.passRetained(self).toOpaque()
        callbackContext = retained
        mpv_render_context_set_update_callback(context, mpvRenderUpdate, retained)
    }

    func destroyRenderContext() {
        guard let renderContext else { return }
        // Order matters: stop new callbacks, then tear the context down, and only
        // then drop the reference mpv was holding. Releasing first would reopen the
        // window this closes.
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        if let retained = callbackContext {
            callbackContext = nil
            Unmanaged<MPVVideoView>.fromOpaque(retained).release()
        }
    }
}

/// mpv's "a frame is ready" callback.
///
/// Deliberately at file scope so it is nonisolated: see the note at the call
/// site. It touches nothing main-actor until it is actually on the main thread.
func mpvRenderUpdate(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    // Boxed so the raw pointer is Sendable in name as well as in fact: it is the
    // same immutable view pointer mpv was handed at setup and is never mutated.
    // Captured strongly for the hop. The registration above holds a reference for
    // as long as mpv can call this, so reading the value here is safe; capturing it
    // in the block is what keeps it alive until the block actually runs.
    let view = MPVViewPointer(raw: ctx).view
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            view.renderIfNeeded()
        }
    }
}

/// Carries the view pointer from mpv's render thread to the main actor.
struct MPVViewPointer: @unchecked Sendable {
    let raw: UnsafeMutableRawPointer

    var view: MPVVideoView {
        Unmanaged<MPVVideoView>.fromOpaque(raw).takeUnretainedValue()
    }
}

import Foundation
import AppKit
import CMPV
import LumiereKit

/// Creating the mpv handle: every option this engine sets, and why. Split from
/// MPVEngine.swift for the 300-line rule — the options are most of what the
/// engine knows, and each carries the measurement that chose it.
@MainActor
extension MPVEngine {

    func createHandle(for request: PlaybackRequest) throws {
        guard let handle = mpv_create() else {
            throw PlayerEngineError.engineUnavailable("mpv_create returned null.")
        }
        self.handle = handle

        // The host owns the surface; mpv renders into it on demand.
        setOption("vo", "libmpv")

        // Asked for, and — measured, on the vendored mpv 0.41 — never granted. Every
        // file this engine plays is decoded in software.
        //
        // The blocker is the embedding, not the option. This engine renders through
        // libmpv's render API with `MPV_RENDER_API_TYPE_OPENGL` into an
        // `NSOpenGLView` (MPVVideoView+Context.swift), and mpv 0.41 has no OpenGL
        // interop left to hand VideoToolbox surfaces through — `--gpu-api=opengl` is
        // not even a valid value any more: "Option gpu-api: 'opengl' isn't
        // supported." So the hwdec is disabled and `hwdec-current` reports "no".
        //
        // Verified from both ends. The same libmpv on its own Metal backend prints
        // "Using hardware decoding (videotoolbox)" for a real file off this library,
        // and `--hwdec=help` lists h264-videotoolbox; in the app, both
        // `videotoolbox` and `videotoolbox-copy` log `decode: Software`, so
        // copy-back is not a way around it either.
        //
        // Kept as `videotoolbox` rather than `-copy` because neither engages, and
        // zero-copy is the value worth keeping if that ever changes: copy-back reads
        // every frame into system memory, 12 MB a frame at 4K, which an earlier audit
        // measured as 143 MB of malloc against 416 KB of IOSurface.
        //
        // The real fix is to stop embedding through OpenGL — hand mpv a view via
        // `wid` and let it run its own Metal `vo=gpu` — which is a rewrite of the
        // video surface rather than an option change. Until then the log line
        // `[playback] decode:` and the HUD's Decode row both say Software, honestly.
        setOption("hwdec", "videotoolbox")

        // No direct rendering. This is the freeze.
        //
        // With DR on, a software decoder asks the video output for its frame
        // buffers, and under the render API the video output is this app's main
        // thread — so a decoder thread sits in `dr_helper_get_image` waiting for
        // the main thread to service the render context. Meanwhile any
        // synchronous libmpv call from the main thread (`mpv_get_property` in
        // `reloadTracks`, `mpv_command` for a seek) waits for the core's dispatch
        // lock, and the core is waiting on the decoder. Three threads, each
        // waiting for the next: the picture stops, the controls stop, and a
        // sample of the process shows all three parked in `pthread_cond_wait`.
        // libmpv's own documentation warns of exactly this under "Threading" for
        // the render API. It surfaced every few seeks once seeks started landing
        // as fast as the picture could take them; it was always latent.
        //
        // Off, the decoder allocates its own buffers and the render thread is
        // never something the core has to wait for. The cost is one copy per
        // frame into the GPU upload path, which every hardware-decoded file was
        // already paying — and on this embedding every file is software-decoded.
        setOption("vd-lavc-dr", "no")

        // The seekable cache lets a scrub back over ground already read come
        // from memory rather than another range request.
        //
        // `cache-pause` is left at mpv's default, on. It was turned off here
        // for a build, on the theory that a loopback server refills a cache
        // faster than a pause is worth — but the library sits on a USB disk
        // that answers a read in ten to fifty milliseconds, and when it fell
        // behind the picture played on through the gap instead of pausing to
        // refill: the "videos look choppy" report. A brief buffering pause is
        // the honest behaviour on a slow disk.
        setOption("demuxer-seekable-cache", "yes")

        // Nothing of mpv's own UI: Lumiere draws the controls.
        setOption("osc", "no")
        setOption("osd-level", "0")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("terminal", "no")
        // Never read the user's ~/.config/mpv — their settings must not silently
        // change how this app behaves.
        setOption("config", "no")
        setOption("load-scripts", "no")
        setOption("ytdl", "no")

        // LUMIERE_MPV_OPTIONS="vd-lavc-dr=yes,opengl-pbo=yes" overrides anything
        // above, for measuring one option against another without a rebuild.
        // Applied last so it wins; never read from the user's config.
        if let extra = ProcessInfo.processInfo.environment["LUMIERE_MPV_OPTIONS"] {
            for pair in extra.split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                Diagnostics.log("[mpv] option override \(parts[0])=\(parts[1])")
                setOption(parts[0], parts[1])
            }
        }

        // Subtitle styling. The fonts live in the bundle rather than being assumed
        // present, and this points libass at that directory — without it a chosen
        // family silently resolves to a default and the setting appears to do
        // nothing at all.
        // One directory holding both the bundled faces and anything the user has
        // added — mpv takes a single path, and `seed` is what keeps that path
        // complete. Without it, adding one font would make the three presets stop
        // resolving.
        SubtitleFonts.seed()
        setOption("sub-fonts-dir", SubtitleFonts.directory.path)
        for (key, value) in SubtitleStyle.style(
            id: UserDefaults.standard.string(forKey: "subtitleStyle")
        ).mpvOptions {
            setOption(key, value)
        }
        // After the style, so its `sub-ass-override` wins where a size is set. The
        // preset asks libass to leave ASS alone; a chosen size asks it to apply the
        // scale and nothing else, and the later option is the one that takes.
        // A face the user picked outright, overriding the preset's. Last, so it
        // beats the `sub-font` the style just set.
        let family = UserDefaults.standard.string(forKey: "subtitleFontFamily") ?? ""
        if !family.isEmpty { setOption("sub-font", family) }

        for (key, value) in SubtitleSize.size(
            id: UserDefaults.standard.string(forKey: "subtitleSize")
        ).mpvOptions {
            setOption(key, value)
        }

        // Keep the file open at EOF so the end can be reported rather than mpv
        // idling out from under us.
        setOption("keep-open", "yes")
        setOption("idle", "yes")

        // Colour handling. target-colorspace-hint lets libplacebo drive the
        // display's colour space where the OS allows it; tone mapping only
        // applies when the source is brighter than the target, so setting it
        // unconditionally is safe for SDR content.
        setOption("target-colorspace-hint", "yes")
        setOption("tone-mapping", "bt.2390")
        if request.toneMapDolbyVision {
            // Profile 5 carries no HDR10 fallback layer, so without libplacebo
            // applying the RPU the picture comes out green and washed.
            setOption("target-trc", "pq")
        }

        // Cache sizing is the single biggest lever on playback footprint, and the
        // defaults are wrong for this app in both directions.
        //
        // `cache=yes` forces the demuxer cache on for local files too, where the
        // OS page cache already does the job — that alone put sustained 4K
        // playback at ~700 MB against a 400 MB budget. `auto` keeps the cache for
        // network streams, which is every Jellyfin direct-play URL, and drops it
        // for local files.
        //
        // 150 MiB of readahead is sized for a slow internet stream. Against a LAN
        // server it buys nothing a fraction of that doesn't, and the back buffer
        // has to be named explicitly or it silently adds its own 50 MiB.
        setOption("cache", "auto")
        setOption("demuxer-max-bytes", "32MiB")
        setOption("demuxer-max-back-bytes", "16MiB")
        setOption("audio-channels", "auto-safe")

        Diagnostics.log("[mpv] initialising, view ready: \(view.isReady)")
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            self.handle = nil
            throw PlayerEngineError.engineUnavailable("mpv_initialize failed.")
        }

        // Ask mpv for warnings and errors before anything else happens, so a
        // failure during file load is visible rather than silent.
        // `LUMIERE_MPV_TRACE=1` raises this to verbose, which is the only way to see
        // *why* mpv refused something — a rejected hardware decoder is an info-level
        // line, so at "warn" the app could only observe that hwdec had not engaged
        // and never the reason. That cost a round of guessing.
        mpv_request_log_messages(
            handle,
            ProcessInfo.processInfo.environment["LUMIERE_MPV_TRACE"] == "1" ? "v" : "warn"
        )

        // Re-applied as properties after initialise. Set only as pre-init options
        // these do not stick, and mpv draws its own timecode over the top-left of
        // the picture — directly on top of Lumiere's Close button.
        setProperty("osd-level", "0")
        setProperty("osd-duration", "0")
        setProperty("keepaspect", "yes")

        // The render context must come after initialise and before playback.
        try view.createRenderContext(mpv: handle)

        observeProperties(handle)
        startEventPump(handle)
    }

    func observeProperties(_ handle: OpaquePointer) {
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "track-list/count", MPV_FORMAT_INT64)
    }
}

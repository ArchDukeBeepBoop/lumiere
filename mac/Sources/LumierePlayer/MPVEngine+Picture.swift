import Foundation
import LumiereKit

/// Picture and sound controls, and subtitle placement, on mpv.
extension MPVEngine {

    public nonisolated var supportsPicture: Bool { true }

    /// The equaliser properties and rotation are applied by the renderer, so
    /// they work on zero-copy frames. Deinterlacing is a software filter and
    /// joins the flip in `applyVideoFilters`, which copies frames back only
    /// while one of them is on.
    public func setPicture(_ picture: PictureAdjustments) async {
        setProperty("brightness", String(PictureAdjustments.clamp(picture.brightness)))
        setProperty("contrast", String(PictureAdjustments.clamp(picture.contrast)))
        setProperty("saturation", String(PictureAdjustments.clamp(picture.saturation)))
        setProperty("gamma", String(PictureAdjustments.clamp(picture.gamma)))
        setProperty("video-rotate", String([0, 90, 180, 270].contains(picture.rotation) ? picture.rotation : 0))
        setProperty("video-zoom", String(format: "%.3f", picture.mpvZoom))
        if cachedDeinterlace != picture.deinterlace {
            cachedDeinterlace = picture.deinterlace
            applyVideoFilters()
        }
    }

    /// Labelled, so it never disturbs Enhance Dialogue or Reduce Loud Sounds.
    public func setSoundPreset(_ preset: SoundPreset) async {
        commandAsync(["af", "remove", "@sound"])
        if let chain = preset.lavfi {
            commandAsync(["af", "add", "@sound:lavfi=[\(chain)]"])
        }
    }

    public func setSubtitlePosition(_ percent: Int) async {
        setProperty("sub-pos", String(max(0, min(150, percent))))
    }

    /// `scale` override so a typeset (ASS) track follows the exact size too;
    /// nil hands back to the named size, which writes its own options.
    public func setSubtitleScale(_ scale: Double?) async {
        guard let scale else {
            let size = SubtitleSize.size(id: UserDefaults.standard.string(forKey: "subtitleSize"))
            await setSubtitleSize(size)
            return
        }
        setProperty("sub-ass-override", "scale")
        setProperty("sub-scale", String(format: "%.2f", max(0.3, min(3, scale))))
    }

    /// mpv's `sub-step`: retimes so the line `lines` away is on screen now.
    public func stepSubtitleTiming(lines: Int) async -> Double {
        command(["sub-step", String(lines)])
        return doubleProperty("sub-delay") ?? 0
    }
}

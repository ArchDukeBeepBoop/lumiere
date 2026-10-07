import Foundation

/// Turns raw stream metadata into the short strings people read.
///
/// Pure, and in the kit rather than the view layer so it can be tested: these
/// functions decide what the app *claims* about a file, and one of those claims
/// — whether Dolby Vision will actually be presented as Dolby Vision — is a
/// promise this Mac cannot keep.
public enum MediaSummary {

    /// Resolution matched on width, not height.
    ///
    /// 4K films are routinely 3840×1600 after the black bars are cropped, so
    /// height alone reports them as 1080p, which is the kind of wrong that makes
    /// a user distrust every other badge.
    public static func resolutionLabel(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        switch width {
        case 3400...: return "4K"
        case 2000..<3400: return "1440p"
        case 1800..<2000: return "1080p"
        case 1200..<1800: return "720p"
        default: return height >= 700 ? "720p" : "SD"
        }
    }

    /// The HDR badge, told honestly.
    ///
    /// A machine that will tone-map Dolby Vision must not print "Dolby Vision" —
    /// the user would only discover otherwise when the colours look wrong, and
    /// would blame the file rather than the client.
    public static func rangeLabel(for video: MediaStream, dolbyVisionSupported: Bool) -> String? {
        let type = (video.videoRangeType ?? video.videoRange ?? "").uppercased()

        if type.contains("DOVI") || video.dvProfile != nil {
            return dolbyVisionSupported ? "Dolby Vision" : "DV → HDR10"
        }
        if type.contains("HDR10PLUS") || type.contains("HDR10+") { return "HDR10+" }
        if type.contains("HLG") { return "HLG" }
        if type.contains("HDR") { return "HDR10" }
        return nil
    }

    public static func channelLabel(for audio: MediaStream) -> String {
        if let layout = audio.channelLayout, !layout.isEmpty { return layout }
        switch audio.channels {
        case 8: return "7.1"
        case 6: return "5.1"
        case 2: return "Stereo"
        case 1: return "Mono"
        default: return ""
        }
    }

    /// Codec names as people recognise them, not as ffmpeg spells them.
    public static func normalise(codec: String) -> String {
        switch codec.uppercased() {
        case "HEVC", "H265", "X265": return "HEVC"
        case "H264", "AVC", "X264": return "H.264"
        case "TRUEHD": return "TrueHD"
        case "EAC3": return "EAC3"
        case "AC3": return "AC3"
        case "DTS": return "DTS"
        case "DTSHD", "DTS-HD", "DTSHD_MA": return "DTS-HD"
        case "AAC": return "AAC"
        case "FLAC": return "FLAC"
        case "OPUS": return "Opus"
        case "VORBIS": return "Vorbis"
        case "AV1": return "AV1"
        case "VP9": return "VP9"
        case "MPEG2VIDEO": return "MPEG-2"
        case "VC1": return "VC-1"
        case "PGSSUB": return "PGS"
        case "SUBRIP": return "SRT"
        case "ASS", "SSA": return "ASS"
        case "": return ""
        default: return codec.uppercased()
        }
    }

    /// Whether this Mac decodes the stream in hardware. Nil when the codec is
    /// unrecognised, which is itself worth surfacing as software decode.
    public static func decodesInHardware(
        codec: String?, capabilities: SystemCapabilities
    ) -> Bool {
        switch (codec ?? "").lowercased() {
        case "h264", "avc": return capabilities.hardwareH264
        case "hevc", "h265": return capabilities.hardwareHEVC
        case "vp9": return capabilities.hardwareVP9
        case "av1": return capabilities.hardwareAV1
        default: return false
        }
    }
}

package app.lumiere.android.player

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import app.lumiere.android.api.Item
import app.lumiere.android.api.MediaStream

/**
 * What this device can decode, asked before playing rather than discovered
 * as a black screen. Audio it cannot decode is converted on the Mac (the
 * picture untouched); video it cannot decode is said plainly.
 */
object Compatibility {
    private val decoders by lazy {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
    }

    private fun audioMime(codec: String?) = when (codec?.lowercase()) {
        "eac3" -> "audio/eac3"; "ac3" -> "audio/ac3"; "truehd" -> "audio/true-hd"
        "dts" -> "audio/vnd.dts"; "dts-hd", "dtshd" -> "audio/vnd.dts.hd"
        "aac" -> "audio/mp4a-latm"; "opus" -> "audio/opus"; "flac" -> "audio/flac"
        "mp3" -> "audio/mpeg"; "vorbis" -> "audio/vorbis"; "pcm_s16le", "pcm_s24le" -> "audio/raw"
        else -> null
    }

    private fun videoMime(codec: String?) = when (codec?.lowercase()) {
        "hevc", "h265" -> "video/hevc"; "h264", "avc" -> "video/avc"; "av1" -> "video/av01"
        "vp9" -> "video/x-vnd.on2.vp9"; "vp8" -> "video/x-vnd.on2.vp8"; "mpeg2video" -> "video/mpeg2"
        "mpeg4" -> "video/mp4v-es"; "vc1" -> "video/wvc1"
        else -> null
    }

    /** Opus, AAC, FLAC and MP3 are decoded by Android itself on every device. */
    fun canDecodeAudio(codec: String?): Boolean {
        val mime = audioMime(codec) ?: return true
        if (mime in setOf("audio/opus", "audio/mp4a-latm", "audio/flac", "audio/mpeg", "audio/vorbis", "audio/raw")) return true
        return decoders.any { info -> info.supportedTypes.any { it.equals(mime, true) } }
    }

    /** Why the picture cannot play here, in words; null when it can. */
    fun videoProblem(stream: MediaStream?, width: Int?, height: Int?, bitDepth: Int?): String? {
        val mime = videoMime(stream?.codec) ?: return null
        val candidates = decoders.filter { info -> info.supportedTypes.any { it.equals(mime, true) } }
        if (candidates.isEmpty()) return "This device has no ${stream?.codec?.uppercase()} video decoder."
        val w = width ?: return null
        val h = height ?: return null
        val fits = candidates.any { info ->
            val caps = info.getCapabilitiesForType(info.supportedTypes.first { it.equals(mime, true) })
            val size = caps.videoCapabilities?.isSizeSupported(w, h) ?: true
            val depth = bitDepth != 10 || mime != "video/hevc" ||
                caps.profileLevels.any { it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 }
            size && depth
        }
        return if (fits) null else "This device can't decode ${w}×$h ${if (bitDepth == 10) "10-bit " else ""}" +
            "${stream?.codec?.uppercase()} video. It plays on the Mac and the phone."
    }

    /** The audio track that will play: Japanese for anime where asked, else the file's default, else the first. */
    fun chooseAudio(item: Item, anime: Boolean, remembered: String?): MediaStream? {
        val audio = item.streams.filter { it.type == "Audio" }
        return remembered?.let { r -> audio.firstOrNull { it.language == r } }
            ?: (if (anime) audio.firstOrNull { it.language == "jpn" || it.language == "ja" } else null)
            ?: audio.firstOrNull { it.isDefault } ?: audio.firstOrNull()
    }
}

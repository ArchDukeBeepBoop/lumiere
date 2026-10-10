package app.lumiere.android.player

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Sound from the screen, on a Quest: turn your head and the film stays
 * where its picture is. The headset tells [azimuth] where the screen is
 * from your head; the player's [Processor] leans the soundtrack that way —
 * louder in the ear nearer the screen, the far ear shadowed by your head,
 * the stereo narrowing as the screen goes to one side. A few multiplications
 * a sample, so nothing the headset would notice; 5.1 and 7.1 are folded to
 * your two ears first, as the headset would anyway.
 */
object ScreenAudio {
    /** Set by the Quest's spatial app; elsewhere the player's sound is left exactly as it was. */
    @Volatile var enabled = false

    /** Where the screen is from your head, in radians: 0 straight ahead, positive to your left. */
    @Volatile var azimuth = 0f

    /** The far ear never drops below this share of the power: a head shadows, it doesn't silence. */
    private const val SHADOW = 0.25f
    /** The stereo never narrows past this, however far round the screen is. */
    private const val MIN_WIDTH = 0.3f

    /**
     * For a screen at [azimuth]: the left ear's gain, the right ear's, and
     * how much of the stereo's width is kept. Straight ahead it is exactly
     * 1, 1, 1 — the sound untouched; no gain is ever above 1, so leaning
     * can't clip.
     */
    fun gains(azimuth: Float): FloatArray {
        val p = sin(azimuth)
        val loudest = 1f + abs(p)
        val left = sqrt((1f + p).coerceAtLeast(SHADOW) / loudest)
        val right = sqrt((1f - p).coerceAtLeast(SHADOW) / loudest)
        val width = abs(cos(azimuth)).coerceAtLeast(MIN_WIDTH)
        return floatArrayOf(left, right, width)
    }

    /**
     * One frame of [channels] samples from [frame] folded to left and right:
     * stereo as it is; 5.1 and 7.1 as the usual downmix (centre and
     * surrounds at -3 dB, a little of the LFE), turned down to leave headroom.
     */
    fun fold(frame: FloatArray, channels: Int, out: FloatArray) {
        if (channels == 2) { out[0] = frame[0]; out[1] = frame[1]; return }
        // Android's order: front left, front right, centre, LFE, back left, back right (side left, side right).
        val centre = 0.7071f * frame[2]
        val lfe = 0.35f * frame[3]
        var l = frame[0] + centre + 0.7071f * frame[4] + lfe
        var r = frame[1] + centre + 0.7071f * frame[5] + lfe
        if (channels == 8) { l += 0.7071f * frame[6]; r += 0.7071f * frame[7] }
        out[0] = l * DOWNMIX_LEVEL; out[1] = r * DOWNMIX_LEVEL
    }

    private const val DOWNMIX_LEVEL = 0.7f

    /**
     * The player's half: 16-bit stereo, 5.1 or 7.1 in, 16-bit stereo out,
     * leant towards the screen. The gains glide across each buffer, so a
     * turn of the head never clicks. Anything else passes by untouched.
     */
    class Processor : BaseAudioProcessor() {
        private var last = floatArrayOf(1f, 1f, 1f)
        private var frame = FloatArray(8)
        private val folded = FloatArray(2)

        override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
            if (!enabled || inputAudioFormat.encoding != C.ENCODING_PCM_16BIT || inputAudioFormat.channelCount !in setOf(2, 6, 8))
                return AudioProcessor.AudioFormat.NOT_SET
            return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, 2, C.ENCODING_PCM_16BIT)
        }

        override fun queueInput(inputBuffer: ByteBuffer) {
            val channels = inputAudioFormat.channelCount
            // PCM here is in the device's own byte order, as Media3's own processors read it.
            inputBuffer.order(java.nio.ByteOrder.nativeOrder())
            val frames = inputBuffer.remaining() / (2 * channels)
            if (frames == 0) { inputBuffer.position(inputBuffer.limit()); return }
            val out = replaceOutputBuffer(frames * 4)
            val target = gains(azimuth)
            val from = last
            for (i in 0 until frames) {
                for (c in 0 until channels) frame[c] = inputBuffer.short.toFloat()
                fold(frame, channels, folded)
                val t = (i + 1).toFloat() / frames
                val gl = from[0] + (target[0] - from[0]) * t
                val gr = from[1] + (target[1] - from[1]) * t
                val w = from[2] + (target[2] - from[2]) * t
                val mid = (folded[0] + folded[1]) * 0.5f
                val side = (folded[0] - folded[1]) * 0.5f
                out.putShort(clip(gl * mid + w * side))
                out.putShort(clip(gr * mid - w * side))
            }
            last = target
            inputBuffer.position(inputBuffer.limit())
            out.flip()
        }

        override fun onReset() { last = floatArrayOf(1f, 1f, 1f) }

        private fun clip(v: Float): Short = v.coerceIn(-32768f, 32767f).toInt().toShort()
    }
}

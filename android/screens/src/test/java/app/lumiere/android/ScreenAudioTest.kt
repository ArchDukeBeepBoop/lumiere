package app.lumiere.android

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import app.lumiere.android.player.ScreenAudio
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAudioTest {
    @After fun tidy() { ScreenAudio.enabled = false; ScreenAudio.azimuth = 0f }

    @Test fun straightAheadTheSoundIsUntouched() {
        val (l, r, w) = ScreenAudio.gains(0f).toList()
        assertEquals(1f, l, 1e-6f); assertEquals(1f, r, 1e-6f); assertEquals(1f, w, 1e-6f)
    }

    @Test fun theEarNearerTheScreenIsLouderAndNothingClips() {
        val left = ScreenAudio.gains(Math.toRadians(60.0).toFloat())
        assertTrue("screen to the left: left ear louder", left[0] > left[1])
        val right = ScreenAudio.gains(Math.toRadians(-60.0).toFloat())
        assertTrue("screen to the right: right ear louder", right[1] > right[0])
        for (deg in -180..180 step 15) {
            val g = ScreenAudio.gains(Math.toRadians(deg.toDouble()).toFloat())
            assertTrue("never above 1 at $deg", g[0] <= 1f + 1e-6f && g[1] <= 1f + 1e-6f)
            assertTrue("the far ear is shadowed, not silenced, at $deg", g[0] >= 0.3f && g[1] >= 0.3f)
        }
    }

    @Test fun fivePointOneFoldsWithTheCentreInBothEars() {
        val out = FloatArray(2)
        ScreenAudio.fold(floatArrayOf(0f, 0f, 1000f, 0f, 0f, 0f), 6, out)
        assertEquals(out[0], out[1], 1e-3f)
        assertTrue(out[0] > 0f)
        ScreenAudio.fold(floatArrayOf(1000f, 0f, 0f, 0f, 0f, 0f), 6, out)
        assertTrue("front left stays left", out[0] > 0f && out[1] == 0f)
    }

    @Test fun theProcessorPassesStereoThroughWhenFacingTheScreen() {
        ScreenAudio.enabled = true
        val p = ScreenAudio.Processor()
        p.configure(AudioProcessor.AudioFormat(48_000, 2, C.ENCODING_PCM_16BIT))
        p.flush()
        assertTrue(p.isActive)
        val samples = shortArrayOf(1000, -2000, 300, 400)
        p.queueInput(pcm(samples))
        val out = p.output
        assertEquals(samples.toList(), (0 until out.remaining() / 2).map { out.getShort() }.toList())
    }

    @Test fun theProcessorFoldsFivePointOneToTwoChannels() {
        ScreenAudio.enabled = true
        val p = ScreenAudio.Processor()
        val format = p.configure(AudioProcessor.AudioFormat(48_000, 6, C.ENCODING_PCM_16BIT))
        assertEquals(2, format.channelCount)
        p.flush()
        p.queueInput(pcm(shortArrayOf(100, 200, 300, 0, 0, 0, 100, 200, 300, 0, 0, 0)))
        assertEquals("two frames of stereo", 8, p.output.remaining())
    }

    @Test fun offTheQuestTheProcessorStandsAside() {
        ScreenAudio.enabled = false
        val p = ScreenAudio.Processor()
        p.configure(AudioProcessor.AudioFormat(48_000, 2, C.ENCODING_PCM_16BIT))
        assertFalse(p.isActive)
    }

    private fun pcm(samples: ShortArray): ByteBuffer =
        ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.nativeOrder()).apply { samples.forEach { putShort(it) }; flip() }
}

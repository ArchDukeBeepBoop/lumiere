package app.lumiere.android.spatial

import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.StereoMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenSoundTest {
    private val forward = Vector3(0f, 0f, 1f)
    private val left = Vector3(1f, 0f, 0f)

    @Test fun theScreenAheadIsStraightAheadAndToTheLeftIsPositive() {
        assertEquals(0f, ScreenSound.azimuth(Vector3(0f, -0.2f, 14f), forward, left), 1e-5f)
        assertEquals(Math.PI.toFloat() / 4, ScreenSound.azimuth(Vector3(1f, 0f, 1f), forward, left), 1e-5f)
        assertTrue("to the right is negative", ScreenSound.azimuth(Vector3(-1f, 0f, 1f), forward, left) < 0f)
    }

    @Test fun eachFilmsEyesBecomeTheScreensStereo() {
        assertEquals(StereoMode.LeftRight, TheaterScreen.stereoModeOf(StereoLayout.SIDE_BY_SIDE))
        assertEquals(StereoMode.UpDown, TheaterScreen.stereoModeOf(StereoLayout.TOP_BOTTOM))
        assertEquals(StereoMode.None, TheaterScreen.stereoModeOf(StereoLayout.MONO))
    }

    @Test fun theTransportStaysWhilePausedAndStepsAwayAfterATouch() {
        assertTrue("paused: always", Theater.transportShows(playing = false, now = 100_000, last = 0))
        assertTrue("just touched", Theater.transportShows(playing = true, now = 10_000, last = 9_000))
        assertFalse("left alone while playing", Theater.transportShows(playing = true, now = 20_000, last = 9_000))
    }
}

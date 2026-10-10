package app.lumiere.android.spatial

import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Surround
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.StereoMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SurroundAndSoundTest {
    private val forward = Vector3(0f, 0f, 1f)
    private val left = Vector3(1f, 0f, 0f)

    @Test fun theScreenAheadIsStraightAheadAndToTheLeftIsPositive() {
        assertEquals(0f, ScreenSound.azimuth(Vector3(0f, -0.2f, 1.4f), forward, left), 1e-5f)
        val leftward = ScreenSound.azimuth(Vector3(1f, 0f, 1f), forward, left)
        assertEquals(Math.PI.toFloat() / 4, leftward, 1e-5f)
        assertTrue("to the right is negative", ScreenSound.azimuth(Vector3(-1f, 0f, 1f), forward, left) < 0f)
        assertEquals("behind you", Math.PI.toFloat(), kotlin.math.abs(ScreenSound.azimuth(Vector3(0f, 0f, -2f), forward, left)), 1e-5f)
    }

    @Test fun eachFilmsEyesBecomeTheSpheresStereo() {
        assertEquals(StereoMode.LeftRight, SurroundSphere.stereoModeOf(StereoLayout.SIDE_BY_SIDE))
        assertEquals(StereoMode.UpDown, SurroundSphere.stereoModeOf(StereoLayout.TOP_BOTTOM))
        assertEquals(StereoMode.None, SurroundSphere.stereoModeOf(StereoLayout.MONO))
    }

    @Test fun theSpheresPictureIsTheFilmsOwnSizeOrASensibleOne() {
        assertEquals(5760 to 2880, SurroundSphere.pictureSize(Surround.Request(Projection.HALF_SPHERE, StereoLayout.SIDE_BY_SIDE, 5760, 2880)))
        assertEquals(3840 to 3840, SurroundSphere.pictureSize(Surround.Request(Projection.SPHERE, StereoLayout.TOP_BOTTOM, 0, 0)))
        assertEquals(3840 to 1920, SurroundSphere.pictureSize(Surround.Request(Projection.SPHERE, StereoLayout.MONO, 0, 0)))
        assertEquals(8192 to 4096, SurroundSphere.pictureSize(Surround.Request(Projection.SPHERE, StereoLayout.MONO, 16384, 4096)))
    }
}

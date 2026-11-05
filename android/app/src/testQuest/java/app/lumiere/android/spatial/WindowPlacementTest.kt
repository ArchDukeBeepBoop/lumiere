package app.lumiere.android.spatial

import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.atan2

/**
 * In the cinema the window stood across the middle of the big screen. Away
 * from your room it now sits low, tipped back to you, under the screen.
 */
class WindowPlacementTest {
    private val eye = Vector3(0f, 1.2f, 0f)
    private val ahead = Vector3(0f, 0f, 1f)
    private val level = Quaternion.fromDirection(ahead)

    /** Degrees above (+) or below (-) your eye line of a point. */
    private fun elevation(p: Vector3): Double {
        val d = p - eye
        return Math.toDegrees(atan2(d.y.toDouble(), kotlin.math.hypot(d.x.toDouble(), d.z.toDouble())))
    }

    @Test fun inYourRoomItStandsAsAQuestWindow() {
        val p = WindowPlacement.pose(eye, ahead, level, away = false)
        assertEquals(Window.DISTANCE_M, p.t.z, 1e-4f)
        assertEquals(eye.y - Window.BELOW_EYES_M, p.t.y, 1e-4f)
    }

    @Test fun awayItSitsUnderTheBigScreen() {
        val p = WindowPlacement.pose(eye, ahead, level, away = true)
        val up = p.q * Vector3(0f, 1f, 0f)
        val top = p.t + up * (Window.HEIGHT_M / 2)
        val bottom = p.t - up * (Window.HEIGHT_M / 2)
        // Its top edge just under your eye line: the screen, middle near your eyes, shows above it.
        assertTrue("top edge at ${elevation(top)}°", elevation(top) in -8.0..-1.0)
        // Its middle in the comfortable reading band below the horizon.
        assertTrue("middle at ${elevation(p.t)}°", elevation(p.t) in -30.0..-15.0)
        assertTrue("bottom edge at ${elevation(bottom)}°", elevation(bottom) > -50.0)
        // Tipped back to face your eyes: it faces along the line from your eye.
        val facing = p.q * Vector3(0f, 0f, 1f)
        val toIt = (p.t - eye).normalize()
        assertEquals(1f, facing.dot(toIt), 1e-3f)
    }

    @Test fun itComesBeforeYouWhicheverWayYouFace() {
        val right = Vector3(1f, 0f, 0f)
        val p = WindowPlacement.pose(eye, right, Quaternion.fromDirection(right), away = true)
        assertEquals(Window.AWAY_DISTANCE_M, p.t.x, 1e-4f)
        assertEquals(0f, p.t.z, 1e-4f)
    }
}

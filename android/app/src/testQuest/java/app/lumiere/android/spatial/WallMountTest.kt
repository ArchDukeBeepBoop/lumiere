package app.lumiere.android.spatial

import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The film's screen on a wall of your room: the wall you face, flush, on the wall, your size. */
class WallMountTest {
    /** A wall 3 m ahead, 4 m wide, from the floor to 2.6 m, its middle 1.3 m up; Space Setup's normal facing you. */
    private val ahead = WallMount.Wall("ahead", Pose(Vector3(0f, 1.3f, 3f), Quaternion.fromDirection(Vector3(0f, 0f, -1f))),
        -2f, 2f, -1.3f, 1.3f)
    /** The same wall with its normal the other way round: a mount must not care. */
    private val reversed = ahead.copy(id = "reversed", pose = Pose(Vector3(0f, 1.3f, 3f), Quaternion.fromDirection(Vector3(0f, 0f, 1f))))
    /** A wall on your left, 2 m off. */
    private val left = WallMount.Wall("left", Pose(Vector3(2f, 1.3f, 0f), Quaternion.fromDirection(Vector3(-1f, 0f, 0f))),
        -2.5f, 2.5f, -1.3f, 1.3f)
    private val eye = Vector3(0f, 1.2f, 0f)

    @Test fun yourGazeFindsTheWallYouFace() {
        val (wall, at) = WallMount.facing(listOf(left, ahead), eye, Vector3(0f, 0f, 1f))!!
        assertEquals("ahead", wall.id)
        assertEquals(0f, at.first, 1e-3f)
        assertEquals(-0.1f, at.second, 1e-3f)
        assertEquals("left", WallMount.facing(listOf(left, ahead), eye, Vector3(1f, 0f, 0.2f).normalize())!!.first.id)
        // Looking away from every wall, or past a wall's edge: none.
        assertNull(WallMount.facing(listOf(left, ahead), eye, Vector3(-1f, 0f, -0.1f).normalize()))
        assertNull(WallMount.hit(ahead, eye, Vector3(2f, 0f, 1f).normalize()))
    }

    @Test fun eitherWayRoundTheWallTakesTheScreen() {
        assertNotNull(WallMount.hit(reversed, eye, Vector3(0f, 0f, 1f)))
        val p = WallMount.pose(reversed, 0f, 0f, eye)
        assertTrue("in front of the wall, toward you: ${p.t.z}", p.t.z < 3f && p.t.z > 2.9f)
    }

    @Test fun itHangsFlushAndFacesYou() {
        val p = WallMount.pose(ahead, 0.5f, 0.2f, eye)
        assertEquals(3f - WallMount.PROUD, p.t.z, 1e-3f)
        // Seen from the room, as the Theater's screen faces its viewer: its forward looks into the wall.
        val forward = p.q * Vector3(0f, 0f, 1f)
        assertEquals(1f, forward.z, 1e-3f)
        assertEquals("upright", 0f, forward.y, 1e-3f)
    }

    @Test fun itsSizeIsYoursButTheWallHoldsIt() {
        // 85° from 3 m wants 5.5 m: the 4 m wall holds 3.84 m.
        assertEquals(4f - 2 * WallMount.MARGIN, WallMount.width(ahead, 85f, 3f, 16f / 9f), 1e-3f)
        // 55° from 2 m is smaller than the wall: as asked.
        val small = WallMount.width(ahead, 55f, 2f, 16f / 9f)
        assertEquals(2 * 2f * kotlin.math.tan(Math.toRadians(27.5)).toFloat(), small, 1e-3f)
        // A squarer film is held by the wall's height.
        val square = WallMount.width(ahead, 115f, 4f, 1.2f)
        assertTrue("height-bound: $square", square / 1.2f <= ahead.height - 2 * WallMount.MARGIN + 1e-3f)
    }

    @Test fun theWholeScreenStaysOnTheWallAtATVsHeight() {
        val w = 2.4f; val h = w * 9 / 16
        val (x, y) = WallMount.fit(ahead, 1.9f, -1.2f, w, h)
        assertTrue("on the wall across: $x", x + w / 2 <= ahead.maxX - WallMount.MARGIN + 1e-4f)
        assertTrue("its middle at least a TV's height: $y", y >= ahead.minY + WallMount.LOWEST_MIDDLE - 1e-4f)
        assertTrue("under the ceiling", y + h / 2 <= ahead.maxY - WallMount.MARGIN + 1e-4f)
        // Too big to move: centred.
        assertEquals(0f, WallMount.fit(ahead, 1.5f, 0f, 4f, 2f).first, 1e-4f)
    }

    @Test fun howFarYouStand() {
        assertEquals(3f, WallMount.distance(ahead, eye), 1e-4f)
        assertEquals(3f, WallMount.distance(reversed, eye), 1e-4f)
    }
}

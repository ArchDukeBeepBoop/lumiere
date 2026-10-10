package app.lumiere.android.spatial

import kotlin.math.abs
import kotlin.math.hypot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SeatsTest {
    @Test fun roomSizesRunFromALaptopToABigTv() {
        val widths = (0 until Seats.ROOM.size).map { Seats.room(it, curved = true).widthM }
        assertTrue("each step larger", widths.zipWithNext().all { (a, b) -> b > a })
        val smallest = Seats.angleDegrees(widths.first(), Window.DISTANCE_M)
        assertTrue("smallest is a laptop's $smallest", smallest in 34f..42f)
        assertTrue("largest fills most of the view", Seats.angleDegrees(widths.last(), Window.DISTANCE_M) > 80f)
        assertEquals(Seats.room(Seats.ROOM.lastIndex, true), Seats.room(99, true))
        assertEquals(Seats.room(0, true), Seats.room(-3, true))
    }

    @Test fun everyoneStartsAtTheWindowsOwnSize() {
        assertEquals(1f, Seats.roomScale(app.lumiere.android.Stage.roomSize), 0f)
        val start = Seats.angleDegrees(Window.WIDTH_M, Window.DISTANCE_M)
        assertTrue("about 60 degrees, a big TV up close: $start", start in 55f..65f)
    }

    @Test fun screensKeepTheWindowsShapeSoTheAppLaysOutTheSame() {
        listOf(Seats.room(0, true), Seats.room(4, false), Seats.cinema(1, true)).forEach {
            assertEquals(Window.HEIGHT_DP.toFloat() / Window.WIDTH_DP, it.heightM / it.widthM, 1e-4f)
        }
    }

    @Test fun curvedIsCentredOnYouAndFlatIsFlat() {
        assertEquals(Window.DISTANCE_M, Seats.room(2, curved = true).radiusM, 0f)
        assertEquals(Seats.rowDistance(2), Seats.cinema(2, curved = true).radiusM, 0f)
        // Flat: the widest screen bulges less than a hand's breadth.
        val wide = Seats.cinema(0, curved = false)
        val bulge = wide.radiusM - kotlin.math.sqrt(wide.radiusM * wide.radiusM - (wide.widthM / 2) * (wide.widthM / 2))
        assertTrue("bulge $bulge m", bulge < 0.06f)
    }

    @Test fun theCinemasRowsAreLikeAppleTvs() {
        val width = Seats.CINEMA_WIDTH_M
        val back = Seats.angleDegrees(width, Seats.rowDistance(0))
        val middle = Seats.angleDegrees(width, Seats.rowDistance(1))
        val front = Seats.angleDegrees(width, Seats.rowDistance(2))
        assertTrue("back $back", back in 35f..42f)
        assertTrue("middle $middle", middle in 48f..56f)
        assertTrue("front $front", front in 62f..72f)
    }

    @Test fun theCinemaScreenStandsOnTheStageNearYourEyeLine() {
        val height = Seats.cinema(1, true).heightM
        listOf(0.4f, 1.2f, 1.7f).forEach { eyes ->
            val middle = Seats.screenMiddleY(eyes, height)
            assertTrue("foot ${middle - height / 2} at eyes $eyes", middle - height / 2 >= Seats.STAGE_M - 1e-4f)
            assertTrue("middle above the eyes", middle >= eyes + Seats.ABOVE_EYES - 1e-4f)
        }
        // Seated in the middle row, the middle of the picture is no more than ~8 degrees up.
        val up = Math.toDegrees(kotlin.math.atan(((Seats.screenMiddleY(1.2f, height) - 1.2f) / Seats.rowDistance(1)).toDouble()))
        assertTrue("$up degrees up", up < 8.5)
    }

    @Test fun theSidebarRidesTheCurvePastTheLeftEdgeFacingYou() {
        val shape = Seats.room(2, curved = true)
        val (x, z, dx, dz) = Seats.sidebarBeside(shape)
        // On the same circle as the screen, centred on you at (0, 0, -r) in the screen's space.
        assertEquals(shape.radiusM, hypot(x, z + shape.radiusM), 1e-4f)
        assertTrue("to the left, past the edge", x > 0f && x < shape.widthM / 2 + 0.2f)
        assertTrue("nearer you than the middle", z < 0f)
        // Facing you: it looks along the line from you to it.
        assertEquals(0f, x * dz - (z + shape.radiusM) * dx, 1e-4f)
        // Flat, it simply sits beside the edge.
        val flat = Seats.sidebarBeside(Seats.room(2, curved = false))
        assertEquals(shape.widthM / 2 + Window.SIDEBAR_GAP_M + Window.SIDEBAR_WIDTH_M / 2, flat[0], 0.01f)
        assertTrue(abs(flat[1]) < 0.01f)
    }
}

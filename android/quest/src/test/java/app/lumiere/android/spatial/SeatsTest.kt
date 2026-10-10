package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SeatsTest {
    @Test fun roomSizesRunFromALaptopToABigTv() {
        val widths = Seats.ROOM.map { it * Window.WIDTH_M }
        assertTrue("each step larger", widths.zipWithNext().all { (a, b) -> b > a })
        assertEquals(1.2f, widths.first(), 0.01f)
        assertTrue("largest fills most of the view", Seats.angleDegrees(widths.last(), Window.DISTANCE_M) > 80f)
        assertEquals(Seats.ROOM.last(), Seats.roomScale(99))
        assertEquals(Seats.ROOM.first(), Seats.roomScale(-3))
    }

    @Test fun theCinemasRowsAreLikeAppleTvs() {
        val width = Window.WIDTH_M * Seats.CINEMA_SCALE
        val back = Seats.angleDegrees(width, Seats.rowDistance(0))
        val middle = Seats.angleDegrees(width, Seats.rowDistance(1))
        val front = Seats.angleDegrees(width, Seats.rowDistance(2))
        assertTrue("back $back", back in 35f..42f)
        assertTrue("middle $middle", middle in 48f..56f)
        assertTrue("front $front", front in 62f..72f)
    }

    @Test fun theCinemaScreenStandsOnTheStageNotInTheFloor() {
        val height = Window.HEIGHT_M * Seats.CINEMA_SCALE
        listOf(0.4f, 1.2f, 1.7f).forEach { eyes ->
            val middle = Seats.screenMiddleY(eyes, height)
            assertTrue("foot ${middle - height / 2} at eyes $eyes", middle - height / 2 >= Seats.STAGE_M - 1e-4f)
            assertTrue("middle above the eyes", middle >= eyes + Seats.ABOVE_EYES - 1e-4f)
        }
        // A screen short enough to sit above the eyes just does.
        assertEquals(1.9f, Seats.screenMiddleY(1.2f, 1f), 1e-4f)
    }
}

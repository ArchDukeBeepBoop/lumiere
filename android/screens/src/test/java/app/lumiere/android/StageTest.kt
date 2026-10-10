package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Test

/** How films are watched: the places come round in turn, and the size stays within its five steps. */
class StageTest {
    @Test fun placesComeRoundInTurn() {
        val start = Stage.place
        val seen = (0 until Stage.Place.entries.size).map { Stage.nextPlace(); Stage.place }
        assertEquals(Stage.Place.entries.toSet(), seen.toSet())
        assertEquals(start, Stage.place)
    }

    @Test fun theScreenSizeStaysWithinItsSteps() {
        repeat(10) { Stage.larger() }
        assertEquals(Stage.SCREEN_SIZES - 1, Stage.screenSize)
        repeat(10) { Stage.smaller() }
        assertEquals(0, Stage.screenSize)
    }
}

package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Test

/** How films are watched: the places come round in turn, old saved places still load, and the size stays within its five steps. */
class StageTest {
    @Test fun placesComeRoundInTurn() {
        val start = Stage.place
        val seen = (0 until Stage.Place.entries.size).map { Stage.nextPlace(); Stage.place }
        assertEquals(Stage.Place.entries.toSet(), seen.toSet())
        assertEquals(start, Stage.place)
    }

    @Test fun thePlacesComeInAnOrderThatReadsNaturally() {
        repeat(Stage.Place.entries.size) { if (Stage.place != Stage.Place.ROOM) Stage.nextPlace() }
        assertEquals(Stage.Place.ROOM, Stage.place)
        val seen = (0 until Stage.Place.entries.size).map { Stage.nextPlace(); Stage.place }
        assertEquals(listOf(Stage.Place.CINEMA, Stage.Place.CABIN, Stage.Place.LAKE, Stage.Place.CLOUDS, Stage.Place.MOON,
            Stage.Place.STATION, Stage.Place.VOID, Stage.Place.SPACE, Stage.Place.ROOM), seen)
    }

    @Test fun placesSavedByEarlierVersionsStillLoad() {
        // What the app saved before the cabin and the lakeside came: names, never positions.
        mapOf("ROOM" to Stage.Place.ROOM, "CINEMA" to Stage.Place.CINEMA, "VOID" to Stage.Place.VOID, "SPACE" to Stage.Place.SPACE)
            .forEach { (saved, place) -> assertEquals(saved, place, Stage.placeNamed(saved)) }
        assertEquals(Stage.Place.CABIN, Stage.placeNamed("CABIN"))
        assertEquals(Stage.Place.LAKE, Stage.placeNamed("LAKE"))
        // Nothing saved yet, or a place this version doesn't know: the cinema, where everyone starts.
        assertEquals(Stage.Place.CINEMA, Stage.placeNamed(null))
        assertEquals(Stage.Place.CINEMA, Stage.placeNamed("GARDEN"))
        assertEquals(Stage.Place.CINEMA, Stage.placeNamed("2"))
    }

    @Test fun theScreenSizeStaysWithinItsSteps() {
        repeat(10) { Stage.larger() }
        assertEquals(Stage.SCREEN_SIZES - 1, Stage.screenSize)
        repeat(10) { Stage.smaller() }
        assertEquals(0, Stage.screenSize)
    }
}

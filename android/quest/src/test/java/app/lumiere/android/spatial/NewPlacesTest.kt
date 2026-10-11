package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Above the clouds, the Moon and the space station: whatever size and
 * shape of film, from a low seat, a chair or standing, nothing of the
 * place hides the screen, every box has a size, and the tall things stand
 * beside you or behind.
 */
class NewPlacesTest {
    private val films = listOf(1920 to 1080, 1920 to 804, 1080 to 1080)
    private val eyes = listOf(0.9f, 1.2f, 1.7f)

    private fun specs(place: Stage.Place) = films.flatMap { (w, h) ->
        listOf(false, true).flatMap { curved ->
            (0 until Stage.SCREEN_SIZES).map { size ->
                TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, w, h), place, size, curved)
            }
        }
    }

    private fun neverHides(place: Stage.Place, build: (TheaterGeometry.Spec, Float) -> List<Block<*>>, moving: Set<Any> = emptySet()) {
        val across = listOf(-0.5f, -0.3f, 0f, 0.3f, 0.5f)
        val up = listOf(-0.5f, -0.4f, -0.25f, 0f, 0.25f, 0.5f)
        specs(place).forEach { spec ->
            eyes.forEach { e ->
                val parts = build(spec, e)
                parts.forEach { p -> assertTrue("$place: ${p.kind} is ${p.w} × ${p.h} × ${p.d}", p.w > 0f && p.h > 0f && p.d > 0f) }
                val eye = Point(0f, e, 0f)
                screenPoints(spec, e, across, up).forEach { target ->
                    parts.filter { it.kind !in moving }.forEach { p ->
                        if (segmentHits(p, eye, target))
                            fail("$place: ${p.kind} at (${p.x}, ${p.y}, ${p.z}) hides the screen at (${target.x}, ${target.y}, ${target.z}): " +
                                "${spec.widthM} m${if (spec.radiusM != null) " curved" else ""}, eyes at $e")
                    }
                }
            }
        }
    }

    @Test fun theTerraceNeverHidesTheScreen() =
        neverHides(Stage.Place.CLOUDS, { spec, e -> Terrace.build(e, TheaterGeometry.footSlope(spec)) })

    @Test fun theMoonBaseNeverHidesTheScreen() =
        neverHides(Stage.Place.MOON, { spec, e -> MoonBase.build(e, TheaterGeometry.footSlope(spec)) })

    @Test fun theStationNeverHidesItsScreen() =
        neverHides(Stage.Place.STATION, { spec, e -> Station.build(spec.widthM, spec.heightM, e + spec.aboveEyesM, spec.distanceM, e) },
            moving = setOf(Station.Kind.NOTEBOOK, Station.Kind.PEN, Station.Kind.POUCH))

    @Test fun onTheDecksEverythingTallIsBesideOrBehindYou() {
        val terrace = Terrace.build(1.2f)
        assertTrue(terrace.filter { it.top > Terrace.LIP + 1e-4f }.all { it.front <= 0.04f })
        val moon = MoonBase.build(1.2f)
        assertTrue(moon.filter { it.top > MoonBase.LIP + 1e-4f }.all { it.front <= 0.04f })
        // Each deck is under you, its top at your floor.
        assertEquals(0f, terrace.filter { it.kind == Terrace.Kind.DECK }.maxOf { it.top }, 1e-5f)
        assertEquals(0f, moon.filter { it.kind == MoonBase.Kind.DECK }.maxOf { it.top }, 1e-5f)
        assertTrue("a few draw calls: ${terrace.size}, ${moon.size}", terrace.size <= 80 && moon.size <= 80)
    }

    @Test fun theStationHoldsItsScreenAndLooksOut() {
        specs(Stage.Place.STATION).forEach { spec ->
            val parts = Station.build(spec.widthM, spec.heightM, 1.2f + spec.aboveEyesM, spec.distanceM)
            assertTrue("${parts.size} boxes", parts.size <= Station.MOST_BOXES)
            val front = parts.single { it.kind == Station.Kind.FRONT }
            assertTrue("the screen before its bulkhead", front.back >= spec.distanceM)
            assertTrue("wider than the screen", front.w > spec.widthM)
            val top = 1.2f + spec.aboveEyesM + spec.heightM / 2
            assertTrue("the ceiling over the screen", parts.filter { it.kind == Station.Kind.CEILING }.all { it.bottom >= top })
            // Windows down both sides: frames between them, and a gap over the sill.
            for (side in floatArrayOf(1f, -1f))
                assertTrue(parts.count { it.kind == Station.Kind.FRAME && it.x * side > Station.HALF - 0.01f } >= 2)
        }
        // The things floating free drift, the panel's lights blink, the walls stay put.
        assertTrue(Station.moves(Station.Kind.PEN, 3, 5f) != null && Station.moves(Station.Kind.WALL, 3, 5f) == null)
    }

    @Test fun eachNewPlaceHasItsSkyAndSound() {
        listOf(Stage.Place.CLOUDS, Stage.Place.MOON, Stage.Place.STATION).forEach { place ->
            assertTrue("$place has a sky", Sky.pictureFor(place) != null)
            assertTrue("$place has its sound", Soundscape.sceneFor(place, true) != null)
        }
        assertTrue(TheaterGeometry.fixedScreen(Stage.Place.STATION))
        assertTrue(!TheaterGeometry.fixedScreen(Stage.Place.CLOUDS) && !TheaterGeometry.fixedScreen(Stage.Place.MOON))
    }
}

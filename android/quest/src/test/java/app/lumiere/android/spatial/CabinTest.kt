package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The cabin round its wall screen: nothing hides the screen, the room holds it at every size, its windows look out, and your seat is your own. */
class CabinTest {
    private class Room(val spec: TheaterGeometry.Spec, val eyes: Float, val parts: List<Block<Cabin.Kind>>) {
        val middle get() = eyes + spec.aboveEyesM
        override fun toString() = "%.2f m away, %.2f × %.2f m%s, eyes at %.1f m".format(
            spec.distanceM, spec.widthM, spec.heightM, if (spec.radiusM != null) " curved" else "", eyes)
    }

    /**
     * The cabin for every size, flat and curved, for a 2.39:1 film, a 16:9
     * one, a 4:3 one and the squarest picture a screen takes, from a low
     * sofa's eyes, a chair's, and standing: as the Director builds it.
     */
    private fun rooms() = listOf(1920 to 804, 1920 to 1080, 1440 to 1080, 1080 to 1080).flatMap { (w, h) ->
        listOf(false to false, true to false, false to true, true to true).flatMap { (curved, fill) ->
            (0 until Stage.SCREEN_SIZES).flatMap { size ->
                val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, w, h), Stage.Place.CABIN, size, curved, fill)
                listOf(0.9f, 1.2f, 1.7f).map { eyes ->
                    Room(spec, eyes, Cabin.build(spec.widthM, spec.heightM, eyes + spec.aboveEyesM, spec.distanceM, eyes, TheaterGeometry.footSlope(spec)))
                }
            }
        }
    }

    /** A box with no size, or turned inside out, is nothing to the eye and may be a crash to the SDK. */
    @Test fun everyBoxHasASize() {
        rooms().forEach { room ->
            room.parts.forEach { b -> assertTrue("$room: ${b.kind} is ${b.w} × ${b.h} × ${b.d}", b.w > 0f && b.h > 0f && b.d > 0f) }
        }
        listOf(0.9f, 1.2f, 1.7f).forEach { eyes ->
            listOf(0f, 0.05f, 0.2f).forEach { slope ->
                Dock.build(eyes, slope).forEach { b -> assertTrue("pontoon at $eyes m: ${b.kind} is ${b.w} × ${b.h} × ${b.d}", b.w > 0f && b.h > 0f && b.d > 0f) }
            }
        }
    }

    @Test fun everySightlineToTheScreenIsClear() {
        val across = listOf(-0.5f, -0.25f, 0f, 0.25f, 0.5f)
        rooms().forEach { room ->
            val eye = Point(0f, room.eyes, 0f)
            screenPoints(room.spec, room.eyes, across, listOf(-0.5f, -0.3f, 0f, 0.5f)).forEach { target ->
                room.parts.forEach { p ->
                    if (segmentHits(p, eye, target))
                        fail("${p.kind} at (${p.x}, ${p.y}, ${p.z}) hides the screen at (${target.x}, ${target.y}, ${target.z}): $room")
                }
            }
        }
    }

    @Test fun theScreenStandsInFrontOfItsWallInsideTheRoom() {
        rooms().forEach { room ->
            val (spec, parts) = room.spec to room.parts
            val wall = parts.single { it.kind == Cabin.Kind.FRONT_WALL }
            assertEquals("5 cm in front of the wall: $room", spec.distanceM + Cabin.SCREEN_GAP, wall.back, 1e-4f)
            val bottom = room.middle - spec.heightM / 2
            val top = room.middle + spec.heightM / 2
            assertTrue("the wall frames the screen across: $room", wall.x - wall.w / 2 < -spec.widthM / 2 && wall.x + wall.w / 2 > spec.widthM / 2)
            assertTrue("and up: $room", wall.bottom < bottom && wall.top > top)
            assertTrue("under the ceiling: $room", parts.single { it.kind == Cabin.Kind.CEILING }.bottom > top)
            assertTrue("beams over the screen: $room", parts.filter { it.kind == Cabin.Kind.BEAM }.all { it.bottom > top })
            val floor = parts.filter { it.kind == Cabin.Kind.FLOOR }.minBy { it.top }
            assertTrue("the floor under it: $room", floor.top < bottom && floor.front >= wall.back)
            val credenza = parts.single { it.kind == Cabin.Kind.CREDENZA }
            assertTrue("the credenza under its foot: $room", credenza.top < bottom && credenza.bottom >= floor.top - 1e-4f)
            parts.filter { it.kind == Cabin.Kind.WALL }.forEach { side ->
                assertTrue("the side walls beyond its edges: $room", kotlin.math.abs(side.x) - side.w / 2 > spec.widthM / 2)
            }
        }
    }

    @Test fun theCeilingIsAGreatRooms() {
        rooms().filter { it.eyes <= 1.2f }.forEach { room ->
            val ceiling = room.parts.single { it.kind == Cabin.Kind.CEILING }.bottom
            assertTrue("$ceiling m: $room", ceiling in 4.5f..5.5f)
        }
    }

    @Test fun bothSideWallsHaveWindowsFromFloorToCeiling() {
        rooms().forEach { room ->
            for (side in listOf(1f, -1f)) {
                val walls = room.parts.filter { it.kind == Cabin.Kind.WALL && it.x * side > 0 }.sortedBy { it.back }
                val gaps = walls.zipWithNext().map { (a, b) -> b.back - a.front }
                assertTrue("a window bay on the ${if (side > 0) "left" else "right"}: $gaps, $room", gaps.any { it >= 1f })
                assertTrue("mullions across it: $room", room.parts.any { it.kind == Cabin.Kind.MULLION && it.x * side > 0 })
                val floor = room.parts.filter { it.kind == Cabin.Kind.FLOOR }.minOf { it.bottom }
                val ceiling = room.parts.single { it.kind == Cabin.Kind.CEILING }.bottom
                walls.forEach { assertTrue("solid from floor to ceiling: $room", it.bottom <= floor + 1e-4f && it.top >= ceiling - 1e-4f) }
            }
        }
    }

    @Test fun theSofaIsBehindOrBelowYourEyesAndNothingStandsWhereYouAre() {
        rooms().forEach { room ->
            val sofa = room.parts.filter { it.kind == Cabin.Kind.SOFA }
            assertTrue(sofa.size >= 3)
            sofa.forEach { p ->
                assertTrue("${p.top} m: below your eyes, $room", p.top < room.eyes - 0.1f)
                if (p.top > 0.7f) assertTrue("its back behind you: ${p.front}", p.front < -0.3f)
            }
            room.parts.forEach { p ->
                if (overlaps(p, -0.5f, 0.5f, 0.05f, 2.0f, -0.4f, 0.4f)) fail("${p.kind} at ${p.x},${p.y},${p.z} is where you sit: $room")
            }
        }
    }

    @Test fun aSunkenRoomIsReachedByStepsUnderYourSightline() {
        // A 4:3 film from a chair at the nearest seat: the screen's foot is below your floor.
        val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, 1440, 1080), Stage.Place.CABIN, 4, false)
        val parts = Cabin.build(spec.widthM, spec.heightM, 1.2f + spec.aboveEyesM, spec.distanceM, 1.2f, TheaterGeometry.footSlope(spec))
        assertTrue("the foot below your floor", 1.2f + spec.aboveEyesM - spec.heightM / 2 < 0f)
        val steps = parts.filter { it.kind == Cabin.Kind.STEP }.sortedBy { it.z }
        assertTrue("steps down: ${steps.size}", steps.isNotEmpty())
        assertTrue("each lower than the last", steps.zipWithNext().all { (a, b) -> b.top < a.top })
        val floors = parts.filter { it.kind == Cabin.Kind.FLOOR }
        assertEquals("your dais at your floor", 0f, floors.maxOf { it.top }, 0f)
    }

    @Test fun aFewDrawCallsWorth() {
        rooms().forEach { room -> assertTrue("${room.parts.size} boxes: $room", room.parts.size <= Cabin.MOST_BOXES) }
    }

    @Test fun whatFacesTheScreenCatchesMoreOfTheFilm() {
        val red = Triple(1f, 0f, 0f)
        fun redGain(kind: Cabin.Kind) = Cabin.colour(kind, CinemaLight.PLAYING, red).first - Cabin.colour(kind, CinemaLight.PLAYING, null).first
        assertTrue(redGain(Cabin.Kind.BACK_WALL) > redGain(Cabin.Kind.WALL))
        assertTrue(redGain(Cabin.Kind.WALL) > redGain(Cabin.Kind.FRONT_WALL))
        assertTrue("the room dims for a film", Cabin.colour(Cabin.Kind.FLOOR, CinemaLight.PLAYING, null).first < Cabin.colour(Cabin.Kind.FLOOR, 1f, null).first)
        assertEquals("the fire burns on", Cabin.baseColour(Cabin.Kind.FIRE), Cabin.colour(Cabin.Kind.FIRE, CinemaLight.PLAYING, red))
    }
}

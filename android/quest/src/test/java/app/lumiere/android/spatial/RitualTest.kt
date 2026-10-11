package app.lumiere.android.spatial

import app.lumiere.android.Stage
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The cinema's ritual: the front curtain drawn as a film comes and opening
 * slowly as it starts, never across a film that's on; the house lights at
 * the hall's own pace; the film's light gliding; a seat for every size.
 */
class RitualTest {
    @After fun reset() { FrontCurtain.closed = 0f; FrontCurtain.target = 0f }

    @Test fun theCurtainIsDrawnAsAFilmComesAndOpenWhileItPlays() {
        assertEquals(1f, FrontCurtain.targetFor(coming = true, on = false, sinceEndMs = Long.MAX_VALUE / 2), 0f)
        assertEquals(0f, FrontCurtain.targetFor(coming = false, on = true, sinceEndMs = 0), 0f)
        assertEquals(0f, FrontCurtain.targetFor(coming = true, on = true, sinceEndMs = 0), 0f)
        // Just after a film: drawn; a while after: open on the next title.
        assertEquals(1f, FrontCurtain.targetFor(coming = false, on = false, sinceEndMs = 1_000), 0f)
        assertEquals(0f, FrontCurtain.targetFor(coming = false, on = false, sinceEndMs = FrontCurtain.HOLD_MS + 1), 0f)
    }

    @Test fun itClosesQuicklyAndOpensSlowly() {
        FrontCurtain.closed = 0f; FrontCurtain.target = 1f
        repeat(36) { FrontCurtain.step(1f / 30) }           // 1.2 s
        assertEquals(1f, FrontCurtain.closed, 1e-3f)
        FrontCurtain.target = 0f
        repeat(30) { FrontCurtain.step(1f / 30) }           // 1 s of 5
        assertTrue("opening slowly: ${FrontCurtain.closed}", FrontCurtain.closed in 0.75f..0.85f)
        repeat(150) { FrontCurtain.step(1f / 30) }
        assertEquals(0f, FrontCurtain.closed, 0f)
    }

    @Test fun theHallsLightsGoDownAtTheirOwnPace() {
        var room = CinemaLight.LIT; var hall = CinemaLight.LIT
        repeat(38) {     // a second and a half of 40 ms looks
            room = CinemaLight.ease(room, CinemaLight.PLAYING)
            hall = CinemaLight.ease(hall, CinemaLight.PLAYING, CinemaLight.HALL_DOWN)
        }
        assertEquals(CinemaLight.PLAYING, room, 0.01f)
        assertTrue("the hall still going down: $hall", hall > 0.3f)
        repeat(150) { hall = CinemaLight.ease(hall, CinemaLight.PLAYING, CinemaLight.HALL_DOWN) }
        assertEquals(CinemaLight.PLAYING, hall, 0.01f)
    }

    @Test fun theFilmsLightGlidesAndSettles() {
        var c: Triple<Float, Float, Float>? = Triple(0f, 0f, 0f)
        val to = Triple(1f, 0.5f, 0.2f)
        c = CinemaLight.easeTint(c, to)
        assertTrue("a step, not a jump: $c", c!!.first in 0.05f..0.3f)
        repeat(80) { c = CinemaLight.easeTint(c, to) }
        assertEquals(to, c)
        // Nothing to take it from: straight there; nothing to go to: none.
        assertEquals(to, CinemaLight.easeTint(null, to))
        assertEquals(null, CinemaLight.easeTint(to, null))
    }

    @Test fun everySizeIsASeatInTheCinema() {
        assertEquals(Stage.SCREEN_SIZES, Stage.SEATS.size)
        assertEquals(Stage.SCREEN_SIZES, Stage.SIZES.size)
        // Further back is a smaller screen: the back row is the first size.
        assertTrue(Stage.SEATS.first().contains("back"))
    }

    @Test fun theLeftHalfOfThePictureLightsTheLeftWall() {
        val s = Modeller<String>()
        s.part("wall", 8f); s.box(7.9f, 8.1f, 0f, 3f, 0f, 10f)
        s.part("wall", -8f); s.box(-8.1f, -7.9f, 0f, 3f, 0f, 10f)
        s.part("seat", 0f); s.box(-1f, 1f, 0f, 1f, 2f, 3f)
        val sides = s.meshes.keys.groupBy { it.kind }.mapValues { (_, v) -> v.map { it.side }.toSet() }
        assertEquals(setOf(Side.LEFT, Side.RIGHT), sides["wall"])
        assertEquals(setOf(Side.MIDDLE), sides["seat"])
    }
}

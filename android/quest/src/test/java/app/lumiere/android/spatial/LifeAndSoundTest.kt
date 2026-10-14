package app.lumiere.android.spatial

import app.lumiere.android.Stage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/** The places' life: flames that stay in their hearth, fireflies that wander near home, and sound that never clips. */
class LifeAndSoundTest {
    private val times = (0 until 2400).map { it * 0.05f }

    @Test fun flamesFlickerInPlace() {
        for (i in 0 until 6) times.forEach { t ->
            val s = Life.flame(i, t)
            assertTrue("flame $i at $t rises ${s.dy}", abs(s.dy) <= 0.025f && abs(s.dx) <= 0.005f && s.dz == 0f)
        }
        // The body of the fire burns steadily; the tongues come and go, but mostly burn.
        assertTrue(times.all { Life.flame(0, it).lit })
        val tongue = times.count { Life.flame(1, it).lit }.toFloat() / times.size
        assertTrue("a tongue lit $tongue of the time", tongue in 0.6f..0.99f)
    }

    @Test fun firefliesWanderNearHomeAndGlowNowAndThen() {
        for (i in 0 until 18) {
            times.forEach { t ->
                val s = Life.firefly(i, t)
                assertTrue("firefly $i strays ${s.dx}, ${s.dz}", abs(s.dx) <= 0.61f && abs(s.dz) <= 0.61f && abs(s.dy) <= 0.22f)
            }
            val glowing = times.count { Life.firefly(i, it).lit }.toFloat() / times.size
            assertTrue("firefly $i glows $glowing of the time", glowing in 0.15f..0.33f)
        }
    }

    @Test fun eachPlaceHasItsSoundAndTheDarkIsQuiet() {
        assertEquals(Soundscape.Scene.CABIN, Soundscape.sceneFor(Stage.Place.CABIN, false))
        assertEquals(Soundscape.Scene.LAKE, Soundscape.sceneFor(Stage.Place.LAKE, false))
        assertEquals(Soundscape.Scene.CINEMA, Soundscape.sceneFor(Stage.Place.CINEMA, true))
        assertNull("no hall, no hush", Soundscape.sceneFor(Stage.Place.CINEMA, false))
        assertNull(Soundscape.sceneFor(Stage.Place.VOID, true))
        assertNull("your room has its own", Soundscape.sceneFor(Stage.Place.ROOM, true))
    }

    @Test fun everySceneSoundsAndNoneClips() {
        Soundscape.Scene.entries.forEach { scene ->
            val synth = Soundscape(seed = 7)
            val out = FloatArray(2 * Soundscape.RATE * 3)
            synth.render(out, scene, 0f, 1f)
            assertTrue("$scene stays within -1..1", out.all { it.isFinite() && it in -1f..1f })
            val rms = kotlin.math.sqrt(out.map { it * it }.average())
            assertTrue("$scene is heard: $rms", rms > 0.003)
            assertTrue("$scene is quiet: $rms", rms < 0.4)
        }
        val silent = FloatArray(512).also { Soundscape().render(it, null, 0f, 1f) }
        assertTrue(silent.all { it == 0f })
    }

    @Test fun soundsComeFromWhereTheyAre() {
        val (l, r) = Soundscape.pan(1.5f)
        assertTrue("to your left, louder in the left ear", l > r)
        val (fl, fr) = Soundscape.pan(0f)
        assertEquals("ahead, both ears alike", fl, fr, 1e-5f)
        // Turn toward the fire (on your left) and it comes before you.
        val (tl, tr) = Soundscape.pan(Soundscape.FIRE_ANGLE - Soundscape.FIRE_ANGLE)
        assertEquals(tl, tr, 1e-5f)
    }

    @Test fun itFadesRatherThanCuts() {
        assertEquals(0.07f, Soundscape.fade(0f, 1f, 0.1f), 1e-5f)
        assertEquals(0.93f, Soundscape.fade(1f, 0f, 0.1f), 1e-5f)
        assertEquals(0.2f, Soundscape.fade(0.18f, 0.2f, 1f), 1e-5f)
    }
}

package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CinemaLightTest {
    @Test fun lightsGoDownForAFilmAndHalfUpWhenPaused() {
        assertEquals(CinemaLight.PLAYING, CinemaLight.target(inPlayer = true, playing = true))
        assertEquals(CinemaLight.PAUSED, CinemaLight.target(inPlayer = true, playing = false))
        assertEquals(CinemaLight.LIT, CinemaLight.target(inPlayer = false, playing = true))
    }

    @Test fun aFullyLitRoomIsUnchanged() {
        for (level in 0..15) assertEquals(level * 17, CinemaLight.channel(level, 1f, 1f))
        assertEquals(255, CinemaLight.channel(15, 1f, 0f))
    }

    @Test fun inTheDarkTheFilmsColourSpillsALittle() {
        val red = CinemaLight.channel(0, CinemaLight.PLAYING, 1f)
        val none = CinemaLight.channel(0, CinemaLight.PLAYING, 0f)
        assertEquals(0, none)
        assertTrue("some spill", red in 10..20)
        assertTrue("the room is dim", CinemaLight.channel(15, CinemaLight.PLAYING, 0f) < 40)
    }

    @Test fun easingSettlesInAboutASecondAndAHalf() {
        var v = CinemaLight.LIT
        var ticks = 0
        while (v != CinemaLight.PLAYING && ticks < 100) { v = CinemaLight.ease(v, CinemaLight.PLAYING); ticks++ }
        assertEquals(CinemaLight.PLAYING, v)
        assertTrue("$ticks ticks at 60 ms", ticks in 15..35)
    }
}

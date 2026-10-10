package app.lumiere.android.spatial

import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The window flashed in front of the cinema's screen at the start of every
 * film and between episodes, while the player had no picture size yet.
 */
class TheaterHoldTest {
    private val film = Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 800)

    @Test fun theScreenStaysUpBetweenEpisodes() {
        val hold = TheaterHold(graceMs = 6_000)
        assertEquals(film, hold.request(film, inPlayer = true, now = 0))
        // The next episode: no picture size for a few seconds; the last screen is kept.
        assertEquals(film, hold.request(null, inPlayer = true, now = 4_000))
        assertEquals(film, hold.request(null, inPlayer = true, now = 5_999))
        // Never forever: a player that never gets a picture lets the Theater go.
        assertNull(hold.request(null, inPlayer = true, now = 6_000))
        assertNull(hold.request(null, inPlayer = true, now = 6_100))
    }

    @Test fun leavingThePlayerTakesTheScreenDownAtOnce() {
        val hold = TheaterHold()
        hold.request(film, inPlayer = true, now = 0)
        assertNull(hold.request(null, inPlayer = false, now = 100))
        // And nothing is held over for the next film.
        assertNull(hold.request(null, inPlayer = true, now = 200))
    }

    @Test fun theWindowWaitsAsideWhileAFilmStarts() {
        val hold = TheaterHold(startMs = 10_000)
        assertFalse(hold.waiting(starting = false, on = false, now = 0))
        assertTrue(hold.waiting(starting = true, on = false, now = 1_000))
        assertTrue(hold.waiting(starting = true, on = false, now = 10_999))
        // A film that can't start: the window comes back so it can say why.
        assertFalse(hold.waiting(starting = true, on = false, now = 11_000))
    }

    @Test fun eachWaitIsTimedAfresh() {
        val hold = TheaterHold(startMs = 10_000)
        assertTrue(hold.waiting(starting = true, on = false, now = 0))
        assertFalse(hold.waiting(starting = true, on = true, now = 2_000))
        // An hour later, the next episode's wait starts its own clock.
        assertTrue(hold.waiting(starting = true, on = false, now = 3_600_000))
        assertTrue(hold.waiting(starting = true, on = false, now = 3_609_000))
        assertFalse(hold.waiting(starting = true, on = false, now = 3_610_000))
    }
}

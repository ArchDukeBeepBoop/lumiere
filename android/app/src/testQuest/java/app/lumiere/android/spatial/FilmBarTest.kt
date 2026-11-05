package app.lumiere.android.spatial

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FilmBarTest {
    @Test fun upForAFewSecondsAfterAWake() {
        assertTrue(FilmBar.shown(playing = true, now = 1_000, until = 4_000, covered = false))
        assertFalse(FilmBar.shown(playing = true, now = 5_000, until = 4_000, covered = false))
    }

    @Test fun alwaysUpWhilePaused() = assertTrue(FilmBar.shown(playing = false, now = 9_000, until = 0, covered = false))

    @Test fun stepsAsideForAMenuOrThePlaces() =
        assertFalse(FilmBar.shown(playing = false, now = 0, until = 9_000, covered = true))
}

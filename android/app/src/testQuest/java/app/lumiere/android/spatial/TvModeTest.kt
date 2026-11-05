package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TvModeTest {
    @Test fun sizesAreTheDiagonalsTvsAreSoldBy() {
        // A 65″ TV is 1.44 m wide; a 200″ one 4.43 m.
        assertEquals(1.439f, TvMode.widthM(65), 0.01f)
        assertEquals(4.428f, TvMode.widthM(200), 0.01f)
        assertEquals(200, TvMode.INCHES.last())
        assertEquals("65″", TvMode.NAMES[TvMode.DEFAULT])
    }

    @Test fun aSmallWallTakesTheLargestThatFits() {
        val (w, cut) = TvMode.fitted(TvMode.INCHES.indexOf(200), 3.0f)
        assertEquals(3.0f, w, 0.001f)
        assertTrue(cut)
        assertEquals(120, TvMode.largestFitting(3.0f))
        assertFalse(TvMode.fitted(TvMode.DEFAULT, 3.0f).second)
    }
}

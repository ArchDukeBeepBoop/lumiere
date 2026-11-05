package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FilmLightTest {
    @Test fun noFilmColourLeavesTheLightPlain() =
        assertEquals(Triple(0.5f, 0.5f, 0.5f), FilmLight.light(0.5f, null))

    @Test fun aWarmFilmCastsAWarmLightWithoutDimmingIt() {
        val (r, g, b) = FilmLight.light(1f, FilmLight.Rgb(0.4f, 0.2f, 0.1f))
        assertEquals(1f, r, 1e-4f)                   // its strongest channel keeps full brightness
        assertEquals(1f - FilmLight.STRENGTH / 2, g, 1e-4f)
        assertEquals(true, b < g)
    }

    @Test fun theAverageSkipsBlackAndWhite() {
        val red = (0xFF shl 24) or (200 shl 16) or (40 shl 8) or 40
        val c = app.lumiere.android.ui.ArtColour.average(intArrayOf(0xFF000000.toInt(), 0xFFFFFFFF.toInt(), red))!!
        assertEquals(200f / 255, c.r, 1e-3f)
        assertNull(app.lumiere.android.ui.ArtColour.average(intArrayOf(0xFF000000.toInt())))
    }
}

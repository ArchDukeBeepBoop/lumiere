package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TheaterGeometryTest {
    @Test fun aSizeIsAShareOfYourView() {
        val s = TheaterGeometry.room(1920, 1080)
        // Everyone starts at 45° across: at 3 m about 2.5 m wide, a big TV rather than a wall of picture.
        assertEquals(2.49f, s.widthM, 0.05f)
        assertEquals(5.5f, TheaterGeometry.room(1920, 1080, 4).widthM, 0.1f)
        assertEquals(s.widthM / (16f / 9f), s.heightM, 0.01f)
        assertTrue("larger sizes are wider", TheaterGeometry.room(1920, 1080, 4).widthM > s.widthM)
    }

    @Test fun aScopeFilmIsWideAndLow() {
        val scope = TheaterGeometry.room(1920, 804)
        val flat = TheaterGeometry.room(1920, 1080)
        assertEquals(flat.widthM, scope.widthM, 0.01f)
        assertTrue(scope.heightM < flat.heightM)
    }

    @Test fun aTallPictureNeverOutgrowsYourView() {
        val portrait = TheaterGeometry.room(1080, 1920, 4)
        assertTrue(portrait.heightM <= TheaterGeometry.span(TheaterGeometry.MAX_TALL_DEGREES, 3f) + 1e-3f)
        assertEquals(1080f / 1920f, portrait.widthM / portrait.heightM, 0.01f)
    }

    @Test fun theScreenIsLaidOutAtTheFilmsPixelsUpTo4K() {
        assertEquals(1920, TheaterGeometry.room(1920, 1080).pixelWidth)
        assertEquals(3840, TheaterGeometry.room(7680, 4320).pixelWidth)
    }

    @Test fun captionsSitUnderTheScreensFoot() {
        val s = TheaterGeometry.room(1920, 1080)
        val c = TheaterGeometry.captions(s)
        assertTrue(c.belowMiddleM > s.heightM / 2)
        assertTrue(c.widthM < s.widthM)
    }

    @Test fun nearerSeatsBringTheSameScreenCloser() {
        val mid = TheaterGeometry.room(1920, 1080, 1)
        val near = TheaterGeometry.seated(mid, 0)
        assertEquals(mid.widthM, near.widthM, 1e-4f)
        assertEquals(mid.distanceM * 0.75f, near.distanceM, 1e-4f)
        assertEquals(mid.distanceM, TheaterGeometry.seated(mid, 1).distanceM, 1e-4f)
    }
}

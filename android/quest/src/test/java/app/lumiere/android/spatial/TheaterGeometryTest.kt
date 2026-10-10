package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TheaterGeometryTest {
    private val wide = Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 804)
    private val tv = Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 1080)

    @Test fun eachSizeFillsItsShareOfYourViewInEveryPlace() {
        Stage.Place.entries.forEach { place ->
            TheaterGeometry.SIZE_DEGREES.forEachIndexed { i, degrees ->
                val s = TheaterGeometry.spec(tv, place, i, curved = false)
                assertEquals("$place size $i", degrees, TheaterGeometry.angleDegrees(s.widthM, s.distanceM), 0.05f)
                assertNull("flat", s.radiusM)
            }
        }
    }

    @Test fun theCinemaScreenIsACinemasAndTheRoomsATvs() {
        val cinema = TheaterGeometry.spec(tv, Stage.Place.CINEMA, 2, false)
        val room = TheaterGeometry.spec(tv, Stage.Place.ROOM, 2, false)
        assertTrue("cinema screen over 15 m: ${cinema.widthM}", cinema.widthM > 15f)
        assertTrue("room screen a big TV: ${room.widthM}", room.widthM in 3f..5f)
    }

    @Test fun theScreenTakesTheFilmsShape() {
        val s = TheaterGeometry.spec(wide, Stage.Place.CINEMA, 2, false)
        assertEquals(1920f / 804f, s.widthM / s.heightM, 0.01f)
        // A side-by-side 3D film's screen is one eye's shape.
        val sbs = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.SIDE_BY_SIDE, 3840, 1080), Stage.Place.VOID, 1, false)
        assertEquals(16f / 9f, sbs.widthM / sbs.heightM, 0.01f)
    }

    @Test fun curvedIsCentredOnYouAndKeepsTheSameAngle() {
        val s = TheaterGeometry.spec(tv, Stage.Place.CINEMA, 3, curved = true)
        assertEquals(s.distanceM, s.radiusM!!, 0f)
        assertEquals(78f, Math.toDegrees((s.widthM / s.radiusM!!).toDouble()).toFloat(), 0.05f)
    }

    @Test fun spheresAreSpheres() {
        val s = TheaterGeometry.spec(Theater.Request(Projection.SPHERE, StereoLayout.TOP_BOTTOM, 0, 0), Stage.Place.ROOM, 2, true)
        assertEquals(TheaterGeometry.SPHERE_RADIUS_M, s.distanceM, 0f)
        assertEquals(3840 to 3840, s.pixelWidth to s.pixelHeight)
    }

    @Test fun captionsSitOverTheScreensFootAtItsScale() {
        val s = TheaterGeometry.spec(wide, Stage.Place.CINEMA, 2, false)
        val (w, h, up, ahead) = TheaterGeometry.captions(s).toList()
        assertTrue(w < s.widthM && h < s.heightM / 2)
        assertTrue("inside the screen's lower half", up - h / 2 >= -s.heightM / 2 && up < 0f)
        assertTrue("just in front", ahead in 0.01f..0.1f)
    }
}

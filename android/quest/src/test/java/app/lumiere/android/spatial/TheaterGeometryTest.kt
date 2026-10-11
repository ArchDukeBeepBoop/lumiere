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

    @Test fun theCinemaIsOneImaxWallAndASizeIsYourSeat() {
        val seats = (0 until Stage.SCREEN_SIZES).map { TheaterGeometry.spec(tv, Stage.Place.CINEMA, it, false) }
        seats.forEach { assertEquals("one wall", TheaterGeometry.CINEMA_SCREEN_WIDTH_M, it.widthM, 1e-3f) }
        assertTrue("larger sits nearer", seats.zipWithNext().all { (a, b) -> b.distanceM < a.distanceM })
        val start = TheaterGeometry.spec(tv, Stage.Place.CINEMA, TheaterGeometry.DEFAULT_SIZE, false)
        assertTrue("the start fills your view: ${TheaterGeometry.angleDegrees(start.widthM, start.distanceM)}°",
            TheaterGeometry.angleDegrees(start.widthM, start.distanceM) >= 80f)
        val room = TheaterGeometry.spec(tv, Stage.Place.ROOM, 0, false)
        assertTrue("your room's smallest is still a big TV: ${room.widthM}", room.widthM in 2.5f..4f)
    }

    @Test fun theCabinIsAWallScreenAndASizeIsYourSeat() {
        val seats = (0 until Stage.SCREEN_SIZES).map { TheaterGeometry.spec(tv, Stage.Place.CABIN, it, false) }
        seats.forEach {
            assertEquals("one wall screen", TheaterGeometry.CABIN_SCREEN_WIDTH_M, it.widthM, 1e-3f)
            assertEquals("its middle a little above your eyes", 0.2f, it.aboveEyesM, 0f)
        }
        assertTrue("larger sits nearer", seats.zipWithNext().all { (a, b) -> b.distanceM < a.distanceM })
        assertTrue("the nearest seat still has room before the screen: ${seats.last().distanceM}", seats.last().distanceM > 1.7f)
        assertTrue("the farthest is still in a room: ${seats.first().distanceM}", seats.first().distanceM < 5.5f)
        assertTrue("its screen stays on its wall", TheaterGeometry.fixedScreen(Stage.Place.CABIN))
    }

    @Test fun theLakesScreenFloatsOverTheWaterAndGrows() {
        val sizes = (0 until Stage.SCREEN_SIZES).map { TheaterGeometry.spec(tv, Stage.Place.LAKE, it, false) }
        sizes.forEach {
            assertEquals("over the water", 14f, it.distanceM, 0f)
            assertEquals("well above your eyes", 0.9f, it.aboveEyesM, 0f)
        }
        assertTrue("each size larger", sizes.zipWithNext().all { (a, b) -> b.widthM > a.widthM })
        assertTrue("yours to carry, as in the dark and space", !TheaterGeometry.fixedScreen(Stage.Place.LAKE))
        assertEquals(listOf(Stage.Place.CINEMA, Stage.Place.CABIN, Stage.Place.STATION), Stage.Place.entries.filter { TheaterGeometry.fixedScreen(it) })
    }

    @Test fun theLineToTheScreensFootIsSteeperForACurve() {
        val flat = TheaterGeometry.spec(tv, Stage.Place.LAKE, 2, false)
        assertEquals((flat.heightM / 2 - flat.aboveEyesM) / flat.distanceM, TheaterGeometry.footSlope(flat), 1e-5f)
        val curved = TheaterGeometry.spec(tv, Stage.Place.LAKE, 2, true)
        assertTrue("the curve's ends come nearer", TheaterGeometry.footSlope(curved) > (curved.heightM / 2 - curved.aboveEyesM) / curved.distanceM)
        val sphere = TheaterGeometry.spec(Theater.Request(Projection.SPHERE, StereoLayout.MONO, 0, 0), Stage.Place.LAKE, 2, false)
        assertEquals(0f, TheaterGeometry.footSlope(sphere), 0f)
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
        assertEquals(TheaterGeometry.SIZE_DEGREES[3], Math.toDegrees((s.widthM / s.radiusM!!).toDouble()).toFloat(), 0.05f)
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

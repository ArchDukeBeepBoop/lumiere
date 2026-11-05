package app.lumiere.android.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlacesTest {
    @Test fun theCinemasScreenIsItsOwnFromTheBackRowAtThePicturesDepth() {
        val s = Place.CINEMA.screen(1920, 1080, size = 4)
        // 20 m across at 19 m, six times further and larger; Screen Size doesn't change it.
        assertEquals(20f * Place.FAR, s.widthM, 0.01f)
        assertEquals(19.02f * Place.FAR, s.distanceM, 0.01f)
        assertEquals(s.widthM, Place.CINEMA.screen(1920, 1080, size = 0).widthM, 0.01f)
    }

    @Test fun aFilmFitsInsideARoomsScreenKeepingItsShape() {
        val scope = Place.CABIN.screen(1920, 804, 1)
        assertEquals(5.5f * Place.FAR, scope.widthM, 0.01f)
        assertEquals(1920f / 804f, scope.widthM / scope.heightM, 0.01f)
        val tall = Place.CABIN.screen(1440, 1080, 1)
        assertEquals(5.5f * 9f / 16f * Place.FAR, tall.heightM, 0.01f)
    }

    @Test fun outdoorsTheScreenIsYourSizeAtThePlacesDistance() {
        val lake = Place.LAKE.screen(1920, 1080, size = 1)
        val share = TheaterGeometry.span(TheaterGeometry.SIZE_DEGREES[1], 14f) * Place.FAR
        assertEquals(share, lake.widthM, 0.01f)
        assertTrue("larger sizes are wider", Place.LAKE.screen(1920, 1080, 3).widthM > lake.widthM)
    }

    @Test fun yourRoomIsAsBeforeAndHasNoPicture() {
        assertTrue(Place.ROOM.passthrough)
        assertNull(Place.ROOM.pictureFor(film = true))
        assertEquals(TheaterGeometry.room(1920, 1080, 1).widthM, Place.ROOM.screen(1920, 1080, 1).widthM, 0.01f)
    }

    @Test fun theLightsGoDownForAFilm() {
        assertEquals(app.lumiere.android.R.drawable.pano_lake_dark, Place.LAKE.pictureFor(true)!!.first)
        assertEquals(app.lumiere.android.R.drawable.pano_cinema_s0_dark to 1f, Place.CINEMA.pictureFor(true))
        assertEquals(1f, Place.CINEMA.pictureFor(false)!!.second, 1e-4f)
    }

    @Test fun anUnknownNameIsYourRoom() = assertEquals(Place.ROOM, Place.named("PALACE"))

    @Test fun theWindowsWhereToWatchOffersTheTheatersPlaces() =
        assertEquals(Place.entries.map { it.name to it.label }, app.lumiere.android.QuestPlaces.all)
}

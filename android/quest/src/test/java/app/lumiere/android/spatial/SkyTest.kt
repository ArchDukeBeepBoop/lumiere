package app.lumiere.android.spatial

import app.lumiere.android.Stage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The sky's picture by place: stars in space, the lake at the lakeside and through the cabin's windows, none indoors or in the dark. */
class SkyTest {
    @Test fun eachPlaceHasItsOwnSky() {
        assertEquals(R.drawable.lumiere_starfield, Sky.pictureFor(Stage.Place.SPACE))
        assertEquals(R.drawable.lumiere_lakeside, Sky.pictureFor(Stage.Place.LAKE))
        assertEquals("the cabin's windows look out on the lake", R.drawable.lumiere_lakeside, Sky.pictureFor(Stage.Place.CABIN))
        listOf(Stage.Place.ROOM, Stage.Place.CINEMA, Stage.Place.VOID).forEach { assertNull("$it", Sky.pictureFor(it)) }
    }
}

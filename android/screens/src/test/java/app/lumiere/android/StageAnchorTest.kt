package app.lumiere.android

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The anchored screen's spot survives being saved as text, and damage reads as no anchor. */
class StageAnchorTest {
    @Test fun aSavedSpotComesBackTheSame() {
        val spot = floatArrayOf(0.4f, 1.3f, 1.4f, 0.92f, 0f, 0.38f, 0f)
        assertArrayEquals(spot, Stage.anchorFrom(spot.joinToString(",")), 0f)
    }

    @Test fun nothingOrDamageIsNoAnchor() {
        assertNull(Stage.anchorFrom(null))
        assertNull(Stage.anchorFrom(""))
        assertNull(Stage.anchorFrom("1,2,3"))
        assertNull(Stage.anchorFrom("1,2,3,NaN,0,0,0"))
    }
}

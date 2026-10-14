package app.lumiere.android

import app.lumiere.android.ui.CalmScroll
import app.lumiere.android.ui.Pointing
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The page moves for the remote only as far as it must, and never for a
 * pointer: on a Quest, a ray passing over a half-hidden card used to pull
 * the whole page under it.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
class CalmScrollTest {
    @After fun keys() { Pointing.byPointer = false }

    @Test fun onScreenNothingMoves() {
        assertEquals(0f, CalmScroll.calculateScrollDistance(100f, 200f, 1000f))
    }

    @Test fun theKeysBringWhatIsChosenJustIntoView() {
        Pointing.byPointer = false
        assertEquals(100f, CalmScroll.calculateScrollDistance(900f, 200f, 1000f))
        assertEquals(-50f, CalmScroll.calculateScrollDistance(-50f, 200f, 1000f))
    }

    @Test fun pointingNeverPullsThePage() {
        Pointing.byPointer = true
        assertEquals(0f, CalmScroll.calculateScrollDistance(900f, 200f, 1000f))
        assertEquals(0f, CalmScroll.calculateScrollDistance(-50f, 200f, 1000f))
    }
}

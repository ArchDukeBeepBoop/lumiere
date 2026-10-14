package app.lumiere.android.spatial

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sitting down or standing up moves the place to you; a lean or a stretch doesn't. */
class PostureTest {
    @Test fun aNewPostureHeldAMomentMovesThePlace() {
        val p = Posture()
        // Standing (eyes 1.65) after being seated at 1.2: not at once, but after a couple of seconds.
        assertFalse(p.moved(1.65f, 1.2f, 0))
        assertFalse(p.moved(1.65f, 1.2f, 2_000))
        assertTrue(p.moved(1.65f, 1.2f, 2_600))
        // Once: then it's the new seat's business.
        assertFalse(p.moved(1.65f, 1.2f, 2_700))
    }

    @Test fun aLeanOrAStretchDoesnt() {
        val p = Posture()
        assertFalse(p.moved(1.0f, 1.2f, 0))          // leaning forward 20 cm: under the threshold
        assertFalse(p.moved(1.55f, 1.2f, 100))       // a stretch up...
        assertFalse(p.moved(1.25f, 1.2f, 1_500))     // ...and back before it settles
        assertFalse(p.moved(1.55f, 1.2f, 2_000))     // the clock starts again
        assertFalse(p.moved(1.55f, 1.2f, 4_000))
        assertTrue(p.moved(1.55f, 1.2f, 4_600))
    }

    @Test fun sittingDownToo() {
        val p = Posture()
        assertFalse(p.moved(1.15f, 1.6f, 0))
        assertTrue(p.moved(1.15f, 1.6f, Posture.SETTLE_MS))
    }
}

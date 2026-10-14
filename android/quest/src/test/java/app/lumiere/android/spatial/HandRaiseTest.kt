package app.lumiere.android.spatial

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Raise a hand and look at it for the menu; pointing, pinching or a glance doesn't call it. */
class HandRaiseTest {
    private val eye = floatArrayOf(0f, 1.2f, 0f)
    private val level = floatArrayOf(0f, 0f, 1f)
    private val atHand = floatArrayOf(0f, -0.2f, 1f).let { val l = kotlin.math.sqrt(1.04f); floatArrayOf(0f, -0.2f / l, 1f / l) }
    private val raised = floatArrayOf(0f, 1.12f, 0.4f)

    @Test fun aRaisedHandHeldStillCallsTheMenu() {
        val h = HandRaise()
        assertFalse(h.update(eye, atHand, raised, 0))
        assertFalse(h.update(eye, atHand, raised, 300))
        assertTrue(h.update(eye, atHand, raised, 700))
    }

    @Test fun aMovingHandDoesnt() {
        val h = HandRaise()
        var t = 0L
        for (i in 0 until 20) {
            val moving = floatArrayOf(0.05f * (i % 2), 1.12f, 0.4f)
            assertFalse(h.update(eye, atHand, moving, t)); t += 100
        }
    }

    @Test fun aHandLowOrAsideOrAControllerDoesnt() {
        val h = HandRaise()
        // Pointing at the handset: the hand well below your eyes.
        assertFalse(h.raised(eye, floatArrayOf(0f, -0.5f, 0.86f), floatArrayOf(0f, 0.75f, 0.45f)))
        // Out at the side of your view.
        assertFalse(h.raised(eye, level, floatArrayOf(0.35f, 1.15f, 0.3f)))
        // Too far: arm's length, reaching for something.
        assertFalse(h.raised(eye, level, floatArrayOf(0f, 1.2f, 0.7f)))
        // No hand tracked (controllers in hand).
        assertFalse(h.update(eye, atHand, null, 0)); assertFalse(h.update(eye, atHand, null, 2000))
    }

    @Test fun itStaysWhileInUseAndGoesAMomentAfterTheHandDrops() {
        val h = HandRaise()
        h.update(eye, atHand, raised, 0); h.update(eye, atHand, raised, 700)
        assertTrue(h.shown)
        // The hand drops, but you've just pressed a button: it stays.
        assertTrue(h.update(eye, level, null, 1_000, touchedAt = 900))
        assertTrue(h.update(eye, level, null, 3_000, touchedAt = 900))
        // Then a moment after: gone.
        assertTrue(h.update(eye, level, null, 3_500, touchedAt = 900))
        assertFalse(h.update(eye, level, null, 4_600, touchedAt = 900))
    }
}

package app.lumiere.android.spatial

import kotlin.math.acos
import kotlin.math.sqrt

/**
 * When the hand menu comes and goes: raise a hand (not a controller) into
 * the middle of your view, near, at least shoulder high, and hold it still a
 * moment while you look at it — and the menu appears by it; drop the hand
 * or look away and, a moment later (not while you're using the menu), it
 * goes. Still and raised, so pointing at the handset or pinching to click
 * doesn't call it. Pure: the Director gives it your eyes, your gaze and the
 * hand each look.
 */
class HandRaise {
    private var since = 0L
    private var steadyAt: FloatArray? = null
    private var awaySince = 0L
    var shown = false
        private set

    /**
     * Your [eye] and [gaze] (unit), and the [hand] (null when no hand is
     * tracked); whether you [touched] the menu just now. True while it shows.
     */
    fun update(eye: FloatArray, gaze: FloatArray, hand: FloatArray?, now: Long, touchedAt: Long = Long.MIN_VALUE / 2): Boolean {
        if (!shown) {
            if (hand == null || !raised(eye, gaze, hand)) { since = 0L; steadyAt = null; return false }
            val first = steadyAt
            if (first == null || dist(first, hand) > STILL_M) { steadyAt = hand.copyOf(); since = now; return false }
            if (now - since < DWELL_MS) return false
            shown = true; awaySince = 0L
            return true
        }
        val near = hand != null && dist(eye, hand) < LEAVE_M && angle(gaze, sub(hand, eye)) < LEAVE_DEGREES
        if (near || now - touchedAt < KEEP_AFTER_TOUCH_MS) { awaySince = 0L; return true }
        if (awaySince == 0L) awaySince = now
        if (now - awaySince < HIDE_MS) return true
        shown = false; since = 0L; steadyAt = null
        return false
    }

    /** A hand held up where you're looking, near: the pose that calls the menu. */
    fun raised(eye: FloatArray, gaze: FloatArray, hand: FloatArray): Boolean {
        val d = dist(eye, hand)
        val pitch = Math.toDegrees(kotlin.math.asin(gaze[1].coerceIn(-1f, 1f).toDouble())).toFloat()
        return d in NEAR_M..FAR_M && angle(gaze, sub(hand, eye)) < CALL_DEGREES &&
            hand[1] >= eye[1] - BELOW_EYES_M && pitch >= MIN_PITCH_DEGREES
    }

    companion object {
        const val NEAR_M = 0.2f
        const val FAR_M = 0.55f
        const val CALL_DEGREES = 20f
        const val BELOW_EYES_M = 0.32f
        const val MIN_PITCH_DEGREES = -25f
        const val STILL_M = 0.04f
        const val DWELL_MS = 600L
        const val LEAVE_M = 0.75f
        const val LEAVE_DEGREES = 40f
        const val HIDE_MS = 1_000L
        const val KEEP_AFTER_TOUCH_MS = 2_500L

        private fun sub(a: FloatArray, b: FloatArray) = floatArrayOf(a[0] - b[0], a[1] - b[1], a[2] - b[2])
        private fun dist(a: FloatArray, b: FloatArray) = sub(a, b).let { sqrt(it[0] * it[0] + it[1] * it[1] + it[2] * it[2]) }
        private fun angle(a: FloatArray, b: FloatArray): Float {
            val la = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); val lb = sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2])
            if (la < 1e-5f || lb < 1e-5f) return 180f
            return Math.toDegrees(acos(((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (la * lb)).coerceIn(-1f, 1f).toDouble())).toFloat()
        }
    }
}

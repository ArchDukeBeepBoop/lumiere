package app.lumiere.android.spatial

import kotlin.math.abs

/**
 * Whether you've sat down or stood up since you were seated: your eyes
 * [THRESHOLD_M] or more from the seat's height, and staying there for
 * [SETTLE_MS]. A lean, a stretch or picking something up from the floor
 * doesn't move the place; a new posture does, and the place (the hall, the
 * screen) comes to your new height. Pure; the Director asks at each look.
 */
class Posture {
    private var awaySince: Long? = null

    /** True once, when eyes at [eyeY] have been away from the seat's [seatEyeY] long enough to be a new posture. */
    fun moved(eyeY: Float, seatEyeY: Float, now: Long): Boolean {
        if (abs(eyeY - seatEyeY) < THRESHOLD_M) { awaySince = null; return false }
        val since = awaySince ?: now.also { awaySince = it }
        if (now - since < SETTLE_MS) return false
        awaySince = null
        return true
    }

    companion object {
        const val THRESHOLD_M = 0.3f
        const val SETTLE_MS = 2_500L
    }
}

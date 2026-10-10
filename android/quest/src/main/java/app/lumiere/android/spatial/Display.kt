package app.lumiere.android.spatial

/**
 * The display rate a film looks smoothest at on a Quest, which runs at 72,
 * 90 or 120 Hz: each frame shown a whole number of times, so a pan across a
 * 24-frame film doesn't stutter. 0 when no rate fits (25 fps) or the rate
 * isn't known yet: the headset keeps its own.
 */
object Display {
    fun rateFor(fps: Float): Float = when {
        fps <= 0f -> 0f
        fps in 23.5f..24.5f -> 72f
        fps in 29.5f..30.5f -> 90f
        fps in 59.5f..60.5f -> 120f
        else -> 0f
    }

    /**
     * Where [look] points (a unit vector) asks for a tilted screen: looking up
     * more than about 30°, as you do lying down, the screen goes where you look.
     */
    fun lookingUp(lookY: Float): Boolean = lookY > 0.5f
}

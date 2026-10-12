package app.lumiere.android.spatial

import kotlin.math.tan

/**
 * The space station as built (Scripts/env/station.py): a module round its
 * screen, 4 m across on the forward bulkhead, its middle [SCREEN_MIDDLE] off
 * the deck; the five sizes are how near you float (3.8 m to 1.3 m), the
 * module staying where it is. Pure, so it's tested without a headset.
 */
object StationRoom {
    const val SCREEN_W = 4.0f
    const val SCREEN_H = SCREEN_W * 9f / 16f
    const val SCREEN_MIDDLE = 1.5f

    fun distance(size: Int): Float {
        val degrees = TheaterGeometry.SIZE_DEGREES[size.coerceIn(0, TheaterGeometry.SIZE_DEGREES.lastIndex)]
        return SCREEN_W / (2 * tan(Math.toRadians(degrees / 2.0)).toFloat())
    }

    fun aboveEyes(eyeY: Float): Float = SCREEN_MIDDLE - eyeY

    fun picture(aspect: Float): Pair<Float, Float> = if (aspect >= SCREEN_W / SCREEN_H) SCREEN_W to SCREEN_W / aspect else SCREEN_H * aspect to SCREEN_H

    fun origin(size: Int): FloatArray = floatArrayOf(0f, 0f, distance(size))
}

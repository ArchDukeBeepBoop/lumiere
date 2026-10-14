package app.lumiere.android.spatial

import kotlin.math.tan

/**
 * The cabin as built (Scripts/env/cabin.py, which writes cabin.json beside
 * its models): a timber great room round its screen, 5.5 m across on the
 * batten wall, its middle [SCREEN_MIDDLE] off the floor; the five sizes are
 * how near the sofa is (from 5.3 m to 1.75 m), so the sofa and its tables
 * are a model of their own that comes with you. The room's floor is yours.
 * A film fills the screen's width, or (narrower than 16:9) its height.
 * Pure, so it's tested without a headset.
 */
object CabinRoom {
    const val SCREEN_W = 5.5f
    const val SCREEN_H = SCREEN_W * 9f / 16f
    const val SCREEN_MIDDLE = 1.72f
    const val SCREEN_BOTTOM = SCREEN_MIDDLE - SCREEN_H / 2
    /** The sofa's coffee table: its far edge ahead of you, and its top. */
    const val TABLE_FRONT = 1.05f
    const val TABLE_TOP = 0.41f

    /** How far the sofa is from the screen at [size]: the screen fills that size's share of your view. */
    fun distance(size: Int): Float {
        val degrees = TheaterGeometry.SIZE_DEGREES[size.coerceIn(0, TheaterGeometry.SIZE_DEGREES.lastIndex)]
        return SCREEN_W / (2 * tan(Math.toRadians(degrees / 2.0)).toFloat())
    }

    fun aboveEyes(eyeY: Float): Float = SCREEN_MIDDLE - eyeY

    fun picture(aspect: Float): Pair<Float, Float> = if (aspect >= SCREEN_W / SCREEN_H) SCREEN_W to SCREEN_W / aspect else SCREEN_H * aspect to SCREEN_H

    /** The room's origin (the floor under the screen's middle) from the floor under your eyes. */
    fun origin(size: Int): FloatArray = floatArrayOf(0f, 0f, distance(size))
}

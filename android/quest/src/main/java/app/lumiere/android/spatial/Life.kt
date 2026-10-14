package app.lumiere.android.spatial

import kotlin.math.cos
import kotlin.math.sin

/**
 * What moves in a place, so it feels lived in rather than built: flames
 * that rise, fall and gutter (the cabin's fire, its candles, the
 * pontoon's lanterns) and fireflies drifting over the water, each glowing
 * a moment and going dark. Small offsets from a part's home, worked out
 * from the time alone, so every frame is cheap and nothing accumulates;
 * pure, so it's tested without a headset. With Motion.reduced nothing
 * moves (the Director doesn't ask).
 */
object Life {
    /** Where a part is now, from its home, and whether it's showing. */
    data class Sway(val dx: Float, val dy: Float, val dz: Float, val lit: Boolean)

    /**
     * Flame [i] at [t] seconds: it lifts and settles a centimetre or two at
     * a few rates at once; every third burns steadily (the body of the
     * fire), the rest are tongues that now and then go out for a moment.
     */
    fun flame(i: Int, t: Float): Sway {
        val k = i * 1.93f
        val dy = 0.012f * sin(t * 7.3f + k) + 0.007f * sin(t * 13.1f + k * 0.7f) + 0.004f * sin(t * 23.7f + k * 1.3f)
        val dx = 0.004f * sin(t * 5.1f + k * 2.1f)
        val lit = i % 3 == 0 || sin(t * 9.7f + k * 2.3f) + 0.8f * sin(t * 4.1f + k) > -0.9f
        return Sway(dx, dy, 0f, lit)
    }

    /**
     * Firefly [i] at [t] seconds: a slow wander up to about half a metre
     * from its home, never the same path twice running, and a glow of a
     * second or so every few seconds, each on its own beat.
     */
    fun firefly(i: Int, t: Float): Sway {
        val k = i * 1.37f
        val dx = 0.42f * sin(0.21f * t + k * 1.7f) + 0.18f * sin(0.53f * t + k * 0.6f)
        val dy = 0.16f * sin(0.29f * t + k * 2.1f) + 0.05f * sin(1.1f * t + k)
        val dz = 0.42f * cos(0.17f * t + k * 0.9f) + 0.18f * sin(0.47f * t + k * 1.3f)
        val period = 3.5f + (i % 5) * 0.7f
        val phase = ((t + k) % period + period) % period / period
        return Sway(dx, dy, dz, phase < GLOW_SHARE)
    }

    /** The share of its beat a firefly glows for. */
    const val GLOW_SHARE = 0.24f

    /** A light that blinks every [period] seconds, on for [share] of it (a beacon, a status light), from [phase] in. */
    fun blink(t: Float, period: Float, share: Float, phase: Float = 0f): Sway {
        val at = ((t + phase) % period + period) % period / period
        return Sway(0f, 0f, 0f, at < share)
    }

    /**
     * Something floating free in a space station, [i] at [t] seconds: a slow
     * drift of a few centimetres each way, as if nudged long ago and never
     * quite still. Always showing.
     */
    fun drift(i: Int, t: Float): Sway {
        val k = i * 2.11f
        return Sway(
            0.05f * sin(0.13f * t + k) + 0.02f * sin(0.41f * t + k * 1.7f),
            0.06f * sin(0.11f * t + k * 0.6f) + 0.02f * sin(0.37f * t + k),
            0.05f * cos(0.09f * t + k * 1.3f) + 0.02f * sin(0.33f * t + k * 0.4f),
            true,
        )
    }
}

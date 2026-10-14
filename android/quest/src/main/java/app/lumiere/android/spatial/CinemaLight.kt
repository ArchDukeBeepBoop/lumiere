package app.lumiere.android.spatial

/**
 * The room's light while a film plays, as numbers: how bright passthrough
 * is, and how much of the film's own colour falls on it, like the spill from
 * a cinema screen. Pure, so it's tested without a headset.
 */
object CinemaLight {
    /** Brightness of the room: playing, paused, and anywhere else. */
    const val PLAYING = 0.12f
    const val PAUSED = 0.45f
    const val LIT = 1f
    /** How much of the film's colour reaches the room at most, while it's dark. */
    const val SPILL = 0.07f
    /** The cinema's pace: going down for a film over about four seconds, coming up over two. */
    const val HALL_DOWN = 25f
    const val HALL_UP = 12f

    /** A step from colour [now] toward [target], a little each tick, so the film's light glides rather than jumps. */
    fun easeTint(now: Triple<Float, Float, Float>?, target: Triple<Float, Float, Float>?): Triple<Float, Float, Float>? {
        if (target == null || now == null) return target
        fun step(a: Float, b: Float) = (a + (b - a) * 0.12f).let { if (kotlin.math.abs(b - it) < 0.004f) b else it }
        return Triple(step(now.first, target.first), step(now.second, target.second), step(now.third, target.third))
    }

    fun target(inPlayer: Boolean, playing: Boolean): Float = when {
        inPlayer && playing -> PLAYING
        inPlayer -> PAUSED
        else -> LIT
    }

    /**
     * A step from [now] toward [target], [slowness] steps' worth each tick: a
     * sixth of the way (about a second and a half to settle), or slower for a
     * cinema's house lights, which go down at their own unhurried pace.
     */
    fun ease(now: Float, target: Float, slowness: Float = 6f): Float {
        val next = now + (target - now) / slowness
        return if (kotlin.math.abs(target - next) < 0.005f) target else next
    }

    /**
     * One channel of the passthrough table: [level] (0..15, the table's grid)
     * dimmed to [brightness], plus [tint] (0..1) of the film's colour in
     * proportion to how dark the room has become. 0..255 out.
     */
    fun channel(level: Int, brightness: Float, tint: Float): Int {
        val dark = 1f - brightness
        val v = level * 17f * brightness + tint * 255f * SPILL * dark
        return v.toInt().coerceIn(0, 255)
    }
}

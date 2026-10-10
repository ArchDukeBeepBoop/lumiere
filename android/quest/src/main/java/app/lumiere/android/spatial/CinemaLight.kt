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

    fun target(inPlayer: Boolean, playing: Boolean): Float = when {
        inPlayer && playing -> PLAYING
        inPlayer -> PAUSED
        else -> LIT
    }

    /** A step from [now] toward [target], a sixth of the way each tick: about a second and a half to settle. */
    fun ease(now: Float, target: Float): Float {
        val next = now + (target - now) / 6f
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

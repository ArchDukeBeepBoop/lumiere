package app.lumiere.android.spatial

import kotlin.math.abs

/**
 * The cinema's front curtain: strips of velvet either side that draw
 * across the screen and gather back beyond its edges, as a picture
 * palace's tabs do. [closed] is how far across they are (0 gathered open,
 * 1 meeting in the middle); each strip's place either way follows from its
 * own open place in the hall (Auditorium), so this needs nothing else.
 * Pure, so it's tested without a headset.
 */
object FrontCurtain {
    /** 0 open, 1 drawn across the screen. */
    @Volatile var closed = 0f
    /** Where it's going. */
    @Volatile var target = 0f

    /** Quick to draw across; slow and stately to open, as the house lights go down. */
    const val CLOSE_S = 1.2f
    const val OPEN_S = 5f
    /** After a film, how long it stays drawn before opening on the big screen's title again. */
    const val HOLD_MS = 6_000L

    /** [dt] seconds on toward [target]. */
    fun step(dt: Float) {
        val c = closed
        closed = if (target > c) (c + dt / CLOSE_S).coerceAtMost(target) else (c - dt / OPEN_S).coerceAtLeast(target)
    }

    /**
     * Where it should be: drawn across as a film is coming (you've pressed
     * Play and the picture isn't here yet), opening as it begins, drawn
     * again for a few seconds after it ends — then open on the title you
     * choose next. Open whenever a film is on, whatever else.
     */
    fun targetFor(coming: Boolean, on: Boolean, sinceEndMs: Long): Float = when {
        on -> 0f
        coming -> 1f
        sinceEndMs in 0 until HOLD_MS -> 1f
        else -> 0f
    }

    /** Where strip [b] is now, from where it hangs open. */
    fun sway(b: Block<Auditorium.Kind>): Life.Sway = Life.Sway(closed * travel(b), 0f, 0f, true)

    /** How far strip [b] moves across to close: from gathered beyond the screen's edge to its place in the drawn curtain. */
    fun travel(b: Block<Auditorium.Kind>): Float {
        val n = Auditorium.TAB_STRIPS
        val side = if (b.x >= 0f) 1f else -1f
        val halfScreen = n * b.w - Auditorium.TAB_OVERLAP
        val k = (abs(b.x) - halfScreen - Auditorium.TAB_CLEAR - b.w / 2) * n / Auditorium.TAB_GATHER
        val closedX = side * (-Auditorium.TAB_OVERLAP + b.w * (k + 0.5f))
        return closedX - b.x
    }
}

package app.lumiere.android.spatial

import app.lumiere.android.player.Theater

/**
 * The Theater held steady through the moments a film has no picture yet.
 * The player only asks for a screen once it knows the picture's size, a
 * second or three after you press Play, and the next episode starts with no
 * size at all; the Theater came down and went up again each time, and the
 * window flashed in front of the cinema's screen. Now:
 *
 * - between pictures (the next episode, a reload) the last screen is kept
 *   for [graceMs] while the player is still up, so it never comes down;
 * - a film starting away from your room keeps the window aside from the
 *   moment you press Play, with the big screen showing the title, for up
 *   to [startMs] — after that the window comes back, so a film that can't
 *   start can still say why.
 *
 * Pure, so it's tested without a headset.
 */
class TheaterHold(private val graceMs: Long = GRACE_MS, private val startMs: Long = START_MS) {
    private var held: Theater.Request? = null
    private var heldAt = 0L
    private var startedAt: Long? = null

    /** The screen to show: the player's own [live] request, or the last one for a moment after it goes. */
    fun request(live: Theater.Request?, inPlayer: Boolean, now: Long): Theater.Request? {
        if (live != null) { held = live; heldAt = now; return live }
        if (inPlayer && held != null && now - heldAt < graceMs) return held
        held = null
        return null
    }

    /**
     * True while a film is starting ([starting]: the player is up and has
     * taken the Theater's controls) but has no screen yet ([on] false).
     */
    fun waiting(starting: Boolean, on: Boolean, now: Long): Boolean {
        // Up, or no film: the next wait (the next episode) is timed afresh.
        if (!starting || on) { startedAt = null; return false }
        val since = startedAt ?: now.also { startedAt = it }
        return now - since < startMs
    }

    companion object {
        const val GRACE_MS = 6_000L
        const val START_MS = 10_000L
    }
}

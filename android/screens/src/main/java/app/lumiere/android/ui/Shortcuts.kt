package app.lumiere.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * The Theater's pinned shortcuts, NEX Player's "first layer": the buttons
 * you choose to keep on the transport beside play and the ten-second jumps.
 * Everything else waits under More. The choice is an ordered list of
 * stable ids, saved with the [app.lumiere.android.Stage]'s other settings;
 * an id a later version adds, and this one doesn't know, is passed over.
 */
object Shortcuts {
    /** Every action the transport can carry. The ids are saved: never change one, only add. */
    enum class Action(val id: String) {
        TRACKS("tracks"), SMALLER("smaller"), LARGER("larger"), CURVE("curve"), PLACE("place"),
        PLAYER_MENU("menu"), SLEEP("sleep"), BRING_HERE("here"), SPEED("speed"), SOUNDS("sounds"), WALL("wall");

        companion object { fun of(id: String): Action? = entries.firstOrNull { it.id == id } }
    }

    /** As many as the bar holds beside its own buttons, and stays easy to aim at. */
    const val MAX_PINNED = 6

    /** What you start with: the buttons the bar had before you could choose. */
    val DEFAULTS = listOf(Action.TRACKS, Action.SMALLER, Action.LARGER, Action.PLACE)

    /** Playback speeds, in the order each press steps through them. */
    val SPEEDS = floatArrayOf(1f, 1.25f, 1.5f, 0.75f)

    fun encode(pins: List<Action>): String = pins.joinToString(",") { it.id }

    /**
     * The saved list back: [DEFAULTS] if nothing was ever saved, nothing if
     * you unpinned everything; unknown ids and repeats dropped, at most
     * [MAX_PINNED], in your order.
     */
    fun decode(saved: String?): List<Action> = if (saved == null) DEFAULTS
        else saved.split(',').mapNotNull { Action.of(it.trim()) }.distinct().take(MAX_PINNED)

    /** [action] pinned to the end of [pins], or unpinned; null when it would be one too many. */
    fun toggled(pins: List<Action>, action: Action): List<Action>? = when {
        action in pins -> pins - action
        pins.size >= MAX_PINNED -> null
        else -> pins + action
    }

    /** The speed after [current]: round the steps, or back to normal from one they don't hold (the window's 2×). */
    fun nextSpeed(current: Float): Float {
        val at = SPEEDS.indexOfFirst { kotlin.math.abs(it - current) < 0.01f }
        return if (at < 0) 1f else SPEEDS[(at + 1) % SPEEDS.size]
    }

    /** 1×, 1.25×, 0.75×: as the speed reads on a remote's menu. */
    fun speedLabel(speed: Float): String {
        val hundredths = Math.round(speed * 100)
        val whole = hundredths / 100; val part = hundredths % 100
        return when {
            part == 0 -> "$whole×"
            part % 10 == 0 -> "$whole.${part / 10}×"
            else -> "$whole.${part.toString().padStart(2, '0')}×"
        }
    }

    /** Your pins, in the order they sit on the bar. */
    var pinned by mutableStateOf(DEFAULTS)
        private set

    private var prefs: android.content.SharedPreferences? = null

    /** From the Stage's preferences, as it loads its own. */
    fun load(p: android.content.SharedPreferences) {
        prefs = p
        pinned = decode(runCatching { p.getString(KEY, null) }.getOrNull())
    }

    /** Pins or unpins [action]; false, and nothing changes, when the bar is already full. */
    fun toggle(action: Action): Boolean {
        val next = toggled(pinned, action) ?: return false
        pinned = next
        prefs?.edit()?.putString(KEY, encode(next))?.apply()
        return true
    }

    private const val KEY = "shortcuts"
}

package app.lumiere.android

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Where you are on a Quest, and how films are watched, as the tab bar and
 * the Theater's transport set it: where (your room, a cinema, or a black
 * void — browsing as well as watching), how big
 * the screen is (five sizes by how much of your view it fills), and whether
 * it curves round you. Remembered between visits. The headset's own module
 * builds it.
 */
object Stage {
    /** Where a film plays: your room, dimmed; a cinema round you; or black, for the deepest contrast. */
    enum class Place(val label: String) { ROOM("your room"), CINEMA("the cinema"), VOID("the dark"), SPACE("space") }

    var place by mutableStateOf(Place.CINEMA)
        private set
    /** 0 smallest … [SCREEN_SIZES] - 1 largest; each a wider share of your view. */
    var screenSize by mutableIntStateOf(2)
        private set
    /** The size everyone starts at (the middle of five: 85° across, as the headset's module sets out). */
    private const val DEFAULT_SIZE = 2
    /** The film's screen curved round you, or flat as most cinemas' are. */
    var curved by mutableStateOf(false)
        private set
    /** When the sleep timer ends, in milliseconds since 1970; 0 when it's off. */
    var sleepAt by mutableStateOf(0L)
        private set
    /** Minutes the timer was set for, for its label; 0 off. */
    var sleepMinutes by mutableIntStateOf(0)
        private set
    val SLEEP_STEPS = intArrayOf(0, 15, 30, 60, 90)

    /** The next step: off, 15, 30, 60, 90 minutes from now, off again. */
    fun cycleSleep(now: Long = System.currentTimeMillis()) {
        val next = SLEEP_STEPS[(SLEEP_STEPS.indexOf(sleepMinutes) + 1) % SLEEP_STEPS.size]
        sleepMinutes = next
        sleepAt = if (next == 0) 0L else now + next * 60_000L
    }

    /** The timer has run its course. */
    fun sleepDone() { sleepMinutes = 0; sleepAt = 0L }

    /**
     * The headset's director is running, so the place, recentring and the
     * sleep timer act. A plain start (after starts that failed) has none,
     * and the tab bar then hides the buttons that would do nothing.
     */
    var directed by mutableStateOf(false)

    /** Counts up each time everything is asked to come back in front of you. */
    var bringHereAsks by mutableIntStateOf(0)
        private set

    const val SCREEN_SIZES = 5

    private var prefs: android.content.SharedPreferences? = null

    fun load(context: Context) {
        val p = context.getSharedPreferences("stage", Context.MODE_PRIVATE).also { prefs = it }
        place = runCatching { Place.valueOf(p.getString("watchIn", Place.CINEMA.name)!!) }.getOrDefault(Place.CINEMA)
        // Sizes were made larger (to 55°–115°); an older saved choice starts afresh at the default.
        screenSize = if (p.getInt("sizes", 1) < 2) DEFAULT_SIZE else p.getInt("screenSize", DEFAULT_SIZE).coerceIn(0, SCREEN_SIZES - 1)
        curved = p.getBoolean("screenCurved", false)
    }

    private fun save() {
        prefs?.edit()?.putString("watchIn", place.name)?.putInt("screenSize", screenSize)?.putInt("sizes", 2)
            ?.putBoolean("screenCurved", curved)?.apply()
    }

    fun larger() { screenSize = (screenSize + 1).coerceAtMost(SCREEN_SIZES - 1); save() }
    fun smaller() { screenSize = (screenSize - 1).coerceAtLeast(0); save() }
    fun toggleCurve() { curved = !curved; save() }
    /** Room, cinema, the dark, space, round again. */
    fun nextPlace() { place = Place.entries[(place.ordinal + 1) % Place.entries.size]; save() }
    fun bringHere() { bringHereAsks++ }
}

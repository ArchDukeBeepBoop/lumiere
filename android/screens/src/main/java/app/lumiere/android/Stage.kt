package app.lumiere.android

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Where Lumiere's screen is, on a Quest, as the sidebar sets it: in your
 * room at one of five sizes, or in the cinema from one of three rows, as
 * Apple TV's Cinema on Vision Pro offers front, middle and back. Locked, it
 * can't be carried off by a stray grab; "bring here" puts it before you.
 * Remembered between visits. The headset's own module does the placing.
 */
object Stage {
    enum class Place { ROOM, CINEMA }

    var place by mutableStateOf(Place.ROOM)
        private set
    /** 0 smallest … [ROOM_SIZES] - 1 largest. */
    var roomSize by mutableIntStateOf(2)
        private set
    /** 0 back row, 1 middle, 2 front. */
    var seat by mutableIntStateOf(1)
        private set
    var locked by mutableStateOf(false)
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

    /** Counts up each time the screen is asked to come in front of you. */
    var bringHereAsks by mutableIntStateOf(0)
        private set

    const val ROOM_SIZES = 5
    const val SEATS = 3

    private var prefs: android.content.SharedPreferences? = null

    fun load(context: Context) {
        val p = context.getSharedPreferences("stage", Context.MODE_PRIVATE).also { prefs = it }
        place = runCatching { Place.valueOf(p.getString("place", "ROOM")!!) }.getOrDefault(Place.ROOM)
        roomSize = p.getInt("roomSize", 2).coerceIn(0, ROOM_SIZES - 1)
        seat = p.getInt("seat", 1).coerceIn(0, SEATS - 1)
        locked = p.getBoolean("locked", false)
    }

    private fun save() {
        prefs?.edit()?.putString("place", place.name)?.putInt("roomSize", roomSize)
            ?.putInt("seat", seat)?.putBoolean("locked", locked)?.apply()
    }

    /** Bigger: a size up in the room, a row nearer in the cinema. */
    fun larger() {
        if (place == Place.ROOM) roomSize = (roomSize + 1).coerceAtMost(ROOM_SIZES - 1) else seat = (seat + 1).coerceAtMost(SEATS - 1)
        save()
    }

    fun smaller() {
        if (place == Place.ROOM) roomSize = (roomSize - 1).coerceAtLeast(0) else seat = (seat - 1).coerceAtLeast(0)
        save()
    }

    fun toggleCinema() { place = if (place == Place.ROOM) Place.CINEMA else Place.ROOM; save() }
    fun toggleLock() { locked = !locked; save() }
    fun bringHere() { bringHereAsks++ }
}

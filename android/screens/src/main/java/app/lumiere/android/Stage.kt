package app.lumiere.android

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Where you are on a Quest, and how films are watched, as the tab bar and
 * the Theater's transport set it: where (your room, a cinema, a cabin, a
 * lakeside, a black void or space — browsing as well as watching), how big
 * the screen is (five sizes by how much of your view it fills), and whether
 * it curves round you. Remembered between visits. The headset's own module
 * builds it.
 */
object Stage {
    /**
     * Where a film plays: your room, dimmed; a cinema round you; a timber cabin's wall; a
     * pontoon on a lake at dusk; black, for the deepest contrast; or among the stars. In the
     * order the place button comes round to them; saved by name, so the order is free to change.
     */
    enum class Place(val label: String) {
        ROOM("your room"), CINEMA("the cinema"), CABIN("the cabin"), LAKE("the lakeside"), CLOUDS("above the clouds"),
        MOON("the Moon"), STATION("the space station"), VOID("the dark"), SPACE("space")
    }

    /** A saved place by its name; a missing or unknown one (from another version) is the cinema, where everyone starts. */
    fun placeNamed(name: String?): Place = Place.entries.firstOrNull { it.name == name } ?: Place.CINEMA

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
    /** The place's own quiet sounds (the fire, the lake at night), while no film plays. */
    var ambience by mutableStateOf(true)
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
        place = placeNamed(p.getString("watchIn", null))
        // Sizes were made larger (to 55°–115°); an older saved choice starts afresh at the default.
        screenSize = if (p.getInt("sizes", 1) < 2) DEFAULT_SIZE else p.getInt("screenSize", DEFAULT_SIZE).coerceIn(0, SCREEN_SIZES - 1)
        curved = p.getBoolean("screenCurved", false)
        ambience = p.getBoolean("ambience", true)
        followPosture = p.getBoolean("followPosture", true)
        scopeFill = p.getBoolean("scopeFill", false)
        captionsNear = p.getBoolean("captionsNear", false)
        handMenu = p.getBoolean("handMenu", true)
        mount = p.getString("mountWall", null)?.let { Mount(it, p.getFloat("mountX", 0f), p.getFloat("mountY", 1.2f), p.getFloat("mountDistance", 3f)) }
        app.lumiere.android.ui.Shortcuts.load(p)
    }

    private fun save() {
        prefs?.edit()?.putString("watchIn", place.name)?.putInt("screenSize", screenSize)?.putInt("sizes", 2)
            ?.putBoolean("screenCurved", curved)?.putBoolean("ambience", ambience)?.apply()
    }

    fun larger() { screenSize = (screenSize + 1).coerceAtMost(SCREEN_SIZES - 1); save() }
    /** Straight to size [size] (the handset's seats and sizes). */
    fun sizeTo(size: Int) { screenSize = size.coerceIn(0, SCREEN_SIZES - 1); save() }

    /** In the cinema a size is a seat: its five rows, from the back to the front. */
    val SEATS = listOf("The back row", "Rear stalls", "The middle of the hall", "Front stalls", "The front row")
    /** Elsewhere, how big the screen is. */
    val SIZES = listOf("Smallest", "Small", "Medium", "Large", "Largest")
    /** Your seat in the cinema now. */
    fun seatName(): String = SEATS[screenSize.coerceIn(0, SEATS.lastIndex)]
    fun smaller() { screenSize = (screenSize - 1).coerceAtLeast(0); save() }
    fun toggleCurve() { curved = !curved; save() }
    fun toggleAmbience() { ambience = !ambience; save() }

    /** Sit down or stand up and, a moment later, the place (the hall, the screen) comes to your new height. */
    var followPosture by mutableStateOf(true)
        private set
    fun toggleFollowPosture() { followPosture = !followPosture; prefs?.edit()?.putBoolean("followPosture", followPosture)?.apply() }

    /**
     * A wide film (2.39:1) on a screen of the same height as a 16:9 one, so
     * it's wider rather than shorter, as an IMAX or a scope cinema shows it;
     * off, every film keeps the screen's width.
     */
    var scopeFill by mutableStateOf(false)
        private set
    fun toggleScopeFill() { scopeFill = !scopeFill; prefs?.edit()?.putBoolean("scopeFill", scopeFill)?.apply() }

    /** The hand menu: raise a hand and look at it (HandMenu). */
    var handMenu by mutableStateOf(true)
        private set
    fun toggleHandMenu() { handMenu = !handMenu; prefs?.edit()?.putBoolean("handMenu", handMenu)?.apply() }

    /** Captions before you, low in your view and turning with you, rather than at the screen's foot. */
    var captionsNear by mutableStateOf(false)
        private set
    fun toggleCaptionsNear() { captionsNear = !captionsNear; prefs?.edit()?.putBoolean("captionsNear", captionsNear)?.apply() }

    /**
     * A title's own picture: brightness and contrast in steps either side of
     * as it came (0, 0), kept for the film, or for the whole show.
     */
    data class Picture(val brightness: Int = 0, val contrast: Int = 0) { val plain get() = brightness == 0 && contrast == 0 }
    fun pictureFor(key: String): Picture = prefs?.getString("picture.$key", null)?.split(',')
        ?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 }?.let { Picture(it[0], it[1]) } ?: Picture()
    fun setPicture(key: String, p: Picture) {
        prefs?.edit()?.apply { if (p.plain) remove("picture.$key") else putString("picture.$key", "${p.brightness},${p.contrast}") }?.apply()
        pictureChanges++
    }
    /** Counts up each time a picture is changed, for the player to apply it. */
    var pictureChanges by mutableIntStateOf(0)
        private set
    const val PICTURE_STEPS = 4
    /** Room, cinema, cabin, lakeside, above the clouds, the Moon, the space station, the dark, space, round again. */
    fun nextPlace() { place = Place.entries[(place.ordinal + 1) % Place.entries.size]; save() }
    /** Straight to [p] (the handset's places). */
    fun goTo(p: Place) { place = p; save() }

    /**
     * Away from your room the handset — a small panel near your hands —
     * chooses what plays on the place's big screen, and the whole window
     * stays as it is for your room. True while you've asked for the whole
     * window there instead (search, settings, everything else); a film
     * starting, or another place, puts it back to the handset.
     */
    var wholeWindow by mutableStateOf(false)
    fun bringHere() { bringHereAsks++ }

    /**
     * The screen on a wall of your room: which wall (Space Setup's id for
     * it), where on it (its own x along and y up), and how far you stood,
     * which with the size sets how big it is. Null: it floats as before.
     */
    data class Mount(val wall: String, val x: Float, val y: Float, val distance: Float)
    var mount by mutableStateOf<Mount?>(null)
        private set
    /** Asked to mount the screen on the wall before you, or take it off (the Director answers). */
    var mountAsks by mutableIntStateOf(0)
        private set
    fun askMount() { mountAsks++ }
    fun mounted(m: Mount?) {
        mount = m
        prefs?.edit()?.apply {
            if (m == null) remove("mountWall")
            else putString("mountWall", m.wall).putFloat("mountX", m.x).putFloat("mountY", m.y).putFloat("mountDistance", m.distance)
        }?.apply()
    }
}

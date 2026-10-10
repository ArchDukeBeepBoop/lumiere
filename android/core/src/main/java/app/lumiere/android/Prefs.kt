package app.lumiere.android

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Every preference, each one a Settings option, as on the Mac. Compose state
 * over SharedPreferences, so a switch flipped in Settings is seen at once.
 */
class Prefs(context: Context) {
    private val store = context.getSharedPreferences("lumiere.prefs", Context.MODE_PRIVATE)

    private val flags = mutableMapOf<String, Pair<androidx.compose.runtime.MutableState<Boolean>, Boolean>>()
    private val ints = mutableMapOf<String, Pair<androidx.compose.runtime.MutableState<Int>, Int>>()

    private fun flag(key: String, default: Boolean) = mutableStateOf(store.getBoolean(key, default)).also { flags[key] = it to default }
    private fun put(key: String, value: Boolean) = store.edit().putBoolean(key, value).apply()

    private val _playsNext = flag("playsNext", true)
    var playsNext: Boolean get() = _playsNext.value
        set(v) { _playsNext.value = v; put("playsNext", v) }

    private val _videoInBackground = flag("videoInBackground", false)
    /** On a phone: a video's sound goes on with the screen off or the app left, with lock-screen controls. */
    var videoInBackground: Boolean get() = _videoInBackground.value
        set(v) { _videoInBackground.value = v; put("videoInBackground", v) }

    private val _subtitleLift = androidx.compose.runtime.mutableFloatStateOf(store.getFloat("subtitleLift", 0.06f))
    /** How far up the picture subtitles sit, as a fraction of its height; two fingers drag it on a phone. */
    var subtitleLift: Float get() = _subtitleLift.floatValue
        set(v) { _subtitleLift.floatValue = v; store.edit().putFloat("subtitleLift", v).apply() }

    private val _wallpaperColours = flag("wallpaperColours", false)
    /** On a phone from Android 12: the accent from the wallpaper rather than the Mac's gold. */
    var wallpaperColours: Boolean get() = _wallpaperColours.value
        set(v) { _wallpaperColours.value = v; put("wallpaperColours", v) }

    private val _skipsIntros = flag("skipsIntros", false)
    /** Skip intros without asking, rather than offering the button. */
    var skipsIntros: Boolean get() = _skipsIntros.value
        set(v) { _skipsIntros.value = v; put("skipsIntros", v) }

    private val _stillWatching = mutableStateOf(store.getInt("stillWatchingAfter", 3))
    /** Episodes in a row with nobody touching anything before asking. 0 never asks. */
    var stillWatchingAfter: Int get() = _stillWatching.value
        set(v) { _stillWatching.value = v; store.edit().putInt("stillWatchingAfter", v).apply() }

    private val _subtitles = flag("subtitlesOn", true)
    var subtitlesOn: Boolean get() = _subtitles.value
        set(v) { _subtitles.value = v; put("subtitlesOn", v) }

    private val _animeJapanese = flag("animeJapanese", true)
    /** Japanese audio and English subtitles in a library named Anime. */
    var animeJapanese: Boolean get() = _animeJapanese.value
        set(v) { _animeJapanese.value = v; put("animeJapanese", v) }

    private val _private = mutableStateOf(store.getStringSet("privateLibraries", emptySet())!!.toSet())
    /** Libraries kept out of sight until the private room is opened. */
    var privateLibraries: Set<String> get() = _private.value
        set(v) { _private.value = v; store.edit().putStringSet("privateLibraries", v).apply() }

    private val _roomLock = flag("roomRequiresUnlock", true)
    /** Opening the room asks for the phone's fingerprint, face or PIN. */
    var roomRequiresUnlock: Boolean get() = _roomLock.value
        set(v) { _roomLock.value = v; put("roomRequiresUnlock", v) }

    private val _roomCapture = flag("roomBlocksCapture", true)
    /** No screenshots, recordings or app-switcher preview while in the room. */
    var roomBlocksCapture: Boolean get() = _roomCapture.value
        set(v) { _roomCapture.value = v; put("roomBlocksCapture", v) }

    private val _followsMac = flag("privateFollowsMac", true)
    /** Use the Mac's private libraries rather than a list of this device's own. */
    var privateFollowsMac: Boolean get() = _followsMac.value
        set(v) { _followsMac.value = v; put("privateFollowsMac", v) }

    private val _lockMinutes = mutableStateOf(store.getInt("roomLockMinutes", 0))
    /** Minutes away from the app before the room shuts; 0 at once, -1 never. */
    var roomLockMinutes: Int get() = _lockMinutes.value
        set(v) { _lockMinutes.value = v; store.edit().putInt("roomLockMinutes", v).apply() }

    private val _ownTheme = flag("roomUsesOwnTheme", true)
    /** The room drawn in grey, so it is plain which space is open. */
    var roomUsesOwnTheme: Boolean get() = _ownTheme.value
        set(v) { _ownTheme.value = v; put("roomUsesOwnTheme", v) }

    private val _blurs = flag("roomBlursCovers", true)
    private val _tvBlurs = flag("tvBlursCovers", false)
    /** On the TV, private covers blurred in lists — off unless chosen; the phone keeps its own. */
    var tvBlursCovers: Boolean get() = _tvBlurs.value
        set(v) { _tvBlurs.value = v; put("tvBlursCovers", v) }
    /** Covers in the room blurred in lists; clear on a title's own page. */
    var roomBlursCovers: Boolean get() = _blurs.value
        set(v) { _blurs.value = v; put("roomBlursCovers", v) }

    private val _downloadCap = androidx.compose.runtime.mutableIntStateOf(store.getInt("downloadCapGb", 0))
    /** The most downloads may take, in GB; 0 for no limit. */
    var downloadCapGb: Int get() = _downloadCap.intValue
        set(v) { _downloadCap.intValue = v; store.edit().putInt("downloadCapGb", v).apply() }

    private val _wifiOnly = flag("downloadsWifiOnly", true)
    var downloadsWifiOnly: Boolean get() = _wifiOnly.value
        set(v) { _wifiOnly.value = v; put("downloadsWifiOnly", v) }

    private val _recent = mutableStateOf(store.getString("recentSearches", "")!!.split('\n').filter { it.isNotBlank() })
    /** The last searches that found something, newest first. */
    val recentSearches: List<String> get() = _recent.value

    fun rememberSearch(term: String) {
        val list = (listOf(term) + _recent.value.filter { !it.equals(term, ignoreCase = true) }).take(8)
        _recent.value = list
        store.edit().putString("recentSearches", list.joinToString("\n")).apply()
    }

    private val _opened = mutableStateOf(store.getString("recentlyOpened", "")!!.split('\n').filter { it.isNotBlank() })
    /** Titles last opened outside the private room, newest first — Search's trail before anything is typed. */
    val recentlyOpened: List<String> get() = _opened.value

    fun rememberOpened(id: String) {
        val list = (listOf(id) + _opened.value.filter { it != id }).take(8)
        _opened.value = list
        store.edit().putString("recentlyOpened", list.joinToString("\n")).apply()
    }

    fun clearSearches() {
        _recent.value = emptyList()
        store.edit().remove("recentSearches").apply()
        _opened.value = emptyList()
        store.edit().remove("recentlyOpened").apply()
    }

    /** A show's audio and subtitle language, as last chosen; "off" for no subtitles. */
    fun tracksFor(seriesId: String): Pair<String?, String?>? {
        val raw = store.getString("tracks.$seriesId", null) ?: return null
        val (a, t) = (raw.split('|') + listOf("", "")).take(2)
        return a.ifEmpty { null } to t.ifEmpty { null }
    }

    fun rememberTracks(seriesId: String, audio: String? = null, text: String? = null) {
        val (a, t) = tracksFor(seriesId) ?: (null to null)
        store.edit().putString("tracks.$seriesId", "${audio ?: a ?: ""}|${text ?: t ?: ""}").apply()
    }

    private fun intPref(key: String, default: Int) = mutableStateOf(store.getInt(key, default)).also { ints[key] = it to default }
    private fun putInt(key: String, v: Int) = store.edit().putInt(key, v).apply()

    private val _burn = flag("burnsInSubtitles", false)
    /** Anime subtitles drawn into the picture rather than over it — heavier. */
    var burnsInSubtitles: Boolean get() = _burn.value
        set(v) { _burn.value = v; put("burnsInSubtitles", v) }

    private val _subSize = intPref("subtitleSize", 1)
    /** 0 small, 1 medium, 2 large, 3 extra large — for plain subtitles. */
    var subtitleSize: Int get() = _subSize.value
        set(v) { _subSize.value = v; putInt("subtitleSize", v) }

    private val _subStyle = intPref("subtitleStyle", 0)
    /** 0 outline, 1 drop shadow, 2 dark box — for plain subtitles. */
    var subtitleStyle: Int get() = _subStyle.value
        set(v) { _subStyle.value = v; putInt("subtitleStyle", v) }

    private val _fill = flag("fillsScreen", false)
    /** Zoom to fill, cropping the edges of wide films; off fits the whole picture. */
    var fillsScreen: Boolean get() = _fill.value
        set(v) { _fill.value = v; put("fillsScreen", v) }

    private val _boost = intPref("dialogueBoost", 0)
    /** Extra loudness in decibels for small speakers: 0, 3, 6 or 9. */
    var dialogueBoost: Int get() = _boost.value
        set(v) { _boost.value = v; putInt("dialogueBoost", v) }

    private val _night = flag("nightSound", false)
    /** Loud scenes quieter and quiet ones louder. */
    var nightSound: Boolean get() = _night.value
        set(v) { _night.value = v; put("nightSound", v) }

    private fun idList(key: String) = mutableStateOf(store.getString(key, "")!!.split(',').filter { it.isNotBlank() })
    private fun saveIds(key: String, v: List<String>) = store.edit().putString(key, v.joinToString(",")).apply()

    private val _watchlist = idList("watchlist")
    /** Titles added to Up Next before they are started — Apple's "Add to Up Next". */
    var watchlist: List<String> get() = _watchlist.value
        set(v) { _watchlist.value = v.take(40); saveIds("watchlist", v.take(40)) }

    private val _notInterested = idList("notInterested")
    /** Titles marked Not Interested: kept off Home's rows. */
    var notInterested: List<String> get() = _notInterested.value
        set(v) { _notInterested.value = v; saveIds("notInterested", v) }

    private val _tick = flag("focusSound", false)
    /** A soft tick as the remote moves, as tvOS has. */
    var focusSound: Boolean get() = _tick.value
        set(v) { _tick.value = v; put("focusSound", v) }

    // Six across, as Apple TV shows a library; an earlier default of seven is moved to six once.
    private val _cols = intPref("libraryColumns", 6).also {
        if (!store.getBoolean("libraryColumnsSix", false)) { it.value = 6; store.edit().putInt("libraryColumns", 6).putBoolean("libraryColumnsSix", true).apply() }
    }
    /** Posters across a TV library: 6, 7, 8 or 10. */
    var libraryColumns: Int get() = _cols.value
        set(v) { _cols.value = v; putInt("libraryColumns", v) }

    private val _epPage = flag("episodesOpenPage", false)
    /** An episode chosen on a show's page opens its own page first, rather than playing at once. */
    var episodesOpenPage: Boolean get() = _epPage.value
        set(v) { _epPage.value = v; put("episodesOpenPage", v) }

    private val _spoilers = flag("hidesSpoilers", false)
    /** Unwatched episodes show their number only, not their name or story. */
    var hidesSpoilers: Boolean get() = _spoilers.value
        set(v) { _spoilers.value = v; put("hidesSpoilers", v) }

    private val _remote = flag("phoneRemote", true)
    /** Phones on the home Wi-Fi may pair and act as this TV's remote. */
    var phoneRemote: Boolean get() = _remote.value
        set(v) { _remote.value = v; put("phoneRemote", v) }

    private val _nightAuto = flag("nightAuto", true)
    /** From 10 pm to 6 am, night sound and a little dialogue boost by themselves. */
    var nightAuto: Boolean get() = _nightAuto.value
        set(v) { _nightAuto.value = v; put("nightAuto", v) }

    private val _subLang = androidx.compose.runtime.mutableStateOf(store.getString("subtitleLanguage", "en")!!)
    /** The subtitle language to prefer, and to fetch when a title has none. */
    var subtitleLanguage: String get() = _subLang.value
        set(v) { _subLang.value = v; store.edit().putString("subtitleLanguage", v).apply() }

    private val _keepNext = flag("keepNextReady", false)
    /** The next two episodes of what is playing kept on the device, within the download space. */
    var keepNextReady: Boolean get() = _keepNext.value
        set(v) { _keepNext.value = v; put("keepNextReady", v) }

    /** A show's seasons newest first — for long-running ones. */
    fun seasonsNewestFirst(seriesId: String): Boolean = store.getBoolean("newestFirst.$seriesId", false)
    fun setSeasonsNewestFirst(seriesId: String, on: Boolean) = store.edit().putBoolean("newestFirst.$seriesId", on).apply()

    /** A show's own picture fit, once changed while watching it. */
    fun fillFor(seriesId: String): Boolean? = if (store.contains("fill.$seriesId")) store.getBoolean("fill.$seriesId", false) else null
    fun rememberFill(seriesId: String, fill: Boolean) = store.edit().putBoolean("fill.$seriesId", fill).apply()

    /** A show's own subtitle size, once changed while watching it. */
    fun subtitleSizeFor(seriesId: String): Int? = store.getInt("subSize.$seriesId", -1).takeIf { it >= 0 }
    fun rememberSubtitleSize(seriesId: String, size: Int) = store.edit().putInt("subSize.$seriesId", size).apply()

    private val _skipCountdown = flag("skipCountdown", true)
    /** On a TV, Skip Intro counts down and skips by itself unless dismissed. */
    var skipCountdown: Boolean get() = _skipCountdown.value
        set(v) { _skipCountdown.value = v; put("skipCountdown", v) }

    private val _saver = intPref("screensaverMinutes", 5)
    /** Minutes still on a menu before the backdrop screensaver; 0 never. */
    var screensaverMinutes: Int get() = _saver.value
        set(v) { _saver.value = v; putInt("screensaverMinutes", v) }

    private val _dim = flag("dimsAtNight", true)
    /** Menus darker from 10 pm to 6 am, so a projected menu does not light the room. */
    var dimsAtNight: Boolean get() = _dim.value
        set(v) { _dim.value = v; put("dimsAtNight", v) }

    private val _pin = mutableStateOf((store.getString("devicePin", "") ?: "").let { stored ->
        // An earlier version kept the digits themselves: sealed the first time it's read.
        if (PinLock.isPlain(stored)) PinLock.seal(stored).also { store.edit().putString("devicePin", it).apply() } else stored
    })
    /** A PIN guards Settings and the private room on a shared device or a Quest. */
    val hasPin: Boolean get() = _pin.value.isNotEmpty()

    fun setPin(pin: String) {
        _pin.value = PinLock.seal(pin)
        store.edit().putString("devicePin", _pin.value).putInt("pinFailures", 0).apply()
    }

    fun clearPin() {
        _pin.value = ""
        store.edit().putString("devicePin", "").putInt("pinFailures", 0).apply()
    }

    sealed interface PinAnswer {
        data object Right : PinAnswer
        /** [triesLeft] before the pad makes you wait. */
        data class Wrong(val triesLeft: Int) : PinAnswer
        /** Too many wrong in a row: no PIN is tried for [ms]. */
        data class Wait(val ms: Long) : PinAnswer
    }

    /** Tries [pin], counting wrong ones in a row, which survive a restart. */
    fun tryPin(pin: String, now: Long = System.currentTimeMillis()): PinAnswer {
        val failures = store.getInt("pinFailures", 0)
        val wait = PinLock.waitMs(failures, store.getLong("pinFailedAt", 0), now)
        if (wait > 0) return PinAnswer.Wait(wait)
        if (PinLock.matches(_pin.value, pin)) {
            store.edit().putInt("pinFailures", 0).apply()
            return PinAnswer.Right
        }
        store.edit().putInt("pinFailures", failures + 1).putLong("pinFailedAt", now).apply()
        val left = PinLock.FREE_TRIES - (failures + 1)
        return if (left > 0) PinAnswer.Wrong(left) else PinAnswer.Wait(PinLock.waitMs(failures + 1, now, now))
    }

    private val _rowOrder = mutableStateOf(store.getString("tvRowOrder", null)?.split(',')?.filter { it.isNotBlank() } ?: TV_ROWS)
    /** The TV Home's rows, in order — the Mac's Home Order. */
    var tvRowOrder: List<String> get() = (_rowOrder.value + TV_ROWS.filter { it !in _rowOrder.value })
        set(v) { _rowOrder.value = v; store.edit().putString("tvRowOrder", v.joinToString(",")).apply() }

    private val _rowsHidden = mutableStateOf(store.getStringSet("tvRowsHidden", emptySet())!!.toSet())
    var tvRowsHidden: Set<String> get() = _rowsHidden.value
        set(v) { _rowsHidden.value = v; store.edit().putStringSet("tvRowsHidden", v).apply() }

    private val _tour = flag("tvTourShown", false)
    var tvTourShown: Boolean get() = _tour.value
        set(v) { _tour.value = v; put("tvTourShown", v) }

    private val _calm = flag("reduceMotion", Device.lowMemory)
    /** tvOS's Reduce Motion: no tilt, sweep or drift, quick fades. On by default where memory is short. */
    var reduceMotion: Boolean get() = _calm.value
        set(v) { _calm.value = v; put("reduceMotion", v) }

    private val _merged = flag("tvUpNextMerged", true)
    /** Continue Watching, Next Up and Finish the Season as one Up Next row, as the Apple TV app shows them. */
    var tvUpNextMerged: Boolean get() = _merged.value
        set(v) { _merged.value = v; put("tvUpNextMerged", v) }

    private val _previews = flag("bannerPreviews", !Device.lowMemory)
    /** A silent clip in Home's spotlight after a few seconds on it. Off by default on a low-memory device. */
    var bannerPreviews: Boolean get() = _previews.value
        set(v) { _previews.value = v; put("bannerPreviews", v) }

    private val _topBar = flag("tvTopBar", true)
    /** The TV's tabs along the top (tvOS), rather than a hidden menu on the left. */
    var tvTopBar: Boolean get() = _topBar.value
        set(v) { _topBar.value = v; put("tvTopBar", v) }

    private val _textScale = intPref("textScale", 0)
    /** 0 normal, 1 larger, 2 largest — for a screen seen from across a room. */
    var textScale: Int get() = _textScale.value
        set(v) { _textScale.value = v; putInt("textScale", v) }

    private val _clock = flag("showsClock", true)
    var showsClock: Boolean get() = _clock.value
        set(v) { _clock.value = v; put("showsClock", v) }

    private val _filmWarm = flag("filmsWarm", false)
    /** Films get the warm picture tone by themselves, whatever the everyday tone is. */
    var filmsWarm: Boolean get() = _filmWarm.value
        set(v) { _filmWarm.value = v; put("filmsWarm", v) }

    private val _compact = flag("compactHome", Device.lowMemory)
    /** TV Home keeps its first six rows; the rest wait in Library and Settings › Rows. */
    var compactHome: Boolean get() = _compact.value
        set(v) { _compact.value = v; put("compactHome", v) }

    private val _tone = intPref("pictureTone", 0)
    /** 0 neutral, 1 warmer, 2 cooler — a light tint for projectors that run blue or yellow. */
    var pictureTone: Int get() = _tone.value
        set(v) { _tone.value = v; putInt("pictureTone", v) }

    private val _lamp = flag("lampBright", false)
    /** The screen or lamp at full brightness while a film plays. */
    var lampBright: Boolean get() = _lamp.value
        set(v) { _lamp.value = v; put("lampBright", v) }

    private val _profiles = mutableStateOf(store.getString("profiles", "[]") ?: "[]")
    /** Other people signed in on this device, as JSON sessions; see Profiles. */
    var profilesJson: String get() = _profiles.value
        set(v) { _profiles.value = v; store.edit().putString("profiles", v).apply() }

    var wakeAddress: String
        get() = store.getString("wakeAddress", "") ?: ""
        set(v) { store.edit().putString("wakeAddress", v).apply() }

    private val _setupDone = flag("setupDone", false)
    /** The first-run guide was finished or put off on this device. */
    var setupDone: Boolean get() = _setupDone.value
        set(v) { _setupDone.value = v; put("setupDone", v) }

    /**
     * Every preference that differs from how Lumiere comes: its name, what it
     * is now, what it was. Settings › Your Setup lists them, each with Reset.
     */
    fun changes(): List<Triple<String, String, String>> {
        val out = mutableListOf<Triple<String, String, String>>()
        flags.forEach { (k, v) ->
            if (k !in INTERNAL && v.first.value != v.second) out += Triple(k, onOff(v.first.value), onOff(v.second))
        }
        ints.forEach { (k, v) -> if (v.first.value != v.second) out += Triple(k, "${v.first.value}", "${v.second}") }
        return out.sortedBy { label(it.first) }
    }

    /** Puts one preference back as Lumiere comes. */
    fun reset(key: String) {
        flags[key]?.let { (state, default) -> state.value = default }
        ints[key]?.let { (state, default) -> state.value = default }
        store.edit().remove(key).apply()
    }

    private fun onOff(v: Boolean) = if (v) "On" else "Off"

    /**
     * The preferences that follow a person between devices, as JSON for the
     * server. The lamp, the PIN, the screensaver, downloads and the private
     * libraries chosen by hand stay with the device.
     */
    fun exportShared(): org.json.JSONObject {
        val o = org.json.JSONObject()
        SHARED.forEach { k ->
            flags[k]?.let { o.put(k, it.first.value) }
            ints[k]?.let { o.put(k, it.first.value) }
        }
        o.put("tvRowOrder", tvRowOrder.joinToString(","))
        o.put("tvRowsHidden", tvRowsHidden.joinToString(","))
        return o
    }

    /** What another device saved, taken in; returns whether anything changed. */
    fun importShared(o: org.json.JSONObject): Boolean {
        var changed = false
        val edit = store.edit()
        SHARED.forEach { k ->
            if (!o.has(k)) return@forEach
            flags[k]?.let { (state, _) ->
                val v = o.optBoolean(k)
                if (state.value != v) { state.value = v; edit.putBoolean(k, v); changed = true }
            }
            ints[k]?.let { (state, _) ->
                val v = o.optInt(k)
                if (state.value != v) { state.value = v; edit.putInt(k, v); changed = true }
            }
        }
        edit.apply()
        o.optString("tvRowOrder").takeIf { it.isNotBlank() }?.split(',')?.let { if (it != tvRowOrder) { tvRowOrder = it; changed = true } }
        if (o.has("tvRowsHidden")) o.optString("tvRowsHidden").split(',').filter { it.isNotBlank() }.toSet()
            .let { if (it != tvRowsHidden) { tvRowsHidden = it; changed = true } }
        return changed
    }

    /** Tells [onChange] whenever a shared preference is set here. */
    fun watchShared(onChange: () -> Unit) {
        store.registerOnSharedPreferenceChangeListener(listener(onChange))
    }

    private var keep: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    private fun listener(onChange: () -> Unit) = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key in SHARED || key == "tvRowOrder" || key == "tvRowsHidden") onChange()
    }.also { keep = it }

    companion object {
        /** Bookkeeping, not choices. */
        val INTERNAL = setOf("setupDone", "tvTourShown")
        private val LABELS = mapOf(
            "playsNext" to "Play the next episode automatically", "videoInBackground" to "Sound with the screen off",
            "wallpaperColours" to "Colours from the wallpaper", "skipsIntros" to "Skip intros without asking",
            "subtitlesOn" to "Subtitles on", "animeJapanese" to "Anime in Japanese", "roomRequiresUnlock" to "Private Room asks to unlock",
            "roomBlocksCapture" to "Private Room hidden from screenshots", "privateFollowsMac" to "Private libraries follow the Mac",
            "roomUsesOwnTheme" to "Private Room's own theme", "roomBlursCovers" to "Private Room covers blurred",
            "tvBlursCovers" to "Blur covers on the TV", "downloadsWifiOnly" to "Download on Wi-Fi only",
            "burnsInSubtitles" to "Burn in subtitles", "subtitleSize" to "Subtitle size", "subtitleStyle" to "Subtitle style",
            "fillsScreen" to "Fill the screen", "dialogueBoost" to "Dialogue boost", "nightSound" to "Night sound",
            "focusSound" to "Sound on focus", "libraryColumns" to "Library columns", "episodesOpenPage" to "Episodes open their page",
            "hidesSpoilers" to "Hide spoilers", "phoneRemote" to "Phone as a remote", "nightAuto" to "Night mode by itself",
            "keepNextReady" to "Keep the next episode ready", "skipCountdown" to "Countdown on Skip", "screensaverMinutes" to "Screensaver after (minutes)",
            "dimsAtNight" to "Dim at night", "reduceMotion" to "Reduce motion", "tvUpNextMerged" to "One Up Next row",
            "bannerPreviews" to "Moving previews", "tvTopBar" to "Top bar on TV", "textScale" to "Text size", "showsClock" to "Clock",
            "filmsWarm" to "Warm picture for films", "compactHome" to "Compact Home", "pictureTone" to "Picture tone",
            "lampBright" to "Bright lamp", "stillWatchingAfter" to "Ask \u201CStill watching?\u201D after",
            "roomLockMinutes" to "Private Room locks after (minutes)",
        )

        /** The name a person knows a preference by. */
        fun label(key: String) = LABELS[key]
            ?: key.replace(Regex("([a-z])([A-Z])"), "$1 $2").replaceFirstChar { it.uppercase() }

        val SHARED = listOf("playsNext", "skipsIntros", "stillWatchingAfter", "subtitlesOn", "animeJapanese", "burnsInSubtitles",
            "subtitleSize", "subtitleStyle", "dialogueBoost", "nightSound", "skipCountdown", "privateFollowsMac", "roomLockMinutes",
            "roomUsesOwnTheme", "roomBlursCovers", "pictureTone", "tvUpNextMerged", "tvTopBar", "textScale")
        val TV_ROWS = listOf("continue", "nextup", "finish", "series", "libraries", "recent", "because", "topfilms", "topseries",
            "topanime", "genres", "collections", "watched")
        val TV_ROW_NAMES = mapOf("continue" to "Continue Watching", "nextup" to "Next Up", "finish" to "Finish the Season",
            "series" to "Continue the Series", "libraries" to "Libraries", "recent" to "Recently Added", "topfilms" to "Top 10 Films",
            "topseries" to "Top 10 Series", "topanime" to "Top 10 Anime", "genres" to "Genres", "watched" to "Watched Lately",
            "because" to "Because You Watched", "collections" to "Collections")
    }
}

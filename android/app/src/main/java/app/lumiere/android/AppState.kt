package app.lumiere.android

import app.lumiere.android.api.is3D
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.Session
import java.util.UUID

/** Where the app is: one screen on top of a stack, Back pops it. */
sealed interface Screen {
    data object Home : Screen
    data class Library(val view: Item) : Screen
    /** [seasonId]: open a show on this season, as an episode card on TV does. */
    data class Detail(val id: String, val seasonId: String? = null) : Screen
    /** [auto] when the next episode started by itself, which counts toward "Still watching?". */
    data class Player(val id: String, val startSeconds: Double?, val auto: Boolean = false) : Screen
    data object Search : Screen
    data object Settings : Screen
    data object Downloads : Screen
    data class Music(val view: Item) : Screen
    data class Album(val id: String) : Screen
    data class Artist(val artist: Item, val libraryId: String) : Screen
    data object NowPlaying : Screen
    data class Edit(val id: String) : Screen
    data object Favourites : Screen
    data object Collections : Screen
    data object Playlists : Screen
    data class Playlist(val id: String, val name: String) : Screen
    data class Person(val id: String, val name: String) : Screen
    data class Genre(val name: String) : Screen
    data object DiagnosticsView : Screen
    data object TvLibrary : Screen
    /** The first-run guide. See `SetupScreen`. */
    data object Setup : Screen
}

/**
 * The signed-in session and the screen stack. Plain Compose state rather than
 * a navigation library: the app has five screens and Back is the only
 * gesture between them.
 */
class AppState(context: Context) {
    private val prefs = context.getSharedPreferences("lumiere", Context.MODE_PRIVATE)
    val settings = Prefs(context)
    lateinit var downloads: app.lumiere.android.downloads.Downloads
    /** The phone's copy of the video libraries, and what keeps it current. See CacheSync. */
    lateinit var cache: app.lumiere.android.cache.LibraryCache
    lateinit var cacheSync: app.lumiere.android.cache.CacheSync

    /** Starts keeping the copy current, when signed in. */
    fun followLibrary() {
        val s = session ?: return
        server?.let { cacheSync.start(it, s.userId) }
    }

    /**
     * Whether the private room is open right now. Never saved: the app opens
     * with it shut every time, and leaving the app shuts it (MainActivity).
     */
    var roomOpen by mutableStateOf(false)

    /**
     * The Mac's private libraries, from the server; see Prefs.privateFollowsMac.
     * Kept between launches: the saved Home is drawn before the Mac answers, and
     * with nothing known then, private titles showed in the ordinary room.
     */
    private var _macPrivate by mutableStateOf(prefs.getStringSet("macPrivate", null)?.toSet())
    var macPrivate: Set<String>
        get() = _macPrivate.orEmpty()
        set(v) { _macPrivate = v; prefs.edit().putStringSet("macPrivate", v).apply() }

    /**
     * Whether which libraries are private is known yet. Until it is, the
     * ordinary room shows nothing rather than risk showing them all.
     */
    val privacyKnown: Boolean get() = !settings.privateFollowsMac || _macPrivate != null

    val privateLibraries: Set<String>
        get() = if (settings.privateFollowsMac) macPrivate else settings.privateLibraries

    /** The card the remote is on, for Play/Pause to start it. */
    var focusedItem: Item? = null

    /** The TV's menu, hidden until Back on Home asks for it. */
    var tvMenuOpen by mutableStateOf(false)
    /** Home's spotlight has the remote: the menu bar shows over it, as on tvOS. */
    var tvAtTop by mutableStateOf(false)
    /** Set at start: this is the TV layout, whose blur setting is its own. */
    var isTv = false
    /** A newer build found by the daily check; the menu bar offers it. */
    var updateReady by mutableStateOf<String?>(null)
    /** Home's quick toggles (hold Menu on Home). */
    var quickToggles by mutableStateOf(false)
    /** The episode last chosen on each show's page, to come back to. */
    val lastEpisode = mutableMapOf<String, String>()
    /** Up Next's first title on Home, for Play pressed twice. */
    var upNextTop: Item? = null
    /** Where Home was scrolled, for Back to return to the same place. */
    var homeScroll = 0 to 0
    /** Each library's sort and filters, kept for the session. */
    val libraryQueries = mutableMapOf<String, Any>()
    /** Searches made inside the room: kept in memory only, gone when it shuts. */
    var roomSearches by mutableStateOf<List<String>>(emptyList())
    /** A change just made, offered back for a few seconds: what it says, and how to undo it. */
    var undo by mutableStateOf<Pair<String, () -> Unit>?>(null)
    /** Titles just marked watched: kept off Up Next before the server's next answer. */
    var justWatched by mutableStateOf<Set<String>>(emptySet())
    /** "Leave Lumiere?" is showing. */
    var confirmExit by mutableStateOf(false)

    /** A card whose actions are open on the TV; see TvActions. */
    var actionsFor by mutableStateOf<Item?>(null)
    /** Bumped when an action changed something Home shows. */
    var homeRefresh by mutableStateOf(0)

    /** Backdrops for the screensaver: what Home last showed. */
    var saverPool by mutableStateOf<List<Item>>(emptyList())

    /** Waiting on the device PIN before this runs; see [guarded]. */
    var pinFor by mutableStateOf<(() -> Unit)?>(null)
    /** The PIN was given since the app last came to the front. */
    var pinOpen = false

    /** Runs [action] — after the device PIN, when Settings has one. */
    fun guarded(action: () -> Unit) {
        if (settings.devicePin.isEmpty() || pinOpen) action() else pinFor = action
    }

    /** When the app was left with the room open, for the lock timer. */
    var leftAt: Long? = null

    fun closeRoom() {
        roomOpen = false
        roomSearches = emptyList()
        app.lumiere.android.ui.RoomTheme.isOn = false
        if (app.lumiere.android.music.Music.isPlayingFromRoom) app.lumiere.android.music.Music.stop()
    }

    /** Hidden right now: the private libraries outside the room, the rest inside. */
    fun hides(libraryId: String?): Boolean {
        if (!privacyKnown && !roomOpen) return true
        val private = libraryId != null && libraryId in privateLibraries
        return if (roomOpen) !private else private
    }

    fun visible(items: List<Item>): List<Item> = when {
        !privacyKnown && !roomOpen -> emptyList()
        privateLibraries.isEmpty() && !roomOpen -> items
        else -> items.filter { !hides(it.libraryId) }
    }

    fun visibleViews(views: List<Item>): List<Item> = when {
        !privacyKnown && !roomOpen -> emptyList()
        privateLibraries.isEmpty() && !roomOpen -> views
        else -> views.filter { !hides(it.id) }
    }

    /** Stable per install, as the server keys sessions on it. */
    val deviceId: String = prefs.getString("deviceId", null) ?: UUID.randomUUID().toString().also {
        prefs.edit().putString("deviceId", it).apply()
    }

    var session by mutableStateOf(loadSession())
        private set

    var server: Server? = session?.let { Server(it.serverUrl, deviceId, it.token) }
        private set

    val stack = mutableStateListOf<Screen>(Screen.Home)
    val top: Screen get() = stack.last()

    /** The libraries, kept from Home, so the player can tell an anime library. */
    // State, so the tab bar's Music entry appears once Home has listed them.
    var views by mutableStateOf<List<Item>>(emptyList())

    /** Episodes started by themselves in a row; any episode chosen by hand resets it. */
    var autoStreak = 0

    fun push(screen: Screen) {
        if (screen is Screen.Player) autoStreak = if (screen.auto) autoStreak + 1 else 0
        stack += screen
        // Never from the room: nothing private is kept outside it.
        if (screen is Screen.Detail && !roomOpen) settings.rememberOpened(screen.id)
    }

    /** A tab from the bar: Home underneath it, so Back returns Home. */
    fun tab(screen: Screen) {
        tvMenuOpen = false
        stack.clear()
        stack += Screen.Home
        if (screen != Screen.Home) stack += screen
    }

    /** False when there is nothing to go back to, so the activity closes. */
    fun pop(): Boolean {
        if (stack.size <= 1) return false
        stack.removeAt(stack.lastIndex)
        return true
    }

    fun signedIn(session: Session, server: Server) {
        prefs.edit()
            .putString("server", session.serverUrl).putString("userId", session.userId)
            .putString("userName", session.userName).putString("token", session.token)
            .putString("serverName", session.serverName).apply()
        // Another account or server: the copy belongs to the last one.
        if (prefs.getString("cacheOwner", null) != "${session.serverUrl}|${session.userId}") {
            cacheSync.forget()
            prefs.edit().putString("cacheOwner", "${session.serverUrl}|${session.userId}").apply()
        }
        this.server = server
        this.session = session
        stack.clear()
        stack += Screen.Home
        followLibrary()
    }

    fun signOut() {
        prefs.edit().remove("token").remove("cacheOwner").apply()
        app.lumiere.android.api.SnapshotCache.clear()
        cacheSync.forget()
        _macPrivate = null
        prefs.edit().remove("macPrivate").apply()
        closeRoom()
        session = null
        server = null
    }

    private fun loadSession(): Session? {
        val url = prefs.getString("server", null) ?: return null
        val token = prefs.getString("token", null) ?: return null
        return Session(
            url, prefs.getString("userId", "")!!, prefs.getString("userName", "")!!,
            token, prefs.getString("serverName", "Lumiere")!!,
        )
    }

    val lastServer: String? get() = prefs.getString("server", null)
    val lastUser: String? get() = prefs.getString("userName", null)
}

/** Opening the room: its palette on, if Settings says so. */
fun AppState.openRoom() {
    roomOpen = true
    app.lumiere.android.ui.RoomTheme.isOn = settings.roomUsesOwnTheme
    app.lumiere.android.ui.RoomTheme.blursCovers = if (isTv) settings.tvBlursCovers else settings.roomBlursCovers
}

/** A 3D title: marked so in its name, or kept in a library called 3D. */
fun AppState.is3D(item: app.lumiere.android.api.Item): Boolean =
    item.is3D || views.any { it.id == item.libraryId && it.name.contains("3D", ignoreCase = true) }

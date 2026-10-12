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
    /** The videos kept on this device itself (local.OnDeviceScreen). */
    data object OnDevice : Screen
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
        // Not for whoever is behind "Who's watching?": the copy may be someone else's in a moment.
        if (choosing) return
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

    /** The private libraries, spelt as this account's own library ids (RoomLibraries). */
    val privateLibraries: Set<String>
        get() {
            val raw = if (settings.privateFollowsMac) macPrivate else settings.privateLibraries
            val shown = views
            privateMemo?.let { (r, v, out) -> if (r == raw && v === shown) return out }
            return RoomLibraries.match(raw, shown.map { it.id }).also { privateMemo = Triple(raw, shown, it) }
        }
    // Asked for once per card in a row: matched once per change, not each time.
    private var privateMemo: Triple<Set<String>, List<Item>, Set<String>>? = null

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
    /** Titles just taken off Continue Watching: kept off Home before the server's next answer, until played again. */
    var offContinue by mutableStateOf<Set<String>>(emptySet())
    /** My List as you've changed it, for whoever is signed in: a new one for each account. See MyList. */
    val myList: MyList get() = session?.userId.let { u -> myListFor.takeIf { it.owner == u } ?: MyList(u).also { myListFor = it } }
    private var myListFor = MyList(null)
    /** "Leave Lumiere?" is showing. */
    var confirmExit by mutableStateOf(false)
    /** What stopped the app last time, shown once at the next start (CrashLog.unseen). */
    var crashReport by mutableStateOf<String?>(null)

    /** A card whose actions are open on the TV; see TvActions. */
    var actionsFor by mutableStateOf<Item?>(null)
    /** The Home row that card was held in, when it can be taken off it; see UpNextDismissed.removal. */
    var actionsRow: String? = null
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
        if (!settings.hasPin || pinOpen) action() else pinFor = action
    }

    /** Waiting on a new PIN to be chosen before this runs: the private room on a Quest with none yet. */
    var pinChooseFor by mutableStateOf<(() -> Unit)?>(null)

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

    /** Signed in, or a profile chosen: [session] is watching now, and is kept among the profiles. */
    fun signedIn(session: Session, server: Server, imageTag: String? = null) {
        // Someone else was watching: none of their place in the app comes along.
        this.session?.let { was -> if (Profiles.key(was) != Profiles.key(session)) leavePerson(was, session) }
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
        keepProfile(Profile(session, imageTag ?: profiles.firstOrNull { it.key == Profiles.key(session) }?.imageTag))
        choosing = false
        stack.clear()
        stack += Screen.Home
        followLibrary()
    }

    /**
     * Signs out the profile watching now; the others stay on this device. With
     * someone left, "Who's watching?" follows, the first of them behind it
     * until a profile is chosen; with nobody, signing in afresh.
     */
    fun signOut() {
        val leaving = session?.let(Profiles::key)
        val (rest, then) = Profiles.remove(profiles, leaving ?: "", leaving)
        prefs.edit().remove("token").remove("cacheOwner").apply()
        app.lumiere.android.api.SnapshotCache.clear()
        cacheSync.forget()
        _macPrivate = null
        prefs.edit().remove("macPrivate").apply()
        closeRoom()
        leaving?.let(settings::forgetPerson)
        saveProfiles(rest)
        val next = rest.firstOrNull()
        if (then == Profiles.Start.SignIn || next == null) {
            // Nothing of theirs (searches, lists) is left for whoever signs in next.
            leaving?.let { settings.switchPerson(null, it) }
            settings.stopWatchingShared()
            choosing = false
            session = null
            server = null
            return
        }
        session?.let { leavePerson(it, next.session, keepTrail = false) }
        // The next one's keys, as signedIn writes them, so a start before anyone is chosen finds them.
        prefs.edit()
            .putString("server", next.session.serverUrl).putString("userId", next.session.userId)
            .putString("userName", next.session.userName).putString("token", next.session.token)
            .putString("serverName", next.session.serverName).apply()
        server = Server(next.session.serverUrl, deviceId, next.session.token)
        session = next.session
        choosingCanCancel = false
        choosing = true
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

    /** Everyone signed in on this device, the one watching among them; see Profiles. */
    var profiles by mutableStateOf(Profiles.migrate(Profiles.decode(settings.profilesJson), session))
        private set

    /** The one watching now, as a profile: their picture's tag with their session. */
    val currentProfile: Profile?
        get() = session?.let { s -> profiles.firstOrNull { it.key == Profiles.key(s) } ?: Profile(s) }

    /** "Who's watching?" is up, in place of every screen (WhoIsWatching). */
    var choosing by mutableStateOf(false)
        private set
    /** It was asked for from inside the app, so Back returns to where you were; at start, Back leaves. */
    var choosingCanCancel = false
        private set

    init {
        // Older versions kept one session: it is the first profile now, saved as one.
        if (Profiles.encode(profiles) != settings.profilesJson) settings.profilesJson = Profiles.encode(profiles)
        val start = Profiles.start(profiles.size, session != null, settings.askWhoIsWatching)
        // Someone signed out with others still here: the first of them behind "Who's watching?", always asked.
        if (session == null) profiles.firstOrNull()?.let { p ->
            session = p.session
            server = Server(p.session.serverUrl, deviceId, p.session.token)
            choosing = true
        }
        // Asked once per start of the app, not again when the window is made afresh (the Quest's panel).
        if (!askedAtStart) {
            askedAtStart = true
            if (start == Profiles.Start.Choose) choosing = true
        }
    }

    private fun saveProfiles(list: List<Profile>) {
        profiles = list
        settings.profilesJson = Profiles.encode(list)
    }

    private fun keepProfile(p: Profile) = saveProfiles(Profiles.upsert(profiles, p))

    /** The pictures the server keeps for its people now, by profile key; a key not given is left as it is. */
    fun updateProfileImages(tags: Map<String, String?>) {
        val updated = profiles.map { p -> if (p.key in tags && tags[p.key] != p.imageTag) p.copy(imageTag = tags[p.key]) else p }
        if (updated != profiles) saveProfiles(updated)
    }

    /**
     * "Who's watching?", asked for from Settings, the TV's menu bar or the
     * Quest's tab bar; Back comes back to where you were. Never over a film:
     * one still open is closed first, as it would be by Back.
     */
    fun askWhoIsWatching() {
        while (top is Screen.Player && pop()) Unit
        // The private room shuts, as leaving the app shuts it, and nothing of it waits behind for Back.
        if (roomOpen) { closeRoom(); stack.clear(); stack += Screen.Home }
        tvMenuOpen = false; quickToggles = false; actionsFor = null; confirmExit = false; undo = null
        // Play on the remote must not start the last card, behind the picker.
        focusedItem = null; upNextTop = null
        // Nothing of theirs on the screensaver, the wall or the cinema's screen while someone else may be choosing.
        saverPool = emptyList()
        app.lumiere.android.ui.PosterWall.open = false
        app.lumiere.android.ui.Marquee.item = null
        app.lumiere.android.ui.Idle.leftOff = null
        choosingCanCancel = true
        choosing = true
    }

    /** Back on "Who's watching?" asked for from inside the app: the same person, where they were. */
    fun keepWatching() {
        if (!choosingCanCancel) return
        choosing = false
        followLibrary()
    }

    /**
     * [profile] chosen on "Who's watching?". The one already watching carries on
     * where they were (a title the widget opened at start stays open); anyone
     * else starts at Home.
     */
    fun choose(profile: Profile) {
        val s = session
        if (s != null && Profiles.key(s) == profile.key && server != null) {
            choosing = false
            // Chosen while the picker came first: the copy is theirs, and kept current.
            if (prefs.getString("cacheOwner", null) != profile.key) {
                cacheSync.forget()
                prefs.edit().putString("cacheOwner", profile.key).apply()
            }
            followLibrary()
            return
        }
        signedIn(profile.session, Server(profile.session.serverUrl, deviceId, profile.session.token), profile.imageTag)
    }

    /** [key] off this device, from Edit on "Who's watching?". The one watching now is signed out. */
    fun removeProfile(key: String) {
        if (session?.let(Profiles::key) == key) { signOut(); return }
        saveProfiles(Profiles.remove(profiles, key, session?.let(Profiles::key)).first)
        settings.forgetPerson(key)
    }

    /**
     * Nothing of [was]'s place in the app is left for [next]: the private room
     * shut, nothing focused, offered back or half-chosen, Home from the top, the
     * music stopped, and their searches and lists put away for when they come
     * back ([keepTrail]; not for someone signed out).
     */
    private fun leavePerson(was: Session, next: Session, keepTrail: Boolean = true) {
        settings.stopWatchingShared()
        closeRoom()
        if (app.lumiere.android.music.Music.queue.isNotEmpty()) app.lumiere.android.music.Music.stop()
        focusedItem = null; upNextTop = null; actionsFor = null; undo = null
        tvMenuOpen = false; tvAtTop = false; quickToggles = false; confirmExit = false
        homeScroll = 0 to 0
        lastEpisode.clear(); libraryQueries.clear()
        justWatched = emptySet(); saverPool = emptyList(); views = emptyList()
        autoStreak = 0
        pinFor = null; pinChooseFor = null; pinOpen = false; leftAt = null
        app.lumiere.android.ui.Marquee.item = null
        app.lumiere.android.ui.PosterWall.open = false
        app.lumiere.android.ui.Idle.leftOff = null
        // Another server: which of its libraries are private isn't known until it says.
        if (was.serverUrl != next.serverUrl) { _macPrivate = null; prefs.edit().remove("macPrivate").apply() }
        settings.switchPerson(if (keepTrail) Profiles.key(was) else null, Profiles.key(next))
        stack.clear()
        stack += Screen.Home
    }

    private companion object {
        /** "Who's watching?" was decided for this start of the app. */
        var askedAtStart = false
    }
}

/** The open window's state, for panels outside it: the Quest's sidebar. */
object OpenApp {
    var state by mutableStateOf<AppState?>(null)
    /** Leaves the whole app: on the Quest the headset's own activity, of which this window is only a panel. */
    var quit: (() -> Unit)? = null
    /** Presses a remote key in the open window, as a TV remote would: the Quest's controllers use it. */
    var press: ((Int) -> Unit)? = null
    /** Scrolls the open window by [amount] wheel steps (up positive): the Quest's thumbstick, smoothly. */
    var scroll: ((Float) -> Unit)? = null
    /**
     * The window's signed-in image loader, for panels outside it (the Quest's
     * poster wall, ornament and transport): posters are behind sign-in, and a
     * panel with the default loader drew them blank.
     */
    var images by mutableStateOf<coil.ImageLoader?>(null)
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

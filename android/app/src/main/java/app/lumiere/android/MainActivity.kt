@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android

import androidx.compose.ui.unit.sp
import androidx.compose.foundation.background
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import app.lumiere.android.api.shuffleFrom
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.layout.fillMaxSize
import app.lumiere.android.api.clientSettings
import app.lumiere.android.api.saveClientSettings
import kotlinx.coroutines.launch
import app.lumiere.android.player.PlayerScreen
import app.lumiere.android.ui.DetailScreen
import app.lumiere.android.ui.HomeScreen
import app.lumiere.android.ui.LibraryScreen
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.LumiereTheme
import app.lumiere.android.ui.SearchScreen
import app.lumiere.android.ui.SignInScreen
import app.lumiere.android.api.libraries
import app.lumiere.android.ui.detectFormFactor
import coil.ImageLoader
import coil.compose.LocalImageLoader

class MainActivity : ComponentActivity() {
    private lateinit var state: AppState
    private var longBack = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CrashGuard.starting(this)
        // Two starts in a row that never drew: the safe screen, from which a fix can still be installed.
        if (CrashGuard.needsSafeMode(this)) { CrashGuard.showSafeMode(this); return }
        Device.detect(this)
        app.lumiere.android.api.SnapshotCache.dir = cacheDir.resolve("home")
        state = AppState(this)
        state.downloads = app.lumiere.android.downloads.Downloads(this)
        state.cache = app.lumiere.android.cache.LibraryCache(this)
        state.cacheSync = app.lumiere.android.cache.CacheSync(state.cache)
        openFrom(intent)
        // Closed by the system to free memory, and now back: the title that
        // was open, with Resume ready, rather than Home as if nothing happened.
        if (savedInstanceState != null) restoreLast()
        setContent {
            LumiereTheme {
                // "tv" in the launch intent draws the TV layout on a phone held
                // sideways — how the TV screens are checked without the TV.
                val form = if (intent?.getBooleanExtra("tv", false) == true) {
                    requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    app.lumiere.android.ui.FormFactor(isTv = true)
                } else detectFormFactor(LocalContext.current)
                // The preview drawn at a 1080p TV's scale — 540 units tall — so
                // what is checked on the phone is what the projector shows.
                val real = androidx.compose.ui.platform.LocalDensity.current
                val tvPreview = intent?.getBooleanExtra("tv", false) == true
                // Larger text, for a screen read from across a room (Settings).
                val textScale = 1f + 0.15f * state.settings.textScale
                val density = if (tvPreview) androidx.compose.ui.unit.Density(
                    resources.displayMetrics.heightPixels.coerceAtMost(resources.displayMetrics.widthPixels) / 540f,
                    real.fontScale * textScale) else androidx.compose.ui.unit.Density(real.density, real.fontScale * textScale)
                CompositionLocalProvider(LocalFormFactor provides form, androidx.compose.ui.platform.LocalDensity provides density) {
                    App(state) { finish() }
                }
                // No screenshots, screen recording or app-switcher snapshot
                // while the room is open.
                // tvOS checks for updates by itself: at start and twice a day after.
                androidx.compose.runtime.LaunchedEffect(state.session?.token) {
                    while (true) {
                        state.server?.let { s -> state.updateReady = app.lumiere.android.Updater.check(s)?.name }
                        kotlinx.coroutines.delay(12 * 3600_000L)
                    }
                }
                androidx.compose.runtime.LaunchedEffect(state.settings.dimsAtNight) {
                    while (true) {
                        val h = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                        app.lumiere.android.ui.Night.on = state.settings.dimsAtNight && (h >= 22 || h < 6)
                        kotlinx.coroutines.delay(5 * 60_000L)
                    }
                }
                // Music playing in the background: the menus go still, leaving the projector's
                // little processor to the sound. Back to the setting when it stops.
                androidx.compose.runtime.LaunchedEffect(app.lumiere.android.music.Music.isPlaying, state.settings.reduceMotion) {
                    app.lumiere.android.Motion.reduced = state.settings.reduceMotion || (app.lumiere.android.Device.lowMemory && app.lumiere.android.music.Music.isPlaying)
                }
                androidx.compose.runtime.LaunchedEffect(state.roomOpen, state.settings.roomBlocksCapture) {
                    if (state.roomOpen && state.settings.roomBlocksCapture) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    }
                }
            }
        }
    }

    /**
     * Leaving the app shuts the room after the minutes Settings gives — at
     * once by default, as quitting the Mac app does — and stops music that
     * came from it, whose title would otherwise sit on the lock screen. The
     * app-switcher snapshot is blocked meanwhile (FLAG_SECURE).
     */
    override fun onStop() {
        super.onStop()
        if (!::state.isInitialized) return
        state.cacheSync.stop()
        rememberLast()
        state.pinOpen = false
        if (!state.roomOpen) return
        if (state.settings.roomLockMinutes == 0) shutRoom() else state.leftAt = System.currentTimeMillis()
    }

    override fun onStart() {
        super.onStart()
        if (!::state.isInitialized) return
        state.followLibrary()
        val left = state.leftAt ?: return
        state.leftAt = null
        val minutes = state.settings.roomLockMinutes
        if (state.roomOpen && minutes >= 0 && System.currentTimeMillis() - left >= minutes * 60_000L) shutRoom()
    }

    private fun rememberLast() {
        val id = when (val top = state.top) {
            is Screen.Player -> top.id
            is Screen.Detail -> top.id
            else -> null
        }
        getSharedPreferences("lumiere", MODE_PRIVATE).edit()
            .putString("lastTitle", if (state.roomOpen) null else id)
            .putLong("lastTitleAt", System.currentTimeMillis()).apply()
    }

    private fun restoreLast() {
        val prefs = getSharedPreferences("lumiere", MODE_PRIVATE)
        val id = prefs.getString("lastTitle", null) ?: return
        if (System.currentTimeMillis() - prefs.getLong("lastTitleAt", 0) > 3 * 3600_000L) return
        if (state.session == null || state.stack.size > 1) return
        state.push(Screen.Detail(id))
    }

    private fun shutRoom() {
        state.closeRoom()
        while (state.top !is Screen.Home && state.pop()) Unit
    }

    private var swallowOkUp = false
    private var lastBack = 0L
    private var heldPlay = false
    private var heldMenu = false
    private var lastPlay = 0L
    private var pendingPlay: Runnable? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (!::state.isInitialized) return super.dispatchKeyEvent(event)
        // Any key ends the screensaver without also doing what it says.
        val minutes = state.settings.screensaverMinutes
        val saving = minutes > 0 && state.top !is Screen.Player &&
            System.currentTimeMillis() - app.lumiere.android.ui.Idle.last >= minutes * 60_000L
        val shown = app.lumiere.android.ui.Idle.showing
        app.lumiere.android.ui.Idle.poke()
        if (saving) {
            val ok = event.keyCode == android.view.KeyEvent.KEYCODE_DPAD_CENTER || event.keyCode == android.view.KeyEvent.KEYCODE_ENTER
            if (ok && event.action == android.view.KeyEvent.ACTION_DOWN && shown != null)
                state.push(if (app.lumiere.android.ui.Idle.resumes) Screen.Player(shown.id, null) else Screen.Detail(shown.id))
            if (ok) swallowOkUp = true
            return true
        }
        if (swallowOkUp && event.action == android.view.KeyEvent.ACTION_UP) { swallowOkUp = false; return true }
        // Two quick presses of Back: Home, from however deep.
        if (event.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP &&
            event.repeatCount == 0 && state.top !is Screen.Player && state.stack.size > 2) {
            val now = event.eventTime
            if (now - lastBack < 400) { lastBack = 0; state.tab(Screen.Home); return true }
            lastBack = now
        }
        // tvOS's soft tick as the remote moves, when asked for.
        if (state.settings.focusSound && event.action == android.view.KeyEvent.ACTION_DOWN && event.keyCode in
            android.view.KeyEvent.KEYCODE_DPAD_UP..android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
            window.decorView.playSoundEffect(android.view.SoundEffectConstants.CLICK)
        if (event.action == android.view.KeyEvent.ACTION_DOWN) when (event.keyCode) {
            android.view.KeyEvent.KEYCODE_DPAD_LEFT -> { app.lumiere.android.ui.FocusDirection.dx = -1f; app.lumiere.android.ui.FocusDirection.dy = 0f }
            android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> { app.lumiere.android.ui.FocusDirection.dx = 1f; app.lumiere.android.ui.FocusDirection.dy = 0f }
            android.view.KeyEvent.KEYCODE_DPAD_UP -> { app.lumiere.android.ui.FocusDirection.dx = 0f; app.lumiere.android.ui.FocusDirection.dy = -1f }
            android.view.KeyEvent.KEYCODE_DPAD_DOWN -> { app.lumiere.android.ui.FocusDirection.dx = 0f; app.lumiere.android.ui.FocusDirection.dy = 1f }
        }
        if (state.session != null && state.top !is Screen.Player) {
            // Holding Back: Home, from anywhere.
            if (event.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_DOWN &&
                event.repeatCount == 3) {
                state.tvMenuOpen = false; state.confirmExit = false; state.tab(Screen.Home)
                longBack = true
                return true
            }
            if (event.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.repeatCount > 0) return true
            // The release of that long press is not also a Back.
            if (event.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP && longBack) {
                longBack = false
                return true
            }
            // A change just made: Menu takes it back while the notice shows.
            state.undo?.let { (_, undo) ->
                if (event.keyCode == android.view.KeyEvent.KEYCODE_MENU) {
                    if (event.action == android.view.KeyEvent.ACTION_UP) { undo(); state.undo = null }
                    return true
                }
            }
            // Menu held on Home: the quick toggles.
            if (event.keyCode == android.view.KeyEvent.KEYCODE_MENU && state.top == Screen.Home) {
                if (event.action == android.view.KeyEvent.ACTION_DOWN && event.repeatCount == 3) { state.quickToggles = true; heldMenu = true }
                if (event.repeatCount > 0) return true
                if (event.action == android.view.KeyEvent.ACTION_UP && heldMenu) { heldMenu = false; return true }
            }
            // Play/Pause on a card plays it — a show plays its next episode.
            val play = event.keyCode == android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                event.keyCode == android.view.KeyEvent.KEYCODE_MEDIA_PLAY
            val target = state.focusedItem
            if (play && target != null && state.top != Screen.NowPlaying) {
                // Held: shuffle — a random episode of a show, a random title of a library.
                if (event.action == android.view.KeyEvent.ACTION_DOWN && event.repeatCount == 3) {
                    heldPlay = true
                    val server = state.server; val userId = state.session?.userId
                    if (server != null && userId != null) lifecycleScope.launch {
                        runCatching { server.shuffleFrom(userId, target) }.getOrNull()?.let { state.push(Screen.Player(it.id, 0.0)) }
                    }
                }
                if (event.action == android.view.KeyEvent.ACTION_UP) {
                    // Pressed twice quickly on Home: the first Up Next title, wherever the remote is.
                    val top = state.upNextTop
                    if (!heldPlay && state.top == Screen.Home && top != null && event.eventTime - lastPlay < 450) {
                        pendingPlay?.let { handler.removeCallbacks(it) }; pendingPlay = null; lastPlay = 0
                        state.push(Screen.Player(top.id, null))
                    } else if (!heldPlay && state.top == Screen.Home && top != null) {
                        lastPlay = event.eventTime
                        pendingPlay = Runnable { pendingPlay = null; state.push(Screen.Player(target.id, null)) }.also { handler.postDelayed(it, 450) }
                    } else if (!heldPlay) state.push(Screen.Player(target.id, null))
                    heldPlay = false
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchTouchEvent(ev: android.view.MotionEvent): Boolean {
        app.lumiere.android.ui.Idle.poke()
        return super.dispatchTouchEvent(ev)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        if (!::state.isInitialized) return
        // Opened again from the home screen while a TV-layout preview was up:
        // back to the phone's own layout. The preview is a one-off for
        // checking TV screens on a phone, never where the app stays.
        if (this.intent?.getBooleanExtra("tv", false) == true && !intent.getBooleanExtra("tv", false)) {
            setIntent(intent)
            requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            recreate()
            return
        }
        openFrom(intent)
    }

    /** A title from the widget or the TV's Play Next row. */
    private fun openFrom(intent: android.content.Intent?) {
        val id = intent?.getStringExtra("item") ?: intent?.data?.getQueryParameter("item") ?: return
        if (state.session == null) return
        state.tab(Screen.Home)
        state.push(Screen.Detail(id))
    }

    /** Leaving mid-film keeps it going in a small window, on a phone. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!::state.isInitialized) return
        val playing = app.lumiere.android.player.PictureInPicture.player?.isPlaying == true
        if (playing && !app.lumiere.android.ui.detectFormFactor(this).isTv && !(state.roomOpen)) {
            app.lumiere.android.player.PictureInPicture.enter(this)
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, config: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        if (!::state.isInitialized) return
        app.lumiere.android.player.PictureInPicture.inPip = inPip
    }

    @Deprecated("Only the pre-Android 9 room unlock uses it")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (!::state.isInitialized) return
        if (requestCode == Room.CONFIRM_REQUEST) Room.confirmed(resultCode == RESULT_OK)
    }
}

@Composable
private fun App(state: AppState, onExit: () -> Unit) {
    val server = state.server
    if (state.session == null || server == null) {
        SignInScreen(state)
        return
    }
    val context = LocalContext.current
    // A server with no libraries yet: the guide, once.
    androidx.compose.runtime.LaunchedEffect(state.session) {
        if (state.settings.setupDone) return@LaunchedEffect
        val libs = runCatching { server.libraries() }.getOrNull() ?: return@LaunchedEffect
        if (libs.isEmpty()) state.push(Screen.Setup) else state.settings.setupDone = true
    }
    // Images are behind sign-in like everything else, so the loader shares
    // the signed-in client and its header.
    val tv = app.lumiere.android.ui.detectFormFactor(context).isTv
    // On a 2 GB TV: a smaller memory cache, half-size pixels for posters, no
    // fade per image — the cost that made rows stutter while scrolling.
    val images = remember(server) {
        ImageLoader.Builder(context).okHttpClient(server.http)
            .crossfade(!tv)
            .allowRgb565(tv)
            // A fixed budget on a low-memory device — about sixty posters — rather
            // than a share of a heap that is small to begin with.
            .memoryCache {
                coil.memory.MemoryCache.Builder(context).apply {
                    if (app.lumiere.android.Device.lowMemory) maxSizeBytes(32 * 1024 * 1024) else maxSizePercent(if (tv) 0.15 else 0.25)
                }.build()
            }
            .diskCache { coil.disk.DiskCache.Builder().directory(context.cacheDir.resolve("images")).maxSizeBytes(250L shl 20).build() }
            .build()
            .also { loader -> Diagnostics.imageCacheMb = { (loader.memoryCache?.size ?: 0) / 1_048_576L } }
    }
    // Bumped whenever a screen comes back into view, so it reloads: a title
    // just watched has moved on by the time Back returns to Home.
    var refresh by remember { mutableIntStateOf(0) }
    val depth = state.stack.size
    LaunchedEffect(depth) { refresh++ }

    // Back goes back; at Home on a TV it first shows the menu; at the very
    // end it asks before leaving, rather than closing on one press too many.
    val tvForm = LocalFormFactor.current.isTv
    state.isTv = tvForm
    // The launch window's icon has done its job once the first frame is drawn; a plain
    // ground behind everything after that costs the projector nothing to redraw.
    val bootWindow = LocalContext.current as? android.app.Activity
    LaunchedEffect(Unit) {
        androidx.compose.runtime.withFrameNanos { }
        bootWindow?.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.BLACK))
        bootWindow?.let { CrashGuard.started(it) }
    }
    // The phone as remote: listening only on a TV, only when allowed in Settings.
    val activity = LocalContext.current as? android.app.Activity
    LaunchedEffect(tvForm, state.settings.phoneRemote, state.session?.token) {
        val ctx = activity ?: return@LaunchedEffect
        if (!tvForm || !state.settings.phoneRemote || state.session == null) { app.lumiere.android.remote.RemoteHost.stop(ctx); return@LaunchedEffect }
        app.lumiere.android.remote.RemoteHost.actions = app.lumiere.android.remote.RemoteHost.Actions(
            key = { k -> remoteKey(ctx, state, k) },
            play = { id, start ->
                // Never opens a private title outside the room, whoever asks.
                val server = state.server; val uid = state.session?.userId
                if (server != null && uid != null) kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
                    val it = runCatching { server.item(uid, id) }.getOrNull() ?: return@launch
                    if (!state.hides(it.libraryId)) state.push(Screen.Player(id, start))
                }
            },
        )
        app.lumiere.android.remote.RemoteHost.start(ctx, "Lumiere on ${android.os.Build.MODEL}")
    }
    app.lumiere.android.ui.TvLook.on = tvForm
    // A crash last time: its report goes to the Mac by itself, once the Mac answers.
    LaunchedEffect(state.server) {
        val ctx = bootWindow ?: return@LaunchedEffect
        val server = state.server ?: return@LaunchedEffect
        CrashGuard.takeCrash(ctx)?.let { crash -> Diagnostics.note(crash); if (!Diagnostics.send(server)) Diagnostics.note("(crash report not sent)") }
    }
    app.lumiere.android.Diagnostics.privacy = {
        "private libraries ${if (state.privacyKnown) state.privateLibraries.size.toString() else "not yet known"}" +
            " (${if (state.settings.privateFollowsMac) "from the Mac" else "set here"}), room ${if (state.roomOpen) "open" else "shut"}"
    }
    // Shared preferences: taken from the server once signed in, sent back a
    // moment after any change here, so the projector and phone agree.
    val syncScope = androidx.compose.runtime.rememberCoroutineScope()
    LaunchedEffect(server) {
        server.clientSettings()?.let { state.settings.importShared(it) }
        var pending: kotlinx.coroutines.Job? = null
        state.settings.watchShared {
            pending?.cancel()
            pending = syncScope.launch {
                kotlinx.coroutines.delay(1500)
                server.saveClientSettings(state.settings.exportShared())
            }
        }
    }

    BackHandler {
        when {
            state.pop() -> Unit
            tvForm && !state.tvMenuOpen -> state.tvMenuOpen = true
            else -> state.confirmExit = true
        }
    }

    @Suppress("DEPRECATION")
    CompositionLocalProvider(LocalImageLoader provides images) {
      androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) {
      val calm = if (LocalFormFactor.current.isTv) app.lumiere.android.ui.CalmScroll else androidx.compose.foundation.gestures.LocalBringIntoViewSpec.current
      CompositionLocalProvider(app.lumiere.android.ui.LocalCardMenu provides
          if (LocalFormFactor.current.isTv) ({ item: app.lumiere.android.api.Item -> state.actionsFor = item }) else null,
          androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides calm) {
        Shell(state) { screen ->
            when (screen) {
                Screen.Home -> HomeScreen(state, refresh + state.homeRefresh)
                is Screen.Library -> LibraryScreen(state, screen.view)
                is Screen.Detail -> if (LocalFormFactor.current.isTv) app.lumiere.android.tv.TvDetailScreen(state, screen.id, refresh, screen.seasonId)
                    else DetailScreen(state, screen.id, refresh)
                // Keyed by episode: the next one gets its own video view. Reusing
                // the last one left the new film playing to a view whose player
                // was gone — sound only, over the old episode's last frame.
                is Screen.Player -> androidx.compose.runtime.key(screen.id) { PlayerScreen(state, screen.id, screen.startSeconds) }
                Screen.Search -> if (LocalFormFactor.current.isTv) app.lumiere.android.tv.TvSearchScreen(state) else SearchScreen(state)
                Screen.Settings -> if (LocalFormFactor.current.isTv) app.lumiere.android.tv.TvSettingsScreen(state) else app.lumiere.android.ui.SettingsScreen(state)
                Screen.Downloads -> app.lumiere.android.downloads.DownloadsScreen(state)
                is Screen.Music -> app.lumiere.android.music.MusicScreen(state, screen.view)
                is Screen.Album -> app.lumiere.android.music.AlbumScreen(state, screen.id)
                is Screen.Artist -> app.lumiere.android.music.ArtistScreen(state, screen.artist, screen.libraryId)
                Screen.NowPlaying -> if (LocalFormFactor.current.isTv) app.lumiere.android.tv.TvNowPlayingScreen(state)
                    else app.lumiere.android.music.NowPlayingScreen(state)
                is Screen.Edit -> app.lumiere.android.ui.EditScreen(state, screen.id)
                Screen.Favourites -> app.lumiere.android.ui.FavouritesScreen(state)
                Screen.Collections -> app.lumiere.android.ui.CollectionsScreen(state)
                Screen.Playlists -> app.lumiere.android.ui.PlaylistsScreen(state)
                is Screen.Playlist -> app.lumiere.android.ui.PlaylistScreen(state, screen.id, screen.name)
                is Screen.Person -> if (tvForm) app.lumiere.android.tv.TvPersonScreen(state, screen.id, screen.name) else app.lumiere.android.ui.PersonScreen(state, screen.id, screen.name)
                is Screen.Genre -> app.lumiere.android.tv.GenreScreen(state, screen.name)
                Screen.DiagnosticsView -> app.lumiere.android.tv.DiagnosticsScreen(state)
                Screen.TvLibrary -> app.lumiere.android.tv.TvLibraryScreen(state)
                Screen.Setup -> app.lumiere.android.ui.SetupScreen(state)
            }
        }
      }
        if (state.top !is Screen.Player) app.lumiere.android.ui.Screensaver(state, state.saverPool)
        app.lumiere.android.tv.TvActions(state)
        // The menu closed: the remote goes back to the card it was opened on,
        // not to the top of the page.
        androidx.compose.runtime.LaunchedEffect(state.actionsFor == null) {
            if (state.actionsFor == null) app.lumiere.android.ui.MenuReturn.to?.let { r ->
                repeat(4) { kotlinx.coroutines.delay(120); if (runCatching { r.requestFocus() }.isSuccess) return@LaunchedEffect }
            }
        }
        app.lumiere.android.tv.QuickToggles(state)
        // A phone asking to pair: the code it must send, large enough to read from the sofa.
        app.lumiere.android.remote.RemoteHost.code?.let { code ->
            androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.TopEnd) {
                androidx.compose.foundation.layout.Column(androidx.compose.ui.Modifier.padding(36.dp).background(
                    androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.82f), androidx.compose.foundation.shape.RoundedCornerShape(18.dp))
                    .padding(horizontal = 24.dp, vertical = 16.dp)) {
                    androidx.compose.material3.Text("Pair your phone", color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.75f))
                    androidx.compose.material3.Text(code.toCharArray().joinToString("  "), color = androidx.compose.ui.graphics.Color.White,
                        fontSize = 40.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
                    androidx.compose.material3.Text("Enter this code in Lumiere on your phone", color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.6f))
                }
            }
        }
        // Confirmations slide in at the bottom left, as tvOS shows them, and go after five seconds.
        state.undo?.let { (label, action) -> androidx.compose.runtime.LaunchedEffect(label, action) { kotlinx.coroutines.delay(5_000); state.undo = null } }
        val lastNotice = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("") }
        state.undo?.let { lastNotice.value = it.first }
        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.BottomStart) {
            androidx.compose.animation.AnimatedVisibility(state.undo != null,
                enter = androidx.compose.animation.slideInHorizontally { -it } + androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.slideOutHorizontally { -it } + androidx.compose.animation.fadeOut()) {
                androidx.compose.foundation.layout.Row(androidx.compose.ui.Modifier.padding(start = 48.dp, bottom = 36.dp)
                    .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.78f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                    .padding(horizontal = 18.dp, vertical = 10.dp),
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)) {
                    androidx.compose.material3.Text(lastNotice.value, color = androidx.compose.ui.graphics.Color.White)
                    androidx.compose.material3.Text("Menu to undo", color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.6f))
                }
            }
        }
        if (state.confirmExit) app.lumiere.android.ui.ExitDialog(onStay = { state.confirmExit = false; state.tvMenuOpen = false }, onLeave = onExit)
        state.pinFor?.let { action ->
            app.lumiere.android.ui.PinPad("Enter this device's PIN", onDone = { pin ->
                if (pin == state.settings.devicePin) { state.pinOpen = true; state.pinFor = null; action() }
            }, onCancel = { state.pinFor = null })
        }
      }
    }
}

/** A key from the phone, as if pressed on the TV's own remote. */
private fun remoteKey(activity: android.app.Activity, state: AppState, key: String) {
    val audio = activity.getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
    when (key) {
        "home" -> { state.tvMenuOpen = false; state.tab(Screen.Home) }
        "volup" -> audio.adjustStreamVolume(android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.ADJUST_RAISE, android.media.AudioManager.FLAG_SHOW_UI)
        "voldown" -> audio.adjustStreamVolume(android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.ADJUST_LOWER, android.media.AudioManager.FLAG_SHOW_UI)
        "mute" -> audio.adjustStreamVolume(android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.ADJUST_TOGGLE_MUTE, android.media.AudioManager.FLAG_SHOW_UI)
        else -> {
            val code = when (key) {
                "up" -> android.view.KeyEvent.KEYCODE_DPAD_UP; "down" -> android.view.KeyEvent.KEYCODE_DPAD_DOWN
                "left" -> android.view.KeyEvent.KEYCODE_DPAD_LEFT; "right" -> android.view.KeyEvent.KEYCODE_DPAD_RIGHT
                "ok" -> android.view.KeyEvent.KEYCODE_DPAD_CENTER; "back" -> android.view.KeyEvent.KEYCODE_BACK
                "menu" -> android.view.KeyEvent.KEYCODE_MENU; "playpause" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                else -> return
            }
            val now = android.os.SystemClock.uptimeMillis()
            activity.dispatchKeyEvent(android.view.KeyEvent(now, now, android.view.KeyEvent.ACTION_DOWN, code, 0))
            activity.dispatchKeyEvent(android.view.KeyEvent(now, now + 40, android.view.KeyEvent.ACTION_UP, code, 0))
        }
    }
}

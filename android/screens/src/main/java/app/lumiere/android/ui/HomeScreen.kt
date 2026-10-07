package app.lumiere.android.ui

import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.openRoom
import app.lumiere.android.api.privateLibraries
import app.lumiere.android.api.Item
import app.lumiere.android.api.watchedLately
import androidx.compose.foundation.layout.Column
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

internal data class HomeRows(
    val resume: List<Item>,
    val nextUp: List<Item>,
    val views: List<Item>,
    val latest: List<Pair<Item, List<Item>>>,
    val watched: List<Item> = emptyList(),
)

/**
 * Continue Watching, Next Up, the libraries, then what is new in each — the
 * Mac app's Home, in the same order. Reloaded each time it comes back into
 * view, so an episode just finished has moved on.
 */
@Composable
fun HomeScreen(state: AppState, refreshKey: Int) {
    val server = state.server ?: return
    val session = state.session ?: return
    val form = LocalFormFactor.current
    val context = androidx.compose.ui.platform.LocalContext.current
    var rows by remember { mutableStateOf<HomeRows?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(refreshKey, state.roomOpen, attempt) {
        // The saved Home first, drawn at once, then the live one over it.
        if (rows == null) runCatching {
            kotlinx.coroutines.withContext(app.lumiere.android.api.CacheOnly) {
                coroutineScope {
                    val all = server.views(session.userId)
                    val views = all.filter { it.collectionType != "boxsets" && it.collectionType != "playlists" }
                    val latest = views.filter { it.collectionType != "music" }
                        .map { v -> async { v to runCatching { server.latest(session.userId, v.id) }.getOrDefault(emptyList()) } }
                    HomeRows(server.resume(session.userId), runCatching { server.nextUp(session.userId) }.getOrDefault(emptyList()),
                        views, latest.map { it.await() }, runCatching { server.watchedLately(session.userId) }.getOrDefault(emptyList()))
                        .also { if (state.views.isEmpty()) state.views = all }
                }
            }
        }.onSuccess { if (rows == null) rows = it }
        // The Mac pauses for a minute or two while it re-imports Jellyfin, so
        // a failure is retried quietly for a while before Home says it's offline.
        var tries = 0
        while (true) {
        val result = runCatching {
            coroutineScope {
                val resume = async { server.resume(session.userId) }
                val watched = async { runCatching { server.watchedLately(session.userId) }.getOrDefault(emptyList()) }
                val next = async { server.nextUp(session.userId) }
                runCatching { server.privateLibraries() }.onSuccess { state.macPrivate = it }
                val all = server.views(session.userId)
                state.views = all
                val views = all.filter { it.collectionType != "boxsets" && it.collectionType != "playlists" }
                val latest = views.filter { it.collectionType != "music" }
                    .map { v -> async { v to runCatching { server.latest(session.userId, v.id) }
                    .getOrDefault(emptyList()) } }
                HomeRows(resume.await(), next.await(), views, latest.map { it.await() }, watched.await())
            }
        }.onSuccess {
            rows = it; error = null
            if (form.isTv) app.lumiere.android.tv.Wake.learn(server)?.let { a -> state.settings.wakeAddress = a }
            state.saverPool = it.latest.flatMap { l -> l.second }
            // Outside the room only, and only what is not private.
            if (!state.roomOpen) {
                val public = it.resume.filter { r -> r.libraryId != null && r.libraryId !in state.privateLibraries }
                app.lumiere.android.widget.ResumeWidget.update(context)
                if (form.isTv) app.lumiere.android.tv.WatchNext.publish(context, server, public)
            }
        }
            .onFailure { if (tries >= 2) error = it.message ?: "Couldn't reach the server." }
        if (result.isSuccess || ++tries > 12) break
        kotlinx.coroutines.delay(15_000)
        }
    }

    var extras by remember { mutableStateOf(PhoneExtras()) }
    LaunchedEffect(rows?.views?.map { it.id }, state.roomOpen) {
        val views = rows?.views ?: return@LaunchedEffect
        if (!form.isTv) extras = runCatching { loadPhoneExtras(state, state.visibleViews(views)) }.getOrDefault(PhoneExtras())
    }

    val open: (Item) -> Unit = { item ->
        if (item.isPlayable && item.positionTicks > 0) {
            state.push(Screen.Player(item.id, null))
        } else {
            state.push(Screen.Detail(item.id))
        }
    }

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        val current = rows
        when {
            // On a TV, a quiet name on the dark while the first Home arrives, not grey blocks.
            // The app's icon, where the launch window put it, until Home is ready.
            current == null && error == null && form.isTv -> androidx.compose.foundation.Image(
                androidx.compose.ui.res.painterResource(app.lumiere.android.screens.R.drawable.boot_icon), "Lumiere",
                modifier = Modifier.align(Alignment.Center).size(144.dp))
            current == null && error == null -> Column { repeat(3) { SkeletonShelf() } }
            current == null && form.isTv -> app.lumiere.android.tv.OfflineHome(state, error!!) { attempt++ }
            current == null -> Text(error!!, style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.align(Alignment.Center).padding(24.dp))
            // Started afresh when the room opens or closes, so nothing private —
            // a backdrop, a selection — carries across.
            form.isTv -> androidx.compose.runtime.key(state.roomOpen) { TvHome(state, current.toTv(state), open) }
            else -> LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                item {
                    val pool = current.latest.filter { !state.hides(it.first.id) }.flatMap { it.second }
                        .filter { it.backdropTag != null }
                    Featured(state, pool)
                }
                item { Shelf("Continue Watching", state.visible(current.resume), server, CardShape.Wide, onOpen = open) }
                item { Shelf("Next Up", state.visible(current.nextUp), server, CardShape.Wide, onOpen = open) }
                item { PhoneLibraries(state.visibleViews(current.views), extras, state) }
                item { Shelf("Watched Lately", state.visible(current.watched), server, CardShape.Wide, onOpen = open) }
                current.latest.filter { !state.hides(it.first.id) }.forEach { (view, items) ->
                    item(key = "latest-${view.id}") {
                        Shelf("Recently Added in ${view.name}", items, server, CardShape.Poster, onOpen = open)
                    }
                }
                phoneTopTens(state, extras, open)
                phoneGenres(state, extras)
            }
        }
        // The saved Home stays up while the Mac is away; a quiet pill says so,
        // and goes once it answers again.
        if (rows != null && error != null) Text("Reconnecting to the Mac…", style = MaterialTheme.typography.labelLarge,
            color = Palette.textPrimary, modifier = Modifier.align(Alignment.TopCenter).padding(top = 14.dp)
                .background(Palette.surfaceRaised.copy(alpha = 0.9f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                .padding(horizontal = 16.dp, vertical = 8.dp))
    }
}

/** In and out of the private room; shown only once a library has been made private. */
@Composable
internal fun RoomButton(state: AppState) {
    if (state.privateLibraries.isEmpty()) return
    val activity = androidx.compose.ui.platform.LocalContext.current as? android.app.Activity ?: return
    LIconButton(onClick = { toggleRoom(state, activity) }) {
        Icon(if (state.roomOpen) Icons.Default.LockOpen else Icons.Default.Lock,
            if (state.roomOpen) "Leave the private room" else "Private room",
            tint = if (state.roomOpen) Palette.accent else Palette.textSecondary)
    }
}

/** Into the room — behind the device's lock or the app's PIN — or out of it. */
internal fun toggleRoom(state: AppState, activity: android.app.Activity) {
        when {
            state.roomOpen -> state.closeRoom()
            !state.settings.roomRequiresUnlock -> state.openRoom()
            // A device with no screen lock of its own — the projector — asks
            // for the app's PIN instead, when one is set.
            state.settings.devicePin.isNotEmpty() &&
                !(activity.getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager).isDeviceSecure ->
                state.guarded { state.openRoom() }
            else -> app.lumiere.android.Room.unlock(activity) { ok -> if (ok) state.openRoom() }
        }
}

/** Home's rows in TV order, with private ones already taken out. */
private fun HomeRows.toTv(state: AppState): TvRows = TvRows(
    shelves = listOf(
        "Continue Watching" to state.visible(resume),
        "Next Up" to state.visible(nextUp),
        "Watched Lately" to state.visible(watched),
    ) + latest.filter { !state.hides(it.first.id) }.map { (v, items) -> "Recently Added in ${v.name}" to
        items.filter { it.id !in state.settings.notInterested && it.seriesId !in state.settings.notInterested } },
    libraries = state.visibleViews(views),
)

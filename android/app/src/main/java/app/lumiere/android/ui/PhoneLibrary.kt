package app.lumiere.android.ui

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Animation
import androidx.compose.material.icons.filled.CollectionsBookmark
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SettingsRemote
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.libraryPage

/**
 * The phone's Library tab, as the Apple TV app's on an iPhone: the libraries
 * as a grouped list with coloured tiles, then Favourites, Collections,
 * Playlists and Downloaded, then the remote and Settings; under them, what
 * arrived most recently.
 */
@Composable
fun PhoneLibraryScreen(state: AppState) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    val views = state.visibleViews(state.views).filter { it.collectionType != "boxsets" && it.collectionType != "playlists" }
    var recent by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(views.map { it.id }, state.roomOpen) {
        recent = runCatching { server.libraryPage(userId, null, 0, 30, "DateCreated", true, types = "Movie,Series") }
            .getOrDefault(emptyList()).let(state::visible)
            .filter { it.id !in state.settings.notInterested }.take(18)
    }
    val downloads = state.downloads.all.count { !state.hides(it.item.libraryId) }
    val across = phoneColumns()

    val list = androidx.compose.foundation.lazy.rememberLazyListState()
    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 40.dp)) {
        item {
            IosLargeTitle("Library") {
                IosAvatar(state.session?.userName ?: "") { state.guarded { state.push(Screen.Settings) } }
            }
        }
        item {
            IosGroup(views.map { v ->
                val (icon, tile) = libraryLook(v)
                IosRow(v.name, icon, tile) { state.push(if (v.collectionType == "music") Screen.Music(v) else Screen.Library(v)) }
            }, Modifier.padding(top = 8.dp))
        }
        item {
            IosGroup(listOf(
                IosRow("Favourites", Icons.Default.Star, Color(0xFFFF9F0A)) { state.push(Screen.Favourites) },
                IosRow("Collections", Icons.Default.CollectionsBookmark, Color(0xFF30B0C7)) { state.push(Screen.Collections) },
                IosRow("Playlists", Icons.AutoMirrored.Filled.PlaylistPlay, Color(0xFF5E5CE6)) { state.push(Screen.Playlists) },
                IosRow("On This Phone", Icons.Default.PhoneAndroid, Color(0xFF64D2FF)) { state.push(Screen.OnThisPhone) },
                IosRow("Downloaded", Icons.Default.Download, Color(0xFF30D158), value = downloads.takeIf { it > 0 }?.toString()) {
                    state.push(Screen.Downloads)
                },
            ), Modifier.padding(top = 22.dp))
        }
        item {
            IosGroup(listOfNotNull(
                // The remote is the phone's alone: the Quest's app has none.
                if (app.lumiere.android.Flavor.isRemote) IosRow("TV Remote", Icons.Default.SettingsRemote, Color(0xFF636366),
                    value = app.lumiere.android.remote.RemoteClient.lastTv(context)?.removePrefix("Lumiere on ")) { state.push(Screen.Remote) } else null,
                IosRow("Settings", Icons.Default.Settings, Color(0xFF8E8E93)) { state.guarded { state.push(Screen.Settings) } },
            ), Modifier.padding(top = 22.dp))
        }
        if (recent.isNotEmpty()) {
            item { Spacer(Modifier.height(26.dp)); IosSectionHeader("Recently Added") ; Spacer(Modifier.height(10.dp)) }
            recent.chunked(across).forEachIndexed { i, row ->
                item(key = "recent-$i") {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { item ->
                            Box(Modifier.weight(1f)) { ItemCard(item, server, CardShape.Poster, fill = true) { state.push(Screen.Detail(item.id)) } }
                        }
                        repeat(across - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
    IosCollapsedTitle(list, "Library")
    }
}

/** A library's icon and tile colour, by what it holds. */
private fun libraryLook(view: Item) = when {
    view.name.contains("anime", true) -> Icons.Default.Animation to Color(0xFFFF9F0A)
    view.collectionType == "movies" -> Icons.Default.Movie to Color(0xFF0A84FF)
    view.collectionType == "tvshows" -> Icons.Default.Tv to Color(0xFFBF5AF2)
    view.collectionType == "music" -> Icons.Default.MusicNote to Color(0xFFFF375F)
    else -> Icons.Default.Folder to Color(0xFF64D2FF)
}

/** A genre on the phone: its films and shows, best rated first. */
@Composable
fun PhoneGenreScreen(state: AppState, name: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    GridScreen(state, name, "Nothing in $name yet.") {
        server.libraryPage(userId, null, 0, 300, "CommunityRating,SortName", true, genre = name, types = "Movie,Series")
    }
}

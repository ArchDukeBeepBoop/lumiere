package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.onPreviewKeyEvent
import kotlinx.coroutines.launch
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.is3D
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage

/**
 * A library kept as folders on disk — 3D, My Videos — browsed as folders:
 * the path across the top as pills to step back along, then the folders,
 * then the videos in this one, each playing at once. Back climbs a level.
 */
@Composable
fun TvFolderBrowser(state: AppState, view: Item) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val path = remember(view.id) { mutableStateListOf(view.id to view.name) }
    var entries by remember { mutableStateOf<List<Item>?>(null) }
    val here = path.last().first
    LaunchedEffect(here) {
        entries = null
        entries = state.visible(runCatching { server.children(userId, here) }.getOrDefault(emptyList()))
            // Subtitle folders hold no videos to browse; their files are offered with the video instead.
            .filter { !(it.isFolder && it.name.lowercase() in setOf("subs", "subtitles", "sub")) }
    }
    var byDate by remember { mutableStateOf(false) }
    val sorted = entries?.sortedWith(if (byDate) compareBy<Item>({ !it.isFolder }).thenByDescending { it.dateCreated ?: "" }
        else compareBy({ !it.isFolder }, { it.name.lowercase() }))
    val videos = sorted.orEmpty().filter { !it.isFolder && it.isPlayable }
    // A number key or a letter typed on the remote jumps to the first entry starting with it.
    val grid = androidx.compose.foundation.lazy.grid.rememberLazyGridState()
    val jump = androidx.compose.runtime.rememberCoroutineScope()
    if (path.size > 1) androidx.activity.compose.BackHandler { path.removeAt(path.lastIndex) }
    Column(Modifier.fillMaxSize().onPreviewKeyEvent { ev ->
        val k = ev.nativeKeyEvent
        val ch = k.unicodeChar.toChar()
        if (k.action != android.view.KeyEvent.ACTION_DOWN || !ch.isLetterOrDigit()) return@onPreviewKeyEvent false
        val at = sorted.orEmpty().indexOfFirst { it.name.startsWith(ch, ignoreCase = true) }
        if (at >= 0) jump.launch { grid.scrollToItem(at) }
        at >= 0
    }) {
        Row(Modifier.padding(start = 56.dp, top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            TvPill({ byDate = !byDate }, selected = true) { Text(if (byDate) "↕ Newest" else "↕ A–Z") }
            if (videos.isNotEmpty()) TvPill({ app.lumiere.android.player.Playback.queue = videos; state.push(Screen.Player(videos.first().id, 0.0)) }) {
                Text("▶  Play All (${videos.size})")
            }
            Spacer(Modifier.size(12.dp))
            path.forEachIndexed { i, (_, name) ->
                if (i > 0) Text("›", color = Palette.textMuted)
                TvPill({ while (path.size > i + 1) path.removeAt(path.lastIndex) }, selected = i == path.lastIndex) {
                    Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        val list = sorted
        when {
            list == null -> Unit
            list.isEmpty() -> Text("This folder is empty.", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(48.dp))
            else -> LazyVerticalGrid(GridCells.Adaptive(240.dp), state = grid, contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 10.dp, bottom = 48.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                items(list, key = { it.id }) { e ->
                    Column {
                        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)
                            .focusCard({}, { if (e.isFolder) path += e.id to e.name else state.push(Screen.Player(e.id, null)) }) { state.actionsFor = e }
                            .background(Palette.surface), contentAlignment = Alignment.Center) {
                            val pic = imageFor(e, server, CardShape.Wide, 480)
                            if (pic != null) AsyncImage(pic, e.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            if (!e.isFolder && state.is3D(e)) Text("3D", style = MaterialTheme.typography.labelMedium, color = androidx.compose.ui.graphics.Color.White,
                                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.65f),
                                    androidx.compose.foundation.shape.RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp))
                            else if (e.isFolder) Icon(Icons.Default.Folder, null, tint = Palette.textSecondary, modifier = Modifier.size(56.dp))
                            if (!e.isFolder) app.lumiere.android.ui.WatchedMark(e, Modifier.align(Alignment.TopEnd))
                            e.progress?.let { p ->
                                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(p).height(4.dp).background(Palette.accent))
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (e.isFolder) Icon(Icons.Default.Folder, null, tint = Palette.textSecondary, modifier = Modifier.size(16.dp).padding(end = 4.dp))
                            Text(e.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                        }
                        e.childCount?.takeIf { e.isFolder }?.let { Text("$it items", style = MaterialTheme.typography.labelMedium) }
                    }
                }
            }
        }
    }
}

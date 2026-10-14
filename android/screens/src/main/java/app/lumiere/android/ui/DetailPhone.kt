@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.itemJson
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/**
 * The hero on a phone moves at half the page's speed and fades as it goes,
 * so the title page gathers itself under the thumb.
 */
internal fun Modifier.collapsing(list: LazyListState): Modifier = graphicsLayer {
    if (list.firstVisibleItemIndex == 0) {
        val y = list.firstVisibleItemScrollOffset.toFloat()
        // Reduce motion: the hero scrolls with the page, only fading.
        if (!app.lumiere.android.Motion.reduced) translationY = y * 0.5f
        alpha = (1f - y / size.height.coerceAtLeast(1f) * 1.2f).coerceIn(0f, 1f)
    } else alpha = 0f
}

/** The title's name in a bar along the top once its hero has scrolled away. */
@Composable
internal fun CollapsedTitle(item: Item, list: LazyListState) {
    val shown by remember { derivedStateOf { list.firstVisibleItemIndex > 0 } }
    if (!shown) return
    Box(Modifier.fillMaxWidth().background(Palette.canvas.copy(alpha = 0.95f))
        .padding(horizontal = LocalFormFactor.current.gutter.dp, vertical = 12.dp)) {
        Text(item.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The season tabs, solid behind so they read when they stick to the top; with [title] once the hero has gone. */
@Composable
internal fun SeasonTabs(seasons: List<Item>, season: Item?, title: String? = null, onPick: (Item) -> Unit) {
    val form = LocalFormFactor.current
    Column(Modifier.fillMaxWidth().background(Palette.canvas)) {
        title?.let {
            Text(it, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = form.gutter.dp, end = form.gutter.dp, top = 12.dp))
        }
        LazyRow(
            Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(seasons, key = { it.id }) { s -> LChip(selected = s.id == season?.id, onClick = { onPick(s) }, label = { Text(s.name) }) }
        }
    }
}

/** An episode on a phone: a tap plays it, a long press offers Mark Watched and Download. */
@Composable
internal fun PhoneEpisodeRow(episode: Item, state: AppState, onPlayed: (Boolean) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    val saved = state.downloads.find(episode.id)
    Box {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(onLongClick = { menu = true }) { state.push(Screen.Player(episode.id, null)) }
                .padding(horizontal = LocalFormFactor.current.gutter.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(Modifier.width(150.dp).aspectRatio(16f / 9f).background(Palette.surface, MaterialTheme.shapes.small)) {
                AsyncImage(imageFor(episode, server, CardShape.Wide, 480), episode.name,
                    contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                episode.progress?.let { f ->
                    Box(Modifier.align(androidx.compose.ui.Alignment.BottomStart).fillMaxWidth(f).aspectRatio(100f)
                        .background(Palette.accent))
                }
            }
            Column(Modifier.weight(1f)) {
                Text(listOfNotNull(episode.indexNumber?.let { "$it." }, episode.name).joinToString(" "),
                    style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(episode.runtimeTicks?.let { "${it / TICKS_PER_SECOND / 60} min" },
                    "Watched".takeIf { episode.played }, "Downloaded".takeIf { saved != null }).joinToString("  ·  "),
                    style = MaterialTheme.typography.labelMedium)
                episode.overview?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(if (episode.played) "Mark Unwatched" else "Mark Watched") },
                onClick = { menu = false; onPlayed(!episode.played) })
            DropdownMenuItem(text = { Text(if (saved != null) "Show in Downloads" else "Download") }, onClick = {
                menu = false
                if (saved != null) state.push(Screen.Downloads)
                else scope.launch {
                    runCatching { server.itemJson(userId, episode.id) }.onSuccess {
                        state.downloads.start(server, userId, it, state.settings.downloadsWifiOnly)
                    }
                }
            })
        }
    }
}

/** Saves every episode of the season not already on the phone, stopping at the downloads limit. */
@Composable
internal fun DownloadSeason(season: Item?, episodes: List<Item>, state: AppState) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    if (season == null || episodes.isEmpty()) return
    val missing = episodes.filter { state.downloads.find(it.id) == null }
    LTextButton(onClick = {
        if (missing.isEmpty()) state.push(Screen.Downloads)
        else scope.launch {
            for (e in missing) {
                val json = runCatching { server.itemJson(userId, e.id) }.getOrNull() ?: continue
                if (!state.downloads.start(server, userId, json, state.settings.downloadsWifiOnly)) break
            }
        }
    }, modifier = Modifier.padding(horizontal = LocalFormFactor.current.gutter.dp - 8.dp)) {
        Text(if (missing.isEmpty()) "${season.name} downloaded" else "Download ${season.name} (${missing.size})")
    }
}

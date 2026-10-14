package app.lumiere.android.music

import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.albums
import app.lumiere.android.api.artists
import app.lumiere.android.api.tracks
import app.lumiere.android.api.playlists
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import coil.compose.AsyncImage

private enum class Tab { Albums, Artists, Tracks, Playlists }

/** The Tracks tab's orders, the Mac's TrackSort: compound where it should be. */
enum class TrackOrder(val label: String, val sortBy: List<String>, val descending: Boolean) {
    Title("Title", listOf("SortName"), false),
    Artist("Artist", listOf("AlbumArtist", "Album", "ParentIndexNumber", "IndexNumber"), false),
    Album("Album", listOf("Album", "ParentIndexNumber", "IndexNumber"), false),
    Time("Time", listOf("Runtime"), true),
    Added("Date Added", listOf("DateCreated"), true),
    Plays("Plays", listOf("PlayCount"), true),
}

@Composable
fun MusicScreen(state: AppState, view: Item) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val form = LocalFormFactor.current
    val context = LocalContext.current
    var tab by remember { mutableStateOf(Tab.Albums) }
    var order by remember { mutableStateOf(TrackOrder.Title) }
    val rows = remember { mutableStateListOf<Item>() }
    var exhausted by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var generation by remember { mutableStateOf(0) }

    suspend fun more(gen: Int) {
        if (loading || exhausted) return
        loading = true
        val page = runCatching {
            when (tab) {
                Tab.Albums -> server.albums(userId, view.id, rows.size, 100)
                Tab.Artists -> server.artists(userId, view.id, rows.size, 100)
                Tab.Tracks -> server.tracks(userId, view.id, rows.size, 100, order.sortBy, order.descending)
                Tab.Playlists -> if (rows.isEmpty()) server.playlists(userId) else emptyList()
            }
        }.getOrDefault(emptyList())
        if (gen == generation) {
            rows += page
            exhausted = page.size < 100
        }
        loading = false
    }
    LaunchedEffect(tab, order) {
        generation++
        rows.clear(); exhausted = false; loading = false
        more(generation)
    }

    Column(Modifier.fillMaxSize().background(Palette.canvas)) {
        // On a TV the name and the tabs share one line, leaving the screen to the covers.
        if (!form.isTv) Text(view.name, style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(start = form.gutter.dp, top = 16.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = if (form.isTv) 16.dp else 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(Tab.entries) { t -> LChip(tab == t, { tab = t }, { Text(t.name) }) }
        }
        if (tab == Tab.Tracks) {
            LazyRow(contentPadding = PaddingValues(horizontal = form.gutter.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(TrackOrder.entries) { o -> LChip(order == o, { order = o }, { Text(o.label) }) }
            }
        }
        when (tab) {
            Tab.Tracks -> LazyColumn(contentPadding = PaddingValues(bottom = 96.dp)) {
                itemsIndexed(rows, key = { _, t -> t.id }) { i, track ->
                    if (i >= rows.size - 30) LaunchedEffect(rows.size) { more(generation) }
                    TrackRow(track, server, showArt = true) {
                        Music.play(context, server, rows.toList(), i, fromRoom = state.roomOpen)
                    }
                }
            }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(form.posterWidth.dp + 20.dp),
                contentPadding = PaddingValues(start = form.gutter.dp, end = form.gutter.dp, top = 8.dp, bottom = 96.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                itemsIndexed(rows, key = { _, a -> a.id }) { i, item ->
                    if (i >= rows.size - 30) LaunchedEffect(rows.size) { more(generation) }
                    SquareCard(item, server, round = tab == Tab.Artists) {
                        when (tab) {
                            Tab.Albums -> state.push(Screen.Album(item.id))
                            Tab.Playlists -> state.push(Screen.Playlist(item.id, item.name))
                            else -> state.push(Screen.Artist(item, view.id))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SquareCard(item: Item, server: Server, round: Boolean = false, onClick: () -> Unit) {
    Column {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).focusCard(onClick)
            .clip(if (round) RoundedCornerShape(50) else RoundedCornerShape(8.dp)).background(Palette.surface)) {
            AsyncImage(server.imageUrl(item.id, "Primary", item.primaryTag, 400), item.name,
                contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        }
        Spacer(Modifier.height(6.dp))
        Text(item.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        (item.albumArtist ?: item.year?.toString())?.let {
            Text(it, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun TrackRow(track: Item, server: Server, showArt: Boolean, onClick: () -> Unit) {
    val form = LocalFormFactor.current
    val playing = Music.current?.id == track.id
    Row(
        Modifier.fillMaxWidth().focusCard(onClick)
            .padding(horizontal = form.gutter.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showArt) {
            AsyncImage(server.imageUrl(track.albumId ?: track.id, "Primary", null, 120), null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(4.dp)).background(Palette.surface))
        } else {
            Text(track.indexNumber?.toString() ?: "", style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1,
                overflow = TextOverflow.Ellipsis, color = if (playing) Palette.accent else Palette.textPrimary)
            val by = track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" }
            Text(listOf(by, if (showArt) track.album ?: "" else "").filter { it.isNotEmpty() }.joinToString(" · "),
                style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        track.runtimeTicks?.let { Text(clock(it / TICKS_PER_SECOND.toDouble()), style = MaterialTheme.typography.labelMedium) }
    }
}

fun clock(seconds: Double): String {
    val s = seconds.toInt().coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

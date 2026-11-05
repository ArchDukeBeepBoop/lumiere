@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.music

import androidx.compose.ui.focus.onFocusChanged
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
import app.lumiere.android.api.musicGenres
import app.lumiere.android.api.playlists
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import coil.compose.AsyncImage

private enum class Tab { Albums, Artists, Genres, Tracks, Playlists }

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
    // The phone's and the Quest's: Apple Music's Library.
    if (!LocalFormFactor.current.isTv) { PhoneMusicScreen(state, view); return }
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
    var groups by remember { mutableStateOf<Map<String, ArtistGroup>>(emptyMap()) }

    suspend fun more(gen: Int) {
        if (loading || exhausted) return
        loading = true
        val page = runCatching {
            when (tab) {
                Tab.Albums -> server.albums(userId, view.id, rows.size, 100)
                // Every artist at once, so guests can be folded under the artist they joined.
                Tab.Artists -> if (rows.isEmpty()) ArtistGroups.group(server.artists(userId, view.id, 0, 5000))
                    .also { g -> groups = g.associateBy { it.item.id } }.map { it.item } else emptyList()
                Tab.Genres -> if (rows.isEmpty()) server.musicGenres(userId, view.id) else emptyList()
                Tab.Tracks -> server.tracks(userId, view.id, rows.size, 100, order.sortBy, order.descending)
                Tab.Playlists -> if (rows.isEmpty()) server.playlists(userId) else emptyList()
            }
        }.getOrDefault(emptyList())
        if (gen == generation) {
            rows += page
            exhausted = tab == Tab.Artists || tab == Tab.Genres || page.size < 100
        }
        loading = false
    }
    LaunchedEffect(tab, order) {
        generation++
        rows.clear(); exhausted = false; loading = false
        more(generation)
    }

    // Home's pattern: the tabs in one frosted capsule in a band that never moves; once the
    // covers are reached, the chosen one is told about over that band, never pushing the grid.
    var focusedItem by remember { mutableStateOf<Item?>(null) }
    var focusedIndex by remember { mutableStateOf<Int?>(null) }
    var holds by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf<Item?>(null) }
    val grid = androidx.compose.foundation.lazy.grid.rememberLazyGridState()
    val list = androidx.compose.foundation.lazy.rememberLazyListState()
    val inGrid = holds && tab != Tab.Tracks && grid.firstVisibleItemIndex >= 6
    LaunchedEffect(focusedItem, inGrid) { kotlinx.coroutines.delay(300); shown = if (inGrid) focusedItem else null }
    LaunchedEffect(tab) { focusedIndex = null }
    app.lumiere.android.ui.SteeredGrid(grid, focusedIndex.takeIf { tab != Tab.Tracks }, landing = 0.02f)
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize().background(Palette.ground)) {
    val band = maxHeight * app.lumiere.android.ui.TvSpace.strip
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().height(band).padding(start = 56.dp, end = 56.dp, bottom = 12.dp), verticalAlignment = Alignment.Bottom) {
            Text(view.name, style = app.lumiere.android.ui.TvType.title, modifier = Modifier.weight(1f))
            Row(Modifier.clip(RoundedCornerShape(50)).background(Palette.surface.copy(alpha = 0.72f)).padding(5.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                // A tab changes when pressed, not as the remote passes over it.
                Tab.entries.forEach { t -> app.lumiere.android.ui.TvPill({ tab = t }, selected = tab == t) { Text(t.name) } }
            }
        }
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides app.lumiere.android.ui.rememberSteeredPageScroll()) {
        Column(Modifier.fillMaxSize().onFocusChanged { holds = it.hasFocus }) {
        if (tab == Tab.Tracks) {
            LazyRow(contentPadding = PaddingValues(horizontal = 56.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(TrackOrder.entries) { o -> app.lumiere.android.ui.TvPill({ order = o }, selected = order == o) { Text(o.label) } }
            }
        }
        when (tab) {
            // A long list of songs moves only as far as needed, as Apple Music's does.
            Tab.Tracks -> androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides app.lumiere.android.ui.rememberCalmPageScroll()) {
                LazyColumn(state = list, contentPadding = PaddingValues(bottom = 96.dp)) {
                itemsIndexed(rows, key = { _, t -> t.id }) { i, track ->
                    if (i >= rows.size - 30) LaunchedEffect(rows.size) { more(generation) }
                    Box(Modifier.onFocusChanged { if (it.hasFocus) focusedIndex = i }) {
                        TrackRow(track, server, showArt = true) {
                            Music.play(context, server, rows.toList(), i, fromRoom = state.roomOpen)
                        }
                    }
                }
            }
            }
            else -> LazyVerticalGrid(
                // Genres are 16:9 cards, four across; covers and photos are square, six.
                columns = GridCells.Fixed(if (tab == Tab.Genres) 4 else 6), state = grid,
                contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 12.dp, bottom = 96.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // Top 10 Artists across the head of the Albums tab, as on the Mac. Grid index 0,
                // so every cover below sits one index on.
                val head = if (tab == Tab.Albums) 1 else 0
                if (head == 1) item(key = "top-artists", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                    TopArtistsRow(state, server, view.id) { focusedItem = null; focusedIndex = 0 }
                }
                itemsIndexed(rows, key = { _, a -> a.id }) { i, item ->
                    if (i >= rows.size - 30) LaunchedEffect(rows.size) { more(generation) }
                    Box(Modifier.onFocusChanged { if (it.hasFocus) { focusedItem = item; focusedIndex = i + head } }) {
                        val g = if (tab == Tab.Artists) groups[item.id] else null
                        if (tab == Tab.Genres) GenreCard(item, server) { state.push(Screen.MusicGenre(item.name, view.id)) }
                        else if (g != null) ArtistCard(g, server) { state.push(Screen.Artist(g.item, view.id, g.ids, g.imageId, g.imageTag)) }
                        else SquareCard(item, server, round = tab == Tab.Artists) {
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
        }
    }
    app.lumiere.android.ui.StripOverlay(shown, server, shown != null, Modifier.fillMaxWidth().height(band))
    }
}

/** An artist in the grid: their photo, or a member's, or an album cover; their initials when there is none. */
@Composable
fun ArtistCard(g: ArtistGroup, server: Server, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).focusCard(onClick).clip(RoundedCornerShape(50)).background(Palette.surface),
            contentAlignment = Alignment.Center) {
            Text(g.item.name.split(' ').mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString(""),
                style = app.lumiere.android.ui.TvType.title, color = Palette.textSecondary)
            g.imageId?.let { AsyncImage(server.imageUrl(it, "Primary", g.imageTag, 400), g.item.name,
                contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) }
        }
        Spacer(Modifier.height(6.dp))
        Text(g.item.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
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

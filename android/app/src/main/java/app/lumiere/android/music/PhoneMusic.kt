@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.music

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.albums
import app.lumiere.android.api.artists
import app.lumiere.android.api.playlists
import app.lumiere.android.api.setFavorite
import app.lumiere.android.api.tracks
import app.lumiere.android.ui.IosCaption
import app.lumiere.android.ui.IosChip
import app.lumiere.android.ui.IosCircle
import app.lumiere.android.ui.IosLargeTitle
import app.lumiere.android.ui.IosSegmented
import app.lumiere.android.ui.IosTintedButton
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.PhoneNotice
import app.lumiere.android.ui.iosClick
import app.lumiere.android.ui.phoneColumns
import app.lumiere.android.ui.pressScale
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

private val kinds = listOf("Albums", "Artists", "Songs", "Playlists")

/**
 * A music library on a phone, as Apple Music's Library: a large title, iOS's
 * segmented control, albums two across with their covers large, artists as a
 * list of round photos, songs with Play and Shuffle, playlists as covers.
 */
@Composable
fun PhoneMusicScreen(state: AppState, view: Item) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    var kind by remember { mutableStateOf(0) }
    var order by remember { mutableStateOf(TrackOrder.Title) }
    val rows = remember { mutableStateListOf<Item>() }
    var exhausted by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var generation by remember { mutableStateOf(0) }

    suspend fun more(gen: Int) {
        if (loading || exhausted) return
        loading = true
        val page = runCatching {
            when (kind) {
                0 -> server.albums(userId, view.id, rows.size, 100)
                1 -> server.artists(userId, view.id, rows.size, 100)
                2 -> server.tracks(userId, view.id, rows.size, 100, order.sortBy, order.descending)
                else -> if (rows.isEmpty()) server.playlists(userId) else emptyList()
            }
        }.getOrDefault(emptyList())
        if (gen == generation) { rows += page; exhausted = page.size < 100 }
        loading = false
    }
    LaunchedEffect(kind, order) { generation++; rows.clear(); exhausted = false; loading = false; more(generation) }

    val across = (phoneColumns() - 1).coerceAtLeast(2)
    LazyVerticalGrid(GridCells.Fixed(across), Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(if (kind == 0 || kind == 3) 18.dp else 0.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Text(view.name, style = IosType.largeTitle, color = Palette.textPrimary, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
        }
        item(span = { GridItemSpan(maxLineSpan) }) { IosSegmented(kinds, kind, { kind = it }, Modifier.padding(vertical = 6.dp)) }
        if (kind == 2) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IosTintedButton("Play", Icons.Default.PlayArrow, { Music.play(context, server, rows.toList(), 0, state.roomOpen) }, Modifier.weight(1f))
                        IosTintedButton("Shuffle", Icons.Default.Shuffle, { Music.play(context, server, rows.shuffled(), 0, state.roomOpen) }, Modifier.weight(1f))
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(TrackOrder.entries) { o -> IosChip(order == o, o.label) { order = o } }
                    }
                }
            }
        }
        itemsIndexed(rows, key = { _, it -> it.id }, span = { _, _ -> if (kind == 1 || kind == 2) GridItemSpan(maxLineSpan) else GridItemSpan(1) }) { i, item ->
            if (i >= rows.size - 30) LaunchedEffect(rows.size) { more(generation) }
            when (kind) {
                0 -> Cover(item, server, item.albumArtist) { state.push(Screen.Album(item.id)) }
                1 -> ArtistRow(item, server) { state.push(Screen.Artist(item, view.id)) }
                2 -> SongRow(state, item, server, art = true) { Music.play(context, server, rows.toList(), i, state.roomOpen) }
                else -> Cover(item, server, null) { state.push(Screen.Playlist(item.id, item.name)) }
            }
        }
    }
}

/** An album's or playlist's cover, large and rounded, its name and artist beneath. */
@Composable
private fun Cover(item: Item, server: Server, by: String?, onClick: () -> Unit) {
    Column(Modifier.iosClick(onClick)) {
        AsyncImage(server.imageUrl(item.id, "Primary", item.primaryTag, 500), item.name, contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(8.dp)).background(Palette.surface))
        Spacer(Modifier.height(6.dp))
        Text(item.name, style = IosType.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium),
            color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        (by ?: item.year?.toString())?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

@Composable
private fun ArtistRow(artist: Item, server: Server, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().iosClick(onClick)) {
        Row(Modifier.padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(50.dp).clip(CircleShape).background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
                Text(artist.name.take(1), style = IosType.headline, color = Palette.textSecondary)
                AsyncImage(server.imageUrl(artist.id, "Primary", artist.primaryTag, 160), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize())
            }
            Spacer(Modifier.width(12.dp))
            Text(artist.name, style = IosType.body, color = Palette.textPrimary, modifier = Modifier.weight(1f), maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Palette.textMuted)
        }
        HorizontalDivider(Modifier.padding(start = 62.dp), thickness = 0.5.dp, color = Palette.border)
    }
}

/**
 * A song as Apple Music lists one: the cover small (or its number on an
 * album), the name in the accent while it plays, who sang it. A long press
 * puts it next in the queue.
 */
@Composable
internal fun SongRow(state: AppState, track: Item, server: Server, art: Boolean, number: Boolean = false, onClick: () -> Unit) {
    val context = LocalContext.current
    val playing = Music.current?.id == track.id
    Column(Modifier.fillMaxWidth().combinedClickable(onLongClick = {
        Music.playNext(context, server, track); PhoneNotice.show("Playing Next")
    }, onClick = onClick)) {
        Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (art) AsyncImage(server.imageUrl(track.albumId ?: track.id, "Primary", null, 120), null, contentScale = ContentScale.Crop,
                modifier = Modifier.size(46.dp).clip(RoundedCornerShape(5.dp)).background(Palette.surface))
            else if (number) Text(track.indexNumber?.toString() ?: "", style = IosType.body, color = Palette.textMuted,
                modifier = Modifier.width(28.dp), textAlign = TextAlign.Start)
            if (art) Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(track.name, style = IosType.body, color = if (playing) Palette.accent else Palette.textPrimary, maxLines = 1,
                    overflow = TextOverflow.Ellipsis)
                val by = track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" }
                if (art || (by.isNotEmpty() && by != track.albumArtist)) Text(listOfNotNull(by.ifEmpty { null }, track.album.takeIf { art })
                    .joinToString(" · "), style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            track.runtimeTicks?.let { Text(clock(it / TICKS_PER_SECOND.toDouble()), style = IosType.footnote, color = Palette.textMuted) }
        }
        HorizontalDivider(Modifier.padding(start = if (art) 58.dp else if (number) 28.dp else 0.dp), thickness = 0.5.dp, color = Palette.border)
    }
}

/**
 * An album as Apple Music shows one: the cover large and centred, the name,
 * the artist in the accent, its genre and year, Play and Shuffle, the songs
 * by number, and how many and how long at the foot.
 */
@Composable
fun PhoneAlbumScreen(state: AppState, id: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var album by remember { mutableStateOf<Item?>(null) }
    var tracks by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(id) {
        album = runCatching { server.item(userId, id) }.getOrNull()
        tracks = runCatching { server.tracks(userId, id, 0, 500, listOf("ParentIndexNumber", "IndexNumber", "SortName")) }.getOrDefault(emptyList())
    }
    val a = album
    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp)) {
        item {
            Column(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AsyncImage(server.imageUrl(id, "Primary", a?.primaryTag, 800), a?.name, contentScale = ContentScale.Crop,
                    modifier = Modifier.width(260.dp).aspectRatio(1f).shadow(18.dp, RoundedCornerShape(10.dp))
                        .clip(RoundedCornerShape(10.dp)).background(Palette.surface))
                Spacer(Modifier.height(14.dp))
                Text(a?.name ?: "", style = IosType.title, color = Palette.textPrimary, textAlign = TextAlign.Center, maxLines = 2)
                a?.albumArtist?.let { Text(it, style = IosType.title.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal),
                    color = Palette.accent, textAlign = TextAlign.Center, maxLines = 1) }
                IosCaption(listOfNotNull(a?.genres?.firstOrNull(), a?.year?.toString()).joinToString(" · "))
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IosTintedButton("Play", Icons.Default.PlayArrow, { Music.play(context, server, tracks, 0, state.roomOpen) }, Modifier.weight(1f))
                    IosTintedButton("Shuffle", Icons.Default.Shuffle, { Music.play(context, server, tracks.shuffled(), 0, state.roomOpen) }, Modifier.weight(1f))
                    a?.let { al ->
                        IosCircle(if (al.favorite) Icons.Default.Star else Icons.Default.StarBorder,
                            if (al.favorite) "Remove from Favourites" else "Add to Favourites", {
                                scope.launch { runCatching { server.setFavorite(al.id, !al.favorite) }; album = al.copy(favorite = !al.favorite) }
                            }, size = 46, tint = Palette.accent)
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
        itemsIndexed(tracks, key = { _, t -> t.id }) { i, t ->
            SongRow(state, t, server, art = false, number = true) { Music.play(context, server, tracks, i, state.roomOpen) }
        }
        if (tracks.isNotEmpty()) item {
            val minutes = tracks.sumOf { it.runtimeTicks ?: 0L } / TICKS_PER_SECOND / 60
            Text("${tracks.size} song${if (tracks.size == 1) "" else "s"}, $minutes minute${if (minutes == 1L) "" else "s"}",
                style = IosType.footnote, color = Palette.textSecondary, modifier = Modifier.padding(top = 12.dp))
        }
    }
}

/**
 * An artist as Apple Music shows one: their photo across the top with the
 * name over its foot and a play button in the accent, then Top Songs, then
 * the albums, newest first.
 */
@Composable
fun PhoneArtistScreen(state: AppState, artist: Item, libraryId: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    var albums by remember { mutableStateOf<List<Item>>(emptyList()) }
    var top by remember { mutableStateOf<List<Item>>(emptyList()) }
    var all by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(artist.id) {
        top = runCatching { server.tracks(userId, null, 0, 10, listOf("PlayCount", "SortName"), true, artistId = artist.id) }.getOrDefault(emptyList())
        albums = runCatching { server.albums(userId, libraryId, 0, 200, "ProductionYear", true, artist.id) }.getOrDefault(emptyList())
        all = runCatching { server.tracks(userId, null, 0, 500, TrackOrder.Album.sortBy, artistId = artist.id) }.getOrDefault(emptyList())
    }
    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas), contentPadding = PaddingValues(bottom = 120.dp)) {
        item {
            Box(Modifier.fillMaxWidth().height(app.lumiere.android.ui.heroHeight(1.15f))) {
                AsyncImage(server.imageUrl(artist.id, "Primary", artist.primaryTag, 900), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize().background(Palette.surface))
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
                Row(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(artist.name, style = IosType.largeTitle, color = Color.White, modifier = Modifier.weight(1f), maxLines = 2,
                        overflow = TextOverflow.Ellipsis)
                    Box(Modifier.size(52.dp).clip(CircleShape).background(Palette.accent).pressScale()
                        .iosClick { Music.play(context, server, all.shuffled(), 0, state.roomOpen) }, contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.PlayArrow, "Play", tint = Palette.onAccent, modifier = Modifier.size(30.dp))
                    }
                }
            }
        }
        if (top.isNotEmpty()) {
            item { Text("Top Songs", style = IosType.title, color = Palette.textPrimary, modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp)) }
            itemsIndexed(top, key = { _, t -> "top-" + t.id }) { i, t ->
                Box(Modifier.padding(horizontal = 16.dp)) { SongRow(state, t, server, art = true) { Music.play(context, server, top, i, state.roomOpen) } }
            }
        }
        if (albums.isNotEmpty()) item {
            Text("Albums", style = IosType.title, color = Palette.textPrimary, modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 10.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                items(albums, key = { it.id }) { al -> Box(Modifier.width(150.dp)) { Cover(al, server, al.year?.toString()) { state.push(Screen.Album(al.id)) } } }
            }
        }
    }
}

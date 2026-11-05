@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.music

import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.albums
import app.lumiere.android.api.setFavorite
import app.lumiere.android.api.tracks
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/** An album: its cover, Play and Shuffle, and its tracks by disc and number. */
@Composable
fun AlbumScreen(state: AppState, id: String) {
    if (!LocalFormFactor.current.isTv) { PhoneAlbumScreen(state, id); return }
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val form = LocalFormFactor.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var album by remember { mutableStateOf<Item?>(null) }
    var tracks by remember { mutableStateOf<List<Item>>(emptyList()) }

    LaunchedEffect(id) {
        album = runCatching { server.item(userId, id) }.getOrNull()
        tracks = runCatching {
            server.tracks(userId, id, 0, 500, listOf("ParentIndexNumber", "IndexNumber", "SortName"))
        }.getOrDefault(emptyList())
    }
    val a = album
    // On a TV, Apple Music's album: cover, title and buttons held on the left, the tracks on the right.
    if (form.isTv) {
        Row(Modifier.fillMaxSize().background(Palette.ground).padding(horizontal = 56.dp, vertical = 36.dp),
            horizontalArrangement = Arrangement.spacedBy(44.dp)) {
            Column(Modifier.width(260.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AsyncImage(server.imageUrl(id, "Primary", a?.primaryTag, 520), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(260.dp).clip(RoundedCornerShape(10.dp)).background(Palette.surface))
                Text(a?.name ?: "", style = app.lumiere.android.ui.TvType.title, maxLines = 2)
                Text(listOfNotNull(a?.albumArtist, a?.year?.toString(), "${tracks.size} songs").joinToString(" · "),
                    style = app.lumiere.android.ui.TvType.meta)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LButton(onClick = { Music.play(context, server, tracks, 0, state.roomOpen) }) { Text("▶  Play") }
                    LButton(primary = false, onClick = { Music.play(context, server, tracks.shuffled(), 0, state.roomOpen) }) { Text("Shuffle") }
                }
            }
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides app.lumiere.android.ui.rememberCalmPageScroll()) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
                    itemsIndexed(tracks, key = { _, t -> t.id }) { i, track ->
                        TrackRow(track, server, showArt = false) { Music.play(context, server, tracks, i, state.roomOpen) }
                    }
                }
            }
        }
        return
    }
    LazyColumn(Modifier.fillMaxSize().background(Palette.ground), contentPadding = PaddingValues(bottom = 96.dp)) {
        item {
            Row(Modifier.padding(form.gutter.dp), horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.Bottom) {
                AsyncImage(server.imageUrl(id, "Primary", a?.primaryTag, 600), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(if (form.isTv) 220.dp else 140.dp).clip(RoundedCornerShape(8.dp))
                        .background(Palette.surface))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(a?.name ?: "", style = MaterialTheme.typography.headlineLarge, maxLines = 3)
                    Text(listOfNotNull(a?.albumArtist, a?.year?.toString()).joinToString(" · "),
                        style = MaterialTheme.typography.titleMedium, color = Palette.accent)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        LButton(onClick = { Music.play(context, server, tracks, 0, state.roomOpen) }) { Text("Play") }
                        LButton(primary = false, onClick = { Music.play(context, server, tracks.shuffled(), 0, state.roomOpen) }) {
                            Text("Shuffle")
                        }
                        a?.let { al ->
                            LButton(primary = false, onClick = {
                                scope.launch { server.setFavorite(al.id, !al.favorite); album = al.copy(favorite = !al.favorite) }
                            }) { Text(if (al.favorite) "★" else "☆") }
                        }
                    }
                }
            }
        }
        itemsIndexed(tracks, key = { _, t -> t.id }) { i, track ->
            TrackRow(track, server, showArt = false) { Music.play(context, server, tracks, i, state.roomOpen) }
        }
    }
}

/**
 * An artist: their photo and name, Top Songs, their albums as a row, then every
 * song they are on — guests' songs too, since [ids] folds every credit of theirs in.
 */
@Composable
fun ArtistScreen(state: AppState, artist: Item, libraryId: String, ids: List<String> = listOf(artist.id),
                 imageId: String? = artist.id, imageTag: String? = artist.primaryTag) {
    if (!LocalFormFactor.current.isTv) { PhoneArtistScreen(state, artist, libraryId, ids, imageId, imageTag); return }
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    val who = ids.joinToString(",")
    var albums by remember { mutableStateOf<List<Item>>(emptyList()) }
    var tracks by remember { mutableStateOf<List<Item>>(emptyList()) }
    var top by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(who) {
        top = runCatching { server.tracks(userId, null, 0, 10, listOf("PlayCount", "SortName"), true, artistId = who) }.getOrDefault(emptyList())
        albums = runCatching { server.albums(userId, libraryId, 0, 200, "ProductionYear", true, who) }.getOrDefault(emptyList())
        tracks = runCatching { server.tracks(userId, null, 0, 500, TrackOrder.Album.sortBy, artistId = who) }.getOrDefault(emptyList())
    }
    val heading = app.lumiere.android.ui.TvType.row
    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides app.lumiere.android.ui.rememberCalmPageScroll()) {
    LazyColumn(Modifier.fillMaxSize().background(Palette.ground), contentPadding = PaddingValues(bottom = 96.dp)) {
        item {
            // The Person page's header: a round photo beside the name.
            Row(Modifier.padding(start = 56.dp, end = 56.dp, top = 36.dp, bottom = 20.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.size(120.dp).clip(RoundedCornerShape(50)).background(Palette.surface), contentAlignment = Alignment.Center) {
                    Text(artist.name.split(' ').mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString(""),
                        style = app.lumiere.android.ui.TvType.title, color = Palette.textSecondary)
                    imageId?.let { AsyncImage(server.imageUrl(it, "Primary", imageTag, 300), null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(artist.name, style = app.lumiere.android.ui.TvType.title)
                    Text(listOfNotNull(albums.size.takeIf { it > 0 }?.let { "$it albums" }, tracks.size.takeIf { it > 0 }?.let { "$it songs" })
                        .joinToString(" · "), style = app.lumiere.android.ui.TvType.meta)
                }
                LButton(onClick = { Music.play(context, server, tracks.shuffled(), 0, state.roomOpen) }) { Text("Shuffle") }
            }
        }
        if (top.isNotEmpty()) {
            item { Text("Top Songs", style = heading, modifier = Modifier.padding(start = 56.dp, bottom = 4.dp)) }
            itemsIndexed(top, key = { _, t -> "top-" + t.id }) { i, track ->
                TrackRow(track, server, showArt = true) { Music.play(context, server, top, i, state.roomOpen) }
            }
        }
        if (albums.isNotEmpty()) {
            item { Text("Albums", style = heading, modifier = Modifier.padding(start = 56.dp, top = 20.dp, bottom = 4.dp)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 56.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    items(albums, key = { it.id }) { al ->
                        Column(Modifier.width(140.dp)) { SquareCard(al, server) { state.push(Screen.Album(al.id)) } }
                    }
                }
            }
        }
        if (tracks.isNotEmpty()) item { Text("All Songs", style = heading, modifier = Modifier.padding(start = 56.dp, top = 20.dp, bottom = 4.dp)) }
        itemsIndexed(tracks, key = { _, t -> t.id }) { i, track ->
            TrackRow(track, server, showArt = true) { Music.play(context, server, tracks, i, state.roomOpen) }
        }
    }
    }
}

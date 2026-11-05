package app.lumiere.android.music

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.albums
import app.lumiere.android.api.topArtists
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import coil.compose.AsyncImage

// Top 10 Artists and the genre cards, as the Mac's Music page has them, drawn as the
// TV draws its own Top 10s: a tall faint number beside each picture.

/** The picture an artist or a genre stands for: its own photo, else the album the server named. */
fun pictureFor(item: Item, server: Server, size: Int): String? = when {
    item.primaryTag != null -> server.imageUrl(item.id, "Primary", item.primaryTag, size)
    item.albumId != null -> server.imageUrl(item.albumId, "Primary", null, size)
    else -> null
}

/**
 * Top 10 Artists, across the head of the Albums tab: round photos, each beside its number.
 * Ranked by plays, then by how much of each artist the library holds. [onFocused] tells
 * the page the row has the remote, so the page can steer to it.
 */
@Composable
fun TopArtistsRow(state: AppState, server: Server, libraryId: String, onFocused: () -> Unit) {
    var artists by remember(libraryId) { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(libraryId) { artists = server.topArtists(libraryId) }
    if (artists.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(bottom = 16.dp)) {
        Text("Top 10 Artists", style = app.lumiere.android.ui.TvType.title.copy(fontSize = 22.sp))
        Text("By plays, then by how much of each you have", style = MaterialTheme.typography.labelMedium)
        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(20.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
            itemsIndexed(artists, key = { _, a -> a.id }) { i, artist ->
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${i + 1}", style = TextStyle(fontSize = 96.sp, fontWeight = FontWeight.Black,
                        color = Palette.textPrimary.copy(alpha = 0.18f), lineHeight = 96.sp),
                        modifier = Modifier.padding(end = 2.dp))
                    Column(Modifier.width(140.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(140.dp).focusCard(onFocused) {
                            state.push(Screen.Artist(artist, libraryId, imageId = if (artist.primaryTag != null) artist.id else artist.albumId,
                                imageTag = artist.primaryTag))
                        }.clip(RoundedCornerShape(50)).background(Palette.surface), contentAlignment = Alignment.Center) {
                            Text(initials(artist.name), style = app.lumiere.android.ui.TvType.title, color = Palette.textSecondary)
                            pictureFor(artist, server, 300)?.let {
                                AsyncImage(it, artist.name, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(artist.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

private fun initials(name: String) = name.split(' ').mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString("")

/** A genre as a card: one of its albums, picked afresh by the server each visit, the name across it. */
@Composable
fun GenreCard(genre: Item, server: Server, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard(onClick).clip(RoundedCornerShape(10.dp))
        .background(Palette.surfaceRaised), contentAlignment = Alignment.BottomStart) {
        pictureFor(genre, server, 480)?.let {
            AsyncImage(it, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        }
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))))
        Text(genre.name, maxLines = 2, overflow = TextOverflow.Ellipsis,
            style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White,
                shadow = Shadow(Color.Black, blurRadius = 8f)), modifier = Modifier.padding(14.dp))
    }
}

/** One genre's albums, opened from its card: six across, as the Albums tab. */
@Composable
fun MusicGenreScreen(state: AppState, name: String, libraryId: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    var albums by remember(name) { mutableStateOf<List<Item>?>(null) }
    LaunchedEffect(name) {
        albums = runCatching { server.albums(userId, libraryId, 0, 500, genre = name) }.getOrDefault(emptyList())
    }
    Column(Modifier.fillMaxSize().background(Palette.ground).padding(top = 48.dp)) {
        Text(name, style = app.lumiere.android.ui.TvType.title, modifier = Modifier.padding(horizontal = 56.dp))
        val list = albums
        if (list != null && list.isEmpty()) {
            Text("No albums in $name yet.", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(56.dp))
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(6),
            contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 20.dp, bottom = 96.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            itemsIndexed(list ?: emptyList(), key = { _, a -> a.id }) { _, album ->
                SquareCard(album, server) { state.push(Screen.Album(album.id)) }
            }
        }
    }
}

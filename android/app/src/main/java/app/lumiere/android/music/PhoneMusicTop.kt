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
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.iosClick
import app.lumiere.android.ui.phoneColumns
import coil.compose.AsyncImage

// The phone's Top 10 Artists and genre cards: the TV's and the Mac's, at a phone's size.

/** Top 10 Artists above the albums: round photos, each beside its number, scrolled sideways. */
@Composable
fun PhoneTopArtists(state: AppState, server: Server, libraryId: String) {
    var artists by remember(libraryId) { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(libraryId) { artists = server.topArtists(libraryId) }
    if (artists.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 6.dp)) {
        Text("Top 10 Artists", style = IosType.title, color = Palette.textPrimary)
        Text("By plays, then by how much of each you have", style = IosType.footnote, color = Palette.textSecondary)
        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(artists, key = { _, a -> a.id }) { i, artist ->
                Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.iosClick {
                    state.push(Screen.Artist(artist, libraryId, imageId = if (artist.primaryTag != null) artist.id else artist.albumId,
                        imageTag = artist.primaryTag))
                }) {
                    Text("${i + 1}", style = TextStyle(fontSize = 64.sp, fontWeight = FontWeight.Black,
                        color = Palette.textPrimary.copy(alpha = 0.18f), lineHeight = 64.sp))
                    Column(Modifier.width(96.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(96.dp).clip(CircleShape).background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
                            Text(artist.name.take(1), style = IosType.title, color = Palette.textSecondary)
                            pictureFor(artist, server, 240)?.let {
                                AsyncImage(it, artist.name, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                            }
                        }
                        Spacer(Modifier.height(4.dp))
                        Text(artist.name, style = IosType.footnote, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** A genre as a card: one of its albums, the name across it. */
@Composable
fun PhoneGenreCard(genre: Item, server: Server, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(Palette.surfaceRaised)
        .iosClick(onClick), contentAlignment = Alignment.BottomStart) {
        pictureFor(genre, server, 400)?.let {
            AsyncImage(it, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        }
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))))
        Text(genre.name, style = IosType.headline, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(10.dp))
    }
}

/** One genre's albums, as the Albums segment lays them out. */
@Composable
fun PhoneMusicGenreScreen(state: AppState, name: String, libraryId: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    var albums by remember(name) { mutableStateOf<List<Item>?>(null) }
    LaunchedEffect(name) {
        albums = runCatching { server.albums(userId, libraryId, 0, 500, genre = name) }.getOrDefault(emptyList())
    }
    LazyVerticalGrid(GridCells.Fixed((phoneColumns() - 1).coerceAtLeast(2)), Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Text(name, style = IosType.largeTitle, color = Palette.textPrimary, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
        }
        if (albums?.isEmpty() == true) item(span = { GridItemSpan(maxLineSpan) }) {
            Text("No albums in $name yet.", style = IosType.body, color = Palette.textSecondary)
        }
        items(albums ?: emptyList(), key = { it.id }) { album ->
            Cover(album, server, album.albumArtist) { state.push(Screen.Album(album.id)) }
        }
    }
}

package app.lumiere.android.ui

import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.collections
import app.lumiere.android.api.favourites
import app.lumiere.android.api.libraryPage
import app.lumiere.android.api.playlistItems
import app.lumiere.android.api.playlists
import app.lumiere.android.music.Music

/** Where a card leads: a title page, an album, a playlist, or straight into a track. */
fun open(state: AppState, item: Item, context: android.content.Context) {
    val server = state.server ?: return
    when {
        item.isAlbum -> state.push(Screen.Album(item.id))
        item.isAudio -> Music.play(context, server, listOf(item), 0, state.roomOpen)
        item.type == "Playlist" -> state.push(Screen.Playlist(item.id, item.name))
        item.type == "Person" -> state.push(Screen.Person(item.id, item.name))
        else -> state.push(Screen.Detail(item.id))
    }
}

/** A titled grid of cards, filled once by [load]; shimmering placeholders until then. */
@Composable
fun GridScreen(state: AppState, title: String, empty: String, header: @Composable () -> Unit = {},
               shape: CardShape = CardShape.Poster, load: suspend () -> List<Item>) {
    val server = state.server ?: return
    val form = LocalFormFactor.current
    val context = LocalContext.current
    var items by remember { mutableStateOf<List<Item>?>(null) }
    LaunchedEffect(title, state.roomOpen) { items = runCatching { state.visible(load()) }.getOrDefault(emptyList()) }
    Column(Modifier.fillMaxSize().background(Palette.canvas)) {
        // On a TV, titled as the Apple TV app's pages are: large and bold, with how many.
        if (form.isTv) androidx.compose.foundation.layout.Row(Modifier.padding(start = form.gutter.dp, top = 28.dp, bottom = 14.dp),
            verticalAlignment = androidx.compose.ui.Alignment.Bottom) {
            Text(title, style = androidx.compose.ui.text.TextStyle(fontSize = 34.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                color = Palette.textPrimary))
            items?.size?.takeIf { it > 0 }?.let { Text("   $it ${if (it == 1) "title" else "titles"}", style = MaterialTheme.typography.labelLarge,
                color = Palette.textSecondary, modifier = Modifier.padding(bottom = 6.dp)) }
        } else Text(title, style = MaterialTheme.typography.headlineLarge, modifier = Modifier.padding(form.gutter.dp))
        header()
        val list = items
        when {
            list == null -> SkeletonGrid()
            list.isEmpty() -> Text(empty, style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = form.gutter.dp))
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(if (shape == CardShape.Wide) form.wideWidth.dp else form.posterWidth.dp),
                contentPadding = PaddingValues(start = form.gutter.dp, end = form.gutter.dp, bottom = 96.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                items(list, key = { it.id }) { item -> ItemCard(item, server, shape) { open(state, item, context) } }
            }
        }
    }
}

@Composable
fun FavouritesScreen(state: AppState) {
    val userId = state.session?.userId ?: return
    val server = state.server ?: return
    GridScreen(state, "Favourites", "Nothing starred yet. Choose ☆ Favourite on a title or album.",
        header = {
            Row(Modifier.padding(horizontal = LocalFormFactor.current.gutter.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LChip(false, { state.push(Screen.Collections) }, { Text("Collections") })
                LChip(false, { state.push(Screen.Playlists) }, { Text("Playlists") })
            }
            Spacer(Modifier.height(12.dp))
        }) { server.favourites(userId) }
}

@Composable
fun CollectionsScreen(state: AppState) {
    val userId = state.session?.userId ?: return
    val server = state.server ?: return
    GridScreen(state, "Collections", "No collections on this server.") {
        server.collections(userId).filter { (it.childCount ?: 2) > 1 }
    }
}

@Composable
fun PlaylistsScreen(state: AppState) {
    val userId = state.session?.userId ?: return
    val server = state.server ?: return
    // Wide cards on a TV, as Apple shows playlists.
    GridScreen(state, "Playlists", "No playlists yet — make them in Lumiere on the Mac.",
        shape = if (LocalFormFactor.current.isTv) CardShape.Wide else CardShape.Poster) { server.playlists(userId) }
}

/** A playlist: Play and Shuffle for music, its titles otherwise. */
@Composable
fun PlaylistScreen(state: AppState, id: String, name: String) {
    val userId = state.session?.userId ?: return
    val server = state.server ?: return
    val context = LocalContext.current
    var tracks by remember { mutableStateOf<List<Item>>(emptyList()) }
    GridScreen(state, name, "This playlist is empty.", header = {
        if (tracks.any { it.isAudio }) Row(Modifier.padding(horizontal = LocalFormFactor.current.gutter.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LButton(onClick = { Music.play(context, server, tracks.filter { it.isAudio }, 0, state.roomOpen) }) { Text("Play") }
            LButton(onClick = { Music.play(context, server, tracks.filter { it.isAudio }.shuffled(), 0, state.roomOpen) }) {
                Text("Shuffle")
            }
        }
    }) { server.playlistItems(userId, id).also { tracks = it } }
}

/** Everything a person is in. */
@Composable
fun PersonScreen(state: AppState, id: String, name: String) {
    val userId = state.session?.userId ?: return
    val server = state.server ?: return
    GridScreen(state, name, "Nothing here with $name.") {
        server.libraryPage(userId, null, 0, 200, "PremiereDate,ProductionYear", true, personId = id,
            types = "Movie,Series,Video")
    }
}

/** Card-shaped placeholders that breathe while the first page loads. */
@Composable
fun SkeletonGrid() {
    val form = LocalFormFactor.current
    val pulse = rememberInfiniteTransition(label = "skeleton")
    val alpha by pulse.animateFloat(0.35f, 0.75f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "a")
    Row(Modifier.padding(horizontal = form.gutter.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        repeat(if (form.isTv) 7 else 3) {
            Box(Modifier.width(form.posterWidth.dp).aspectRatio(2f / 3f).alpha(alpha)
                .background(Palette.surface, RoundedCornerShape(10.dp)))
        }
    }
}

/** A row of wide placeholders, for Home while it loads. */
@Composable
fun SkeletonShelf() {
    val form = LocalFormFactor.current
    val pulse = rememberInfiniteTransition(label = "shelf")
    val alpha by pulse.animateFloat(0.35f, 0.75f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "a")
    Column(Modifier.padding(vertical = 10.dp)) {
        Box(Modifier.padding(horizontal = form.gutter.dp).width(160.dp).height(18.dp).alpha(alpha)
            .background(Palette.surface, RoundedCornerShape(4.dp)))
        Spacer(Modifier.height(10.dp))
        Row(Modifier.padding(horizontal = form.gutter.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(4) {
                Box(Modifier.width(form.wideWidth.dp).aspectRatio(16f / 9f).alpha(alpha)
                    .background(Palette.surface, RoundedCornerShape(10.dp)))
            }
        }
    }
}


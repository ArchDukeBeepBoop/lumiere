package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.allGenres
import app.lumiere.android.api.pictureFor
import app.lumiere.android.api.topRated
import coil.compose.AsyncImage
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** The Mac's extra Home rows on the phone: Top 10s, genres, library art. */
internal data class PhoneExtras(
    val topFilms: List<Item> = emptyList(),
    val topSeries: List<Item> = emptyList(),
    val topAnime: List<Item> = emptyList(),
    val genres: List<Pair<String, Item>> = emptyList(),
    val libraryArt: Map<String, Item?> = emptyMap(),
)

/** Loaded after the main rows; anything private is already taken out. */
internal suspend fun loadPhoneExtras(state: AppState, libraries: List<Item>): PhoneExtras {
    val server = state.server ?: return PhoneExtras()
    val userId = state.session?.userId ?: return PhoneExtras()
    return coroutineScope {
        val anime = libraries.filter { it.name.contains("anime", true) }
        val films = libraries.filter { it.collectionType == "movies" && it !in anime }
        val shows = libraries.filter { it.collectionType == "tvshows" && it !in anime }
        suspend fun top(views: List<Item>, types: String) = views.flatMap { server.topRated(userId, it.id, types) }
            .sortedByDescending { it.communityRating ?: 0.0 }
        val f = async { top(films, "Movie") }
        val s = async { top(shows, "Series") }
        val a = async { top(anime, "Movie,Series") }
        val g = async {
            server.allGenres(userId).take(12).map { name -> async { name to server.pictureFor(userId, null, name) } }
                .mapNotNull { val (n, p) = it.await(); p?.let { n to p } }
        }
        val l = async { libraries.map { v -> async { v.id to server.pictureFor(userId, v.id, null) } }.map { it.await() }.toMap() }
        PhoneExtras(
            state.visible(f.await()).take(10), state.visible(s.await()).take(10), state.visible(a.await()).take(10),
            // A genre is shown only by a picture that may be shown here.
            g.await().filter { !state.hides(it.second.libraryId) }, l.await(),
        )
    }
}

internal fun LazyListScope.phoneTopTens(state: AppState, extras: PhoneExtras, open: (Item) -> Unit) {
    listOf("Top 10 Films" to extras.topFilms, "Top 10 Series" to extras.topSeries, "Top 10 Anime" to extras.topAnime)
        .filter { it.second.isNotEmpty() }.forEach { (title, list) ->
            item(key = title) {
                PhoneShelf(title) {
                    itemsIndexed(list, key = { _, it -> it.id }) { i, it -> RankedPoster(it, state, i + 1) { open(it) } }
                }
            }
        }
}

internal fun LazyListScope.phoneGenres(state: AppState, extras: PhoneExtras) {
    if (extras.genres.isEmpty()) return
    item(key = "genres") {
        PhoneShelf("Genres") {
            items(extras.genres, key = { it.first }) { (name, pic) -> PictureCard(name, pic, state) { state.push(Screen.Search) } }
        }
    }
}

/** The libraries as pictured cards, each by one of its own titles. */
@Composable
internal fun PhoneLibraries(views: List<Item>, extras: PhoneExtras, state: AppState) {
    if (views.isEmpty()) return
    PhoneShelf("Libraries") {
        items(views, key = { it.id }) { v ->
            PictureCard(v.name, extras.libraryArt[v.id], state) {
                state.push(if (v.collectionType == "music") Screen.Music(v) else Screen.Library(v))
            }
        }
    }
}

@Composable
private fun PhoneShelf(title: String, content: LazyListScope.() -> Unit) {
    val form = LocalFormFactor.current
    Column(Modifier.padding(vertical = 10.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = form.gutter.dp))
        Spacer(Modifier.height(10.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

/** A poster with the Top 10's big number beside it. */
@Composable
private fun RankedPoster(item: Item, state: AppState, rank: Int, onClick: () -> Unit) {
    val server = state.server ?: return
    val width = LocalFormFactor.current.posterWidth
    Row(verticalAlignment = Alignment.Bottom) {
        Text("$rank", style = TextStyle(fontSize = 72.sp, lineHeight = 72.sp, fontWeight = FontWeight.Black,
            color = Palette.textPrimary.copy(alpha = 0.2f)), modifier = Modifier.padding(end = 2.dp))
        Column(Modifier.width(width.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).focusCard(onClick).background(Palette.surface)) {
                AsyncImage(imageFor(item, server, CardShape.Poster, width * 2), item.name,
                    contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
            }
            Spacer(Modifier.height(6.dp))
            Text(item.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A library or genre, pictured by one of its titles, its name across it. */
@Composable
private fun PictureCard(name: String, picture: Item?, state: AppState, onClick: () -> Unit) {
    val server = state.server ?: return
    Box(Modifier.width(200.dp).aspectRatio(16f / 9f).focusCard(onClick).background(Palette.surfaceRaised),
        contentAlignment = Alignment.Center) {
        picture?.let {
            AsyncImage(server.imageUrl(it.id, "Backdrop", it.backdropTag, 420), null, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize())
        }
        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.45f)))
        Text(name, textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.padding(10.dp),
            style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White,
                shadow = Shadow(Color.Black, blurRadius = 8f)))
    }
}

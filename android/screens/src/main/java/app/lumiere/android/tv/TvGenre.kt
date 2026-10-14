package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.libraryPage
import app.lumiere.android.ui.GridScreen
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LocalFormFactor

/** A genre's films and shows, from the Home's genre cards: newest or best first, unwatched or starred. */
@Composable
fun GenreScreen(state: AppState, genre: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    var sort by remember { mutableStateOf(0) }
    var unwatched by remember { mutableStateOf(false) }
    var favourites by remember { mutableStateOf(false) }
    val key = "$genre|$sort|$unwatched|$favourites"
    androidx.compose.runtime.key(key) {
        GridScreen(state, genre, "Nothing in $genre with these filters.", header = {
            // The genre's best-rated title across the top, as Apple opens a category.
            var lead by remember { mutableStateOf<app.lumiere.android.api.Item?>(null) }
            androidx.compose.runtime.LaunchedEffect(genre) {
                lead = state.visible(runCatching { server.libraryPage(userId, null, 0, 8, "CommunityRating", true, genre = genre, types = "Movie,Series") }
                    .getOrDefault(emptyList())).firstOrNull { it.backdropTag != null }
            }
            lead?.let { l -> androidx.compose.foundation.layout.Box(Modifier.padding(horizontal = LocalFormFactor.current.gutter.dp)
                .fillMaxWidth().height(180.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp))) {
                coil.compose.AsyncImage(app.lumiere.android.ui.imageFor(l, server, app.lumiere.android.ui.CardShape.Wide, 1200), null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.fillMaxSize())
                androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.horizontalGradient(
                    listOf(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.7f), androidx.compose.ui.graphics.Color.Transparent))))
                Text("Top rated in $genre · ${l.name}", color = androidx.compose.ui.graphics.Color.White,
                    style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                    modifier = Modifier.align(androidx.compose.ui.Alignment.BottomStart).padding(18.dp))
            } }
            Row(Modifier.padding(horizontal = LocalFormFactor.current.gutter.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf("Newest", "Best rated", "A–Z").forEachIndexed { i, l -> LChip(sort == i, { sort = i }, { Text(l) }) }
                LChip(unwatched, { unwatched = !unwatched }, { Text("Unwatched") })
                LChip(favourites, { favourites = !favourites }, { Text("Favourites") })
            }
        }) {
            val (by, desc) = when (sort) { 1 -> "CommunityRating" to true; 2 -> "SortName" to false; else -> "PremiereDate,DateCreated" to true }
            server.libraryPage(userId, null, 0, 300, by, desc, genre = genre, unwatched = unwatched, favourites = favourites,
                types = "Movie,Series")
        }
    }
}

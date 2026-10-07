package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.libraryPage
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.ItemCard
import app.lumiere.android.ui.Palette
import coil.compose.AsyncImage

/**
 * A person, as the Apple TV app shows one: their picture and a few lines
 * about them, then what of theirs is in the library — films, then shows.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun TvPersonScreen(state: AppState, id: String, name: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    var person by remember { mutableStateOf<Item?>(null) }
    var works by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(id) {
        person = runCatching { server.item(userId, id) }.getOrNull()
        works = state.visible(runCatching {
            server.libraryPage(userId, null, 0, 200, "PremiereDate,ProductionYear", true, personId = id, types = "Movie,Series")
        }.getOrDefault(emptyList()))
    }
    val rows = listOf("Known For" to works.filter { it.communityRating != null }.sortedByDescending { it.communityRating }.take(10),
        "Movies" to works.filter { it.type == "Movie" }, "TV Shows" to works.filter { it.type == "Series" })
        .filter { it.second.isNotEmpty() }
    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas), contentPadding = PaddingValues(vertical = 36.dp)) {
        item {
            Row(Modifier.padding(horizontal = 56.dp), horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(server.imageUrl(id, "Primary", person?.primaryTag, 320), name, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(160.dp).clip(CircleShape).background(Palette.surface))
                Column(Modifier.widthIn(max = 760.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(name, fontSize = 36.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary)
                    person?.overview?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary,
                        maxLines = 5, overflow = TextOverflow.Ellipsis) }
                    if (works.isEmpty()) Text("Nothing with $name in the library yet.", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        rows.forEach { (title, items) ->
            item(key = title) {
                Column(Modifier.padding(top = 24.dp)) {
                    Text(title, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary,
                        modifier = Modifier.padding(start = 56.dp))
                    LazyRow(Modifier.focusRestorer(), contentPadding = PaddingValues(horizontal = 56.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        items(items, key = { it.id }) { w -> ItemCard(w, server, CardShape.Poster) { state.push(Screen.Detail(w.id)) } }
                    }
                }
            }
        }
    }
}

package app.lumiere.android.ui

import kotlinx.coroutines.launch
import app.lumiere.android.api.shuffleFrom
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.genres
import app.lumiere.android.api.libraryPage
import kotlinx.coroutines.delay

private enum class Order(val label: String, val sortBy: String, val descending: Boolean) {
    Title("A–Z", "SortName", false),
    Added("Recently Added", "DateCreated", true),
    Year("Year", "ProductionYear", true),
    Watched("Recently Watched", "DatePlayed", true),
}

/**
 * A library's titles in a grid, a page at a time as it scrolls — some
 * libraries here hold thousands of rows, and the first page should not wait
 * on the last.
 */
@Composable
fun LibraryScreen(state: AppState, view: Item) {
    val server = state.server ?: return
    val session = state.session ?: return
    val form = LocalFormFactor.current
    val items = remember(view.id) { mutableStateListOf<Item>() }
    var order by remember { mutableStateOf(Order.Title) }
    var filter by remember { mutableStateOf("") }
    var exhausted by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var generation by remember { mutableStateOf(0) }
    var genres by remember { mutableStateOf<List<String>>(emptyList()) }
    var genre by remember { mutableStateOf<String?>(null) }
    var unwatched by remember { mutableStateOf(false) }
    var favourites by remember { mutableStateOf(false) }
    var letter by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(view.id) { genres = server.genres(session.userId, view.id) }

    // The phone's copy answers the same question, for an instant first page
    // and for when the server cannot be reached. See LibraryCache.
    fun fromCopy(start: Int) = runCatching {
        state.cache.page(view.id, start, 60, if (letter != null) "SortName" else order.sortBy,
            if (letter != null) false else order.descending, listOf("Movie", "Series", "Video", "BoxSet"),
            genre, unwatched, favourites, letter, filter)
    }.getOrDefault(emptyList())

    suspend fun loadMore(gen: Int) {
        if (loading || exhausted) return
        loading = true
        val first = items.isEmpty()
        if (first) {
            val saved = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { fromCopy(0) }
            if (gen == generation && saved.isNotEmpty()) items += saved
        }
        val start = if (first) 0 else items.size
        val page = runCatching {
            if (filter.isNotBlank()) server.library(session.userId, view.id, start, 60, order.sortBy,
                order.descending, filter)
            else server.libraryPage(session.userId, view.id, start, 60,
                if (letter != null) "SortName" else order.sortBy, if (letter != null) false else order.descending,
                genre, unwatched, favourites, letter)
        }.getOrElse { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { fromCopy(start) }.let { saved ->
            // Offline: the first page is already the copy's.
            if (first) items.toList() else saved
        } }
        if (gen == generation) {
            if (first) items.clear()
            items += page.filter { new -> items.none { it.id == new.id } }
            exhausted = page.size < 60
        }
        loading = false
    }

    LaunchedEffect(view.id, order, filter, genre, unwatched, favourites, letter) {
        delay(if (filter.isEmpty()) 0 else 350)
        generation++
        items.clear()
        exhausted = false
        loading = false
        loadMore(generation)
    }

    Column(Modifier.fillMaxSize().background(Palette.canvas)) {
        Text(view.name, style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(start = form.gutter.dp, top = 16.dp, end = form.gutter.dp))
        Row(
            Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Order.entries.forEach { o ->
                LChip(selected = order == o && letter == null, onClick = { order = o; letter = null },
                    label = { Text(o.label) })
            }
            LChip(unwatched, { unwatched = !unwatched }, { Text("Unwatched") })
            LChip(favourites, { favourites = !favourites }, { Text("Favourites") })
            // A random title from here, playing at once.
            val scope = androidx.compose.runtime.rememberCoroutineScope()
            LChip(false, { scope.launch {
                runCatching { server.shuffleFrom(session.userId, view) }.getOrNull()?.let { state.push(Screen.Player(it.id, 0.0)) }
            } }, { Text("Shuffle") })
        }
        if (genres.isNotEmpty()) {
            androidx.compose.foundation.lazy.LazyRow(
                contentPadding = PaddingValues(horizontal = form.gutter.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item { LChip(genre == null, { genre = null }, { Text("All genres") }) }
                items(genres.size) { i ->
                    val g = genres[i]
                    LChip(genre == g, { genre = if (genre == g) null else g }, { Text(g) })
                }
            }
        }
        if (!form.isTv) {
            OutlinedTextField(
                value = filter, onValueChange = { filter = it }, singleLine = true,
                placeholder = { Text("Filter ${view.name}") },
                modifier = Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp),
            )
        }
        Row(Modifier.weight(1f)) {
        LazyVerticalGrid(
            modifier = Modifier.weight(1f),
            columns = GridCells.Adaptive(form.posterWidth.dp),
            contentPadding = PaddingValues(form.gutter.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            itemsIndexed(items, key = { _, item -> item.id }) { index, item ->
                if (index >= items.size - 20) LaunchedEffect(items.size) { loadMore(generation) }
                ItemCard(item, server, CardShape.Poster) {
                    state.push(Screen.Detail(item.id))
                }
            }
        }
            AlphabetStrip(letter) { letter = it }
        }
    }
}

/** A–Z down the side: a letter jumps the grid to titles from there on. */
@Composable
private fun AlphabetStrip(current: String?, onPick: (String?) -> Unit) {
    androidx.compose.foundation.lazy.LazyColumn(
        Modifier.padding(end = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val letters = listOf("#") + ('A'..'Z').map { it.toString() }
        items(letters.size) { i ->
            val l = letters[i]
            Text(l, style = MaterialTheme.typography.labelMedium,
                color = if (l == current || (l == "#" && current == null)) Palette.accent else Palette.textSecondary,
                modifier = Modifier.focusCard { onPick(if (l == "#") null else l) }.padding(horizontal = 6.dp, vertical = 2.dp))
        }
    }
}

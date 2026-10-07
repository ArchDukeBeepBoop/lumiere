package app.lumiere.android.tv

import androidx.compose.runtime.mutableStateOf
import app.lumiere.android.ui.TvPill
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.Alignment
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import app.lumiere.android.downloads.DownloadsScreen
import app.lumiere.android.ui.CollectionsScreen
import app.lumiere.android.ui.FavouritesScreen
import app.lumiere.android.ui.LibraryScreen
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.PlaylistsScreen
import app.lumiere.android.ui.focusCard

private sealed class Shelf(val name: String) {
    class Library(val view: Item) : Shelf(view.name)
    data object Favourites : Shelf("Favourites")
    data object Collections : Shelf("Collections")
    data object Playlists : Shelf("Playlists")
    data object Downloads : Shelf("Downloaded")
}

/**
 * The Apple TV app's Library, the whole screen given to the titles: the
 * libraries — then favourites, collections, playlists and downloads — as one
 * row of pills across the top, the sort and filters as pills beside them, and
 * the grid edge to edge below. Once the grid is scrolled the bar tucks away;
 * back at the top it returns.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun TvLibraryScreen(state: AppState) {
    val shelves = remember(state.views, state.roomOpen) {
        state.visibleViews(state.views).filter { it.collectionType !in setOf("music", "boxsets", "playlists") }
            .map { Shelf.Library(it) } + listOf(Shelf.Favourites, Shelf.Collections, Shelf.Playlists, Shelf.Downloads)
    }
    var chosen by rememberSaveable { mutableIntStateOf(0) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    // Each library keeps its sort and filters between visits.
    val q = remember(chosen) { (shelves.getOrNull(chosen) as? Shelf.Library)?.let { state.libraryQueries.getOrPut(it.view.id) { LibraryQuery() } as LibraryQuery } ?: LibraryQuery() }
    var scrolled by remember(chosen) { mutableStateOf(false) }
    var choosing by remember { mutableStateOf<String?>(null) }
    var genres by remember(chosen) { mutableStateOf<List<String>>(emptyList()) }
    val current = shelves.getOrNull(chosen)
    LaunchedEffect(chosen) { (current as? Shelf.Library)?.let { genres = genresOf(state, it.view) } }
    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        Column(Modifier.fillMaxSize()) {
            androidx.compose.animation.AnimatedVisibility(!scrolled) {
                Row(Modifier.fillMaxWidth().padding(start = 56.dp, end = 56.dp, top = 22.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    LazyRow(Modifier.weight(1f).focusRestorer(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        itemsIndexed(shelves) { i, s ->
                            TvPill({ chosen = i }, (if (i == chosen) Modifier.focusRequester(first) else Modifier)
                                .onFocusChanged { if (it.isFocused) chosen = i }, selected = i == chosen) {
                                Text(s.name, style = MaterialTheme.typography.titleSmall)
                            }
                        }
                    }
                    if (current is Shelf.Library && !current.view.collectionType.isNullOrEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        TvPill({ q.sort = (q.sort + 1) % SORTS.size; q.letter = null }) { Text("↕ ${SORTS[q.sort].first}") }
                        TvPill({ q.unwatched = !q.unwatched }, selected = q.unwatched) { Text("Unwatched") }
                        if (genres.isNotEmpty()) TvPill({ choosing = "genre" }, selected = q.genre != null) { Text(q.genre ?: "Genre") }
                        TvPill({ choosing = "letter" }, selected = q.letter != null) { Text(q.letter?.let { "From $it" } ?: "A–Z") }
                    }
                }
            }
            Box(Modifier.fillMaxSize()) {
                when (val s = current) {
                    is Shelf.Library -> androidx.compose.runtime.key(s.view.id) {
                        // A library with no kind — 3D, My Videos — is folders on disk, browsed as folders.
                        if (s.view.collectionType.isNullOrEmpty()) TvFolderBrowser(state, s.view)
                        else TvLibraryGrid(state, s.view, q) { scrolled = it }
                    }
                    Shelf.Favourites -> FavouritesScreen(state)
                    Shelf.Collections -> CollectionsScreen(state)
                    Shelf.Playlists -> PlaylistsScreen(state)
                    Shelf.Downloads -> DownloadsScreen(state)
                    null -> Unit
                }
            }
        }
        when (choosing) {
            "genre" -> PillChooser("Genre", genres, q.genre, { q.genre = it }) { choosing = null }
            "letter" -> PillChooser("Starting from", ('A'..'Z').map { it.toString() }, q.letter, { q.letter = it }) { choosing = null }
        }
    }
}

package app.lumiere.android.tv

import app.lumiere.android.ui.pointable
import app.lumiere.android.ui.hoverFocuses

import android.view.KeyEvent
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.ViewInAr
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import app.lumiere.android.downloads.DownloadsScreen
import app.lumiere.android.ui.CollectionsScreen
import app.lumiere.android.ui.FavouritesScreen
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.PlaylistsScreen
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.TvSpace
import app.lumiere.android.ui.TvType

private sealed class Shelf(val name: String, val icon: ImageVector) {
    class Library(val view: Item) : Shelf(view.name, when {
        view.collectionType == "movies" -> Icons.Default.Movie
        view.collectionType == "tvshows" -> Icons.Default.Tv
        view.name.contains("3D", ignoreCase = true) -> Icons.Default.ViewInAr
        view.collectionType.isNullOrEmpty() -> Icons.Default.Folder
        else -> Icons.Default.VideoLibrary
    })
    data object Favourites : Shelf("Favourites", Icons.Default.Star)
    data object Collections : Shelf("Collections", Icons.Default.VideoLibrary)
    data object Playlists : Shelf("Playlists", Icons.Default.PlaylistPlay)
    data object Downloads : Shelf("Downloaded", Icons.Default.Download)
}

/**
 * The Apple TV app's Library: which library, in a slim capsule at the left that
 * opens when the remote reaches it (Left again, the main menu); the library's
 * name and its sort and filters in a band across the top that never moves; the
 * posters below, steered as Home's rows are. Nothing appears or vanishes above
 * the grid while the remote is in it, so the page never jumps.
 */
@Composable
fun TvLibraryScreen(state: AppState) {
    val shelves = remember(state.views, state.roomOpen) {
        state.visibleViews(state.views).filter { it.collectionType !in setOf("music", "boxsets", "playlists") }
            .map { Shelf.Library(it) } + listOf(Shelf.Favourites, Shelf.Collections, Shelf.Playlists, Shelf.Downloads)
    }
    var chosen by rememberSaveable { mutableIntStateOf(0) }
    val current = shelves.getOrNull(chosen)
    // Each library keeps its sort and filters between visits.
    val q = remember(chosen) { (current as? Shelf.Library)?.let { state.libraryQueries.getOrPut(it.view.id) { LibraryQuery() } as LibraryQuery } ?: LibraryQuery() }
    var choosing by remember { mutableStateOf<String?>(null) }
    var genres by remember(chosen) { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(chosen) { (current as? Shelf.Library)?.let { genres = genresOf(state, it.view) } }
    val entry = remember { FocusRequester() }
    var strip by remember(chosen) { mutableStateOf<Item?>(null) }

    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.ground)) {
        val band = maxHeight * TvSpace.strip
        Column(Modifier.fillMaxSize()) {
            // The band: the library's name at the left, its sort and filters at the right.
            Row(Modifier.fillMaxWidth().height(band).padding(start = TvSpace.margin, end = TvSpace.margin, bottom = 12.dp),
                verticalAlignment = Alignment.Bottom) {
                Text(current?.name ?: "", style = TvType.title, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (current is Shelf.Library && !current.view.collectionType.isNullOrEmpty()) {
                    Row(Modifier.clip(RoundedCornerShape(50)).background(Palette.surface.copy(alpha = 0.72f)).padding(5.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        TvPill({ choosing = "sort" }) { app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.sort, size = 14.dp); Spacer(Modifier.width(6.dp)); Text(SORTS[q.sort].first, style = MaterialTheme.typography.titleSmall) }
                        TvPill({ q.unwatched = !q.unwatched }, selected = q.unwatched) { Text("Unwatched", style = MaterialTheme.typography.titleSmall) }
                        if (genres.isNotEmpty()) TvPill({ choosing = "genre" }, selected = q.genre != null) { Text(q.genre ?: "Genre", style = MaterialTheme.typography.titleSmall) }
                        TvPill({ choosing = "letter" }, selected = q.letter != null) { Text(q.letter?.let { "From $it" } ?: "A–Z", style = MaterialTheme.typography.titleSmall) }
                    }
                }
            }
            Box(Modifier.fillMaxSize()) { androidx.compose.runtime.CompositionLocalProvider(app.lumiere.android.ui.LocalInTvLibrary provides true) {
                when (val s = current) {
                    is Shelf.Library -> key(s.view.id) {
                        // A library with no kind — 3D, My Videos — is folders on disk, browsed as folders.
                        if (s.view.collectionType.isNullOrEmpty()) TvFolderBrowser(state, s.view)
                        else TvLibraryGrid(state, s.view, q, entry) { strip = it }
                    }
                    Shelf.Favourites -> FavouritesScreen(state)
                    Shelf.Collections -> CollectionsScreen(state)
                    Shelf.Playlists -> PlaylistsScreen(state)
                    Shelf.Downloads -> DownloadsScreen(state)
                    null -> Unit
                }
            } }
        }
        // Deep in the grid, the band tells about the chosen title instead; it covers the band, never the posters.
        state.server?.let { srv -> app.lumiere.android.ui.StripOverlay(strip, srv, strip != null, Modifier.fillMaxWidth().height(band)) }
        LibrarySwitcher(state, shelves, chosen, Modifier.align(Alignment.CenterStart)) { chosen = it }
        when (choosing) {
            "sort" -> TvChooser("Sort", SORTS.map { it.first }, SORTS[q.sort].first, allLabel = null,
                onPick = { name -> q.sort = SORTS.indexOfFirst { it.first == name }.coerceAtLeast(0); q.letter = null }) { choosing = null }
            "genre" -> TvChooser("Genre", genres, q.genre, onPick = { q.genre = it }) { choosing = null }
            "letter" -> TvChooser("Starting From", ('A'..'Z').map { it.toString() }, q.letter, onPick = { q.letter = it }) { choosing = null }
        }
    }
}

/**
 * The libraries, as the main menu's capsule: closed, a slim pill at the left
 * edge showing where you are; reached with Left, it opens into the list. Moving
 * along it only moves the highlight; OK chooses. Right or Back puts it away,
 * Left once more opens the main menu.
 */
@Composable
private fun LibrarySwitcher(state: AppState, shelves: List<Shelf>, chosen: Int, modifier: Modifier, onChoose: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    // Opening swaps the closed circle for the list, and focus is briefly nowhere;
    // only once the list holds the remote does losing it close the capsule.
    var settled by remember { mutableStateOf(false) }
    val here = remember { FocusRequester() }
    val focus = LocalFocusManager.current
    if (open) androidx.activity.compose.BackHandler { focus.moveFocus(FocusDirection.Right) }
    Column(modifier.padding(start = 6.dp)
        .onFocusChanged { if (it.hasFocus) open = true else if (settled) open = false }
        .onPreviewKeyEvent { e ->
            if (e.nativeKeyEvent.action != KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
            when (e.nativeKeyEvent.keyCode) {
                KeyEvent.KEYCODE_DPAD_LEFT -> if (app.lumiere.android.Flavor.quest) false else { state.tvMenuOpen = true; true }
                KeyEvent.KEYCODE_DPAD_RIGHT -> { focus.moveFocus(FocusDirection.Right); true }
                else -> false
            }
        }
        .animateContentSize()
        .clip(RoundedCornerShape(28.dp))
        .background(Palette.surface.copy(alpha = if (open) 0.92f else 0.6f))
        .then(if (open) Modifier.width(220.dp) else Modifier)
        .padding(if (open) 10.dp else 3.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        shelves.forEachIndexed { i, s ->
            // Closed, only the library you are in shows, as its symbol; the others wait.
            if (open || i == chosen) key(i) {
                if (open && i == shelves.indexOfFirst { it !is Shelf.Library })
                    Box(Modifier.padding(vertical = 4.dp).fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))
                if (open) TvPill({ onChoose(i); focus.moveFocus(FocusDirection.Right) },
                    (if (i == chosen) Modifier.focusRequester(here) else Modifier).fillMaxWidth(),
                    selected = i == chosen, tint = if (i == chosen) Palette.textPrimary else Palette.textSecondary) {
                    Icon(s.icon, null, Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp)); Text(s.name, style = MaterialTheme.typography.titleSmall, maxLines = 1)
                }
                // Closed: the symbol alone in a 40 dp circle, clear of the posters' margin.
                else androidx.tv.material3.Surface({ }, Modifier.size(40.dp).focusRequester(here).hoverFocuses(),
                    shape = androidx.tv.material3.ClickableSurfaceDefaults.shape(androidx.compose.foundation.shape.CircleShape),
                    colors = androidx.tv.material3.ClickableSurfaceDefaults.colors(containerColor = Color.Transparent,
                        contentColor = Palette.textPrimary, focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas)) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(s.icon, null, Modifier.size(18.dp)) }
                }
            }
        }
    }
    LaunchedEffect(open) {
        if (open) { kotlinx.coroutines.delay(30); runCatching { here.requestFocus() }; settled = true } else settled = false
    }
}

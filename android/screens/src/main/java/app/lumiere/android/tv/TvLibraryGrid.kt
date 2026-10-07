package app.lumiere.android.tv

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.input.key.onPreviewKeyEvent
import app.lumiere.android.ui.focusCard
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import app.lumiere.android.ui.holdsRemote
import androidx.compose.foundation.layout.width
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.is3D
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.genres
import app.lumiere.android.api.libraryPage
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.ItemCard
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.frosted
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage

/** The library's sorts, as the pill cycles through them. */
internal val SORTS = listOf(
    Triple("A–Z", "SortName", false), Triple("Recently Added", "DateCreated", true),
    Triple("Release Date", "ProductionYear,PremiereDate", true), Triple("Rating", "CommunityRating", true),
    Triple("Recently Watched", "DatePlayed", true),
)

/** What the library bar sets: sort, filters, genre and starting letter. */
internal class LibraryQuery {
    var sort by mutableStateOf(0)
    var unwatched by mutableStateOf(false)
    var genre by mutableStateOf<String?>(null)
    var letter by mutableStateOf<String?>(null)
    val key get() = "$sort|$unwatched|$genre|$letter"
}

/**
 * A library on a TV as the Apple TV app shows one: posters edge to edge, the
 * whole screen theirs, the chosen title's picture faint behind them. Pages of
 * sixty arrive as the remote nears the end.
 */
@Composable
internal fun TvLibraryGrid(state: AppState, view: Item, q: LibraryQuery, onScrolled: (Boolean) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val items = remember(view.id) { mutableStateListOf<Item>() }
    var done by remember(view.id) { mutableStateOf(false) }
    var busy by remember(view.id) { mutableStateOf(false) }
    var gen by remember(view.id) { mutableStateOf(0) }
    var focused by remember { mutableStateOf<Item?>(null) }
    val grid = rememberLazyGridState()
    var featured by remember(view.id) { mutableStateOf(0) }
    var latest by remember(view.id) { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(view.id) { latest = state.visible(runCatching { server.latest(userId, view.id) }.getOrDefault(emptyList()))
        .distinctBy { it.seriesId ?: it.id }.take(14) }
    LaunchedEffect(grid.firstVisibleItemIndex > 0) { onScrolled(grid.firstVisibleItemIndex > 0) }

    suspend fun more(g: Int) {
        if (busy || done) return
        busy = true
        val (_, by, desc) = SORTS[q.sort]
        val page = runCatching {
            server.libraryPage(userId, view.id, items.size, 60, if (q.letter != null) "SortName" else by,
                if (q.letter != null) false else desc, q.genre, q.unwatched, false, q.letter)
        }.getOrDefault(emptyList())
        if (g == gen) { items += page.filter { n -> items.none { it.id == n.id } }; done = page.size < 60 }
        busy = false
    }
    LaunchedEffect(view.id, q.key) { gen++; items.clear(); done = false; busy = false; more(gen); grid.scrollToItem(0) }

    Box(Modifier.fillMaxSize()) {
        // Plain grey behind the grid, as Apple TV's library: the posters carry the colour.
        if (items.isEmpty() && done) Text("Nothing here with these choices.", style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.align(Alignment.Center))
        LazyVerticalGrid(GridCells.Fixed(state.settings.libraryColumns), state = grid,
            contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 12.dp, bottom = 48.dp),
            horizontalArrangement = Arrangement.spacedBy(32.dp), verticalArrangement = Arrangement.spacedBy(36.dp)) {
            // Recently added, as one row across the top, while nothing narrows the grid.
            // A featured title across the top of the library, as Apple opens each one.
            val leads = latest.filter { it.backdropTag != null }.take(3)
            leads.getOrNull(featured % leads.size.coerceAtLeast(1))?.takeIf { q.sort == 0 && !q.unwatched && q.genre == null && q.letter == null }?.let { lead ->
                item(key = "featured", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                    androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth().height(200.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                        // Left and right turn through the three newest, as the Home banner turns.
                        .onPreviewKeyEvent { e ->
                            val k = e.nativeKeyEvent
                            if (k.action != android.view.KeyEvent.ACTION_DOWN || leads.size < 2) return@onPreviewKeyEvent false
                            when (k.keyCode) {
                                android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> { featured = (featured + 1) % leads.size; true }
                                android.view.KeyEvent.KEYCODE_DPAD_LEFT -> { featured = (featured + leads.size - 1) % leads.size; true }
                                else -> false
                            }
                        }
                        .focusCard({ focused = lead }, { state.push(Screen.Detail(lead.id)) })) {
                        AsyncImage(imageFor(lead, server, CardShape.Wide, 1200), lead.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                        androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent))))
                        Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                            Text("New in ${view.name}", style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.75f))
                            Text(lead.seriesName ?: lead.name, style = MaterialTheme.typography.headlineSmall, color = Color.White)
                            if (leads.size > 1) Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                repeat(leads.size) { i -> androidx.compose.foundation.layout.Box(Modifier.size(6.dp).clip(androidx.compose.foundation.shape.CircleShape)
                                    .background(Color.White.copy(alpha = if (i == featured % leads.size) 1f else 0.35f))) }
                            }
                        }
                    }
                }
            }
            if (latest.isNotEmpty() && q.sort == 0 && !q.unwatched && q.genre == null && q.letter == null) {
                item(key = "latest", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                    Column {
                        Text("Recently Added", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp))
                        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(32.dp),
                            contentPadding = PaddingValues(vertical = 8.dp)) {
                            items(latest.size) { j -> val it = latest[j]
                                androidx.compose.foundation.layout.Box(Modifier.width(150.dp)) {
                                    ItemCard(it, server, CardShape.Poster, onFocus = { f -> focused = f }) { state.push(Screen.Detail(it.id)) }
                                }
                            }
                        }
                        Text("All", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 10.dp))
                    }
                }
            }
            itemsIndexed(items, key = { _, it -> it.id }) { i, item ->
                if (i >= items.size - 20) LaunchedEffect(items.size) { more(gen) }
                ItemCard(item, server, CardShape.Poster, onFocus = { focused = it }, fill = true,
                    badge = if (state.is3D(item)) "3D" else null) { state.push(Screen.Detail(item.id)) }
            }
        }
    }
}

/** A short list of pills over the page — genres, or letters — chosen with OK, left with Back. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun PillChooser(title: String, options: List<String>, current: String?, onPick: (String?) -> Unit, onClose: () -> Unit) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.holdsRemote().padding(top = 70.dp).widthIn(max = 900.dp).frosted().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                TvPill({ onPick(null); onClose() }, if (current == null) Modifier.focusRequester(first) else Modifier, selected = current == null) { Text("All") }
                options.forEach { o ->
                    TvPill({ onPick(o); onClose() }, if (o == current) Modifier.focusRequester(first) else Modifier, selected = o == current) { Text(o) }
                }
            }
        }
    }
}

/** A library's genres, for the chooser. */
internal suspend fun genresOf(state: AppState, view: Item): List<String> {
    val server = state.server ?: return emptyList()
    val userId = state.session?.userId ?: return emptyList()
    return runCatching { server.genres(userId, view.id) }.getOrDefault(emptyList())
}

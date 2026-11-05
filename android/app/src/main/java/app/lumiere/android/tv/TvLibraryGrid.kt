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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.material.icons.filled.Check
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
 * A library on a TV as the Apple TV app shows one: posters six across, steered
 * as Home's rows are — each new line settles at the top of the grid, moving
 * along a line never scrolls. The chosen title is told about in the band above
 * ([onStrip]); the grid itself never changes size. Pages of sixty arrive as the
 * remote nears the end.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun TvLibraryGrid(state: AppState, view: Item, q: LibraryQuery, entry: FocusRequester, onStrip: (Item?) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val items = remember(view.id) { mutableStateListOf<Item>() }
    var done by remember(view.id) { mutableStateOf(false) }
    var busy by remember(view.id) { mutableStateOf(false) }
    var gen by remember(view.id) { mutableStateOf(0) }
    var focused by remember { mutableStateOf<Item?>(null) }
    var focusedIndex by remember { mutableStateOf<Int?>(null) }
    val grid = rememberLazyGridState()
    var featured by remember(view.id) { mutableStateOf(0) }
    var latest by remember(view.id) { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(view.id) { latest = state.visible(runCatching { server.latest(userId, view.id) }.getOrDefault(emptyList()))
        .distinctBy { it.seriesId ?: it.id }.take(14) }

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
    // The remote starts on the library's first title.
    LaunchedEffect(view.id, items.isNotEmpty()) { if (items.isNotEmpty()) { kotlinx.coroutines.delay(80); runCatching { entry.requestFocus() } } }

    // Home's pattern: once past the first line, the chosen title is told about in
    // the band above, settling a moment after the remote stops.
    var holds by remember { mutableStateOf(false) }
    val inGrid = holds && grid.firstVisibleItemIndex > 0
    LaunchedEffect(focused, inGrid) { kotlinx.coroutines.delay(300); onStrip(if (inGrid) focused else null) }
    app.lumiere.android.ui.SteeredGrid(grid, focusedIndex, landing = 0.02f)
    val plain = q.sort == 0 && !q.unwatched && q.genre == null && q.letter == null
    val leads = latest.filter { it.backdropTag != null }.take(3)
    val lead = leads.getOrNull(featured % leads.size.coerceAtLeast(1))?.takeIf { plain }
    val heads = (if (lead != null) 1 else 0) + (if (latest.isNotEmpty() && plain) 1 else 0)
    Box(Modifier.fillMaxSize().onFocusChanged { holds = it.hasFocus }) {
        if (items.isEmpty() && done) Text("Nothing here with these choices.", style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.align(Alignment.Center))
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides app.lumiere.android.ui.rememberSteeredPageScroll()) {
        LazyVerticalGrid(GridCells.Fixed(state.settings.libraryColumns), state = grid,
            contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 12.dp, bottom = 48.dp + app.lumiere.android.ui.TvSpace.foot),
            horizontalArrangement = Arrangement.spacedBy(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            // A featured title across the top of the library, as Apple opens each one.
            lead?.let { lead ->
                item(key = "featured", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                    androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth().height(160.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                        .onFocusChanged { if (it.hasFocus) focusedIndex = 0 }
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
                        .focusRequester(entry)
                        .focusCard({ focused = lead }, { state.push(Screen.Detail(lead.id)) })) {
                        AsyncImage(imageFor(lead, server, CardShape.Wide, 1200), lead.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                        androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent))))
                        Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                            Text("New in ${view.name}", style = app.lumiere.android.ui.TvType.meta)
                            Text(lead.seriesName ?: lead.name, style = app.lumiere.android.ui.TvType.strip)
                            if (leads.size > 1) Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                repeat(leads.size) { i -> androidx.compose.foundation.layout.Box(Modifier.size(6.dp).clip(androidx.compose.foundation.shape.CircleShape)
                                    .background(Color.White.copy(alpha = if (i == featured % leads.size) 1f else 0.35f))) }
                            }
                        }
                    }
                }
            }
            if (latest.isNotEmpty() && plain) {
                item(key = "latest", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.onFocusChanged { if (it.hasFocus) focusedIndex = heads - 1 }) {
                        Text("Recently Added", style = app.lumiere.android.ui.TvType.row, modifier = Modifier.padding(bottom = 8.dp))
                        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(24.dp),
                            contentPadding = PaddingValues(vertical = 8.dp)) {
                            items(latest.size) { j -> val it = latest[j]
                                androidx.compose.foundation.layout.Box(Modifier.width(150.dp)) {
                                    ItemCard(it, server, CardShape.Poster, onFocus = { f -> focused = f }) { state.push(Screen.Detail(it.id)) }
                                }
                            }
                        }
                        Text("All", style = app.lumiere.android.ui.TvType.row, modifier = Modifier.padding(top = 10.dp))
                    }
                }
            }
            itemsIndexed(items, key = { _, it -> it.id }) { i, item ->
                if (i >= items.size - 20) LaunchedEffect(items.size) { more(gen) }
                Box(Modifier.onFocusChanged { if (it.hasFocus) focusedIndex = heads + i }
                    .then(if (i == 0 && lead == null) Modifier.focusRequester(entry) else Modifier)) {
                    ItemCard(item, server, CardShape.Poster, onFocus = { focused = it }, fill = true,
                        badge = if (state.is3D(item)) "3D" else null) { state.push(Screen.Detail(item.id)) }
                }
            }
        }
        }
    }
}

/**
 * A choice over the page as tvOS draws its menus — the playback menu's look: a
 * frosted list at the right, a tick beside the current option. OK chooses, Back leaves.
 * [allLabel] heads the list as the "no choice" option, when there is one.
 */
@Composable
internal fun TvChooser(title: String, options: List<String>, current: String?, allLabel: String? = "All",
                       onPick: (String?) -> Unit, onClose: () -> Unit) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler(onBack = onClose)
    val all = listOfNotNull(allLabel?.let { null to it }) + options.map { it to it }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.CenterEnd) {
        Column(Modifier.holdsRemote().padding(end = 36.dp).width(340.dp).heightIn(max = 480.dp).frosted(22).padding(10.dp)) {
            Text(title, style = app.lumiere.android.ui.TvType.meta, modifier = Modifier.padding(start = 14.dp, top = 6.dp, bottom = 8.dp))
            androidx.compose.foundation.lazy.LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(all.size) { j ->
                    val (value, label) = all[j]
                    val now = value == current
                    TvPill({ onPick(value); onClose() }, Modifier.fillMaxWidth().then(if (now) Modifier.focusRequester(first) else Modifier),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)) {
                        Box(Modifier.size(22.dp)) { if (now) androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Default.Check, null, Modifier.size(20.dp)) }
                        androidx.compose.foundation.layout.Spacer(Modifier.width(8.dp))
                        Text(label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    }
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

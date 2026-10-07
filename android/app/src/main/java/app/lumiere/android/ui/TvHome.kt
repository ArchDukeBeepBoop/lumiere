@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.ui.ExperimentalComposeUiApi::class)

package app.lumiere.android.ui

import androidx.compose.animation.core.animateFloat
import androidx.compose.ui.graphics.graphicsLayer
import app.lumiere.android.api.isNew
import app.lumiere.android.api.byIds
import androidx.compose.ui.focus.focusProperties
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.input.key.onPreviewKeyEvent
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.collections
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.allGenres
import app.lumiere.android.api.pictureFor
import app.lumiere.android.api.topRated
import app.lumiere.android.api.albums
import app.lumiere.android.api.similar
import coil.compose.AsyncImage
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

internal data class TvRows(val shelves: List<Pair<String, List<Item>>>, val libraries: List<Item>)

/** The Mac's extra rows, loaded on the TV only: Top 10s, genres, library art. */
private data class TvExtras(
    val topFilms: List<Item> = emptyList(),
    val topSeries: List<Item> = emptyList(),
    val topAnime: List<Item> = emptyList(),
    val genres: List<Pair<String, Item?>> = emptyList(),
    val finishSeason: List<Item> = emptyList(),
    val continueSeries: List<Item> = emptyList(),
    val because: List<Pair<String, List<Item>>> = emptyList(),
    val libraryArt: Map<String, Item?> = emptyMap(),
    val collections: List<Item> = emptyList(),
)

/** Keeps what has focus at a fixed place rather than chasing the edge. */
private fun pivot(fraction: Float, still: () -> Boolean = { false }) = object : BringIntoViewSpec {
    // The spotlight holds still while the remote moves between its buttons:
    // More Info is already on screen, and scrolling to it pulled the page away.
    // Already wholly on screen: nothing moves. Moving along a row used to
    // nudge the whole page each time; only a row off screen is brought up.
    override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float = when {
        still() -> 0f
        offset >= 0f && offset + size <= containerSize -> 0f
        else -> offset - containerSize * fraction
    }
}

private const val GUTTER = 56

/** Card widths from the screen's own width: six posters, four Up Next, five libraries, three large across. */
private data class TvSizes(val poster: androidx.compose.ui.unit.Dp, val wide: androidx.compose.ui.unit.Dp,
                           val library: androidx.compose.ui.unit.Dp, val large: androidx.compose.ui.unit.Dp)
private val LocalTvSizes = androidx.compose.runtime.compositionLocalOf { TvSizes(150.dp, 300.dp, 260.dp, 360.dp) }
private val GAP = 32.dp

/**
 * Home on a TV, laid out as the Mac's: a spotlight across the top with Play
 * and More Info, moving through new titles on its own; then Continue Watching
 * and Next Up as wide cards with progress, the libraries and genres as
 * pictured cards, Recently Added as posters, and the Top 10s with their
 * numbers. Below the spotlight the backdrop follows whatever is selected.
 */
@Composable
internal fun TvHome(state: AppState, rows: TvRows, @Suppress("UNUSED_PARAMETER") phoneOpen: (Item) -> Unit) {
    // As the Apple TV app: an Up Next card plays; anything else opens its page —
    // an episode its show's, on its season.
    val play: (Item) -> Unit = { state.push(Screen.Player(it.id, null)) }
    val open: (Item) -> Unit = { item ->
        if (item.isEpisode && item.seriesId != null) state.push(Screen.Detail(item.seriesId, item.seasonId))
        else state.push(Screen.Detail(item.id))
    }
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    var extras by remember { mutableStateOf(TvExtras()) }
    LaunchedEffect(rows.libraries.map { it.id }, state.roomOpen) {
        // The rows below the first few wait until those are on screen — Home
        // appears sooner, and the Top 10s and genres follow a moment later.
        delay(if (app.lumiere.android.Device.lowMemory) 1500 else 600)
        extras = coroutineScope {
            val films = rows.libraries.filter { it.collectionType == "movies" && !it.name.contains("anime", true) }
            val shows = rows.libraries.filter { it.collectionType == "tvshows" && !it.name.contains("anime", true) }
            val anime = rows.libraries.filter { it.name.contains("anime", true) }
            val f = async { films.flatMap { server.topRated(userId, it.id, "Movie") }.sortedByDescending { it.communityRating ?: 0.0 }.take(10) }
            val s = async { shows.flatMap { server.topRated(userId, it.id, "Series") }.sortedByDescending { it.communityRating ?: 0.0 }.take(10) }
            val a = async { anime.flatMap { server.topRated(userId, it.id, "Movie,Series") }.sortedByDescending { it.communityRating ?: 0.0 }.take(10) }
            val g = async { server.allGenres(userId).take(12).map { name -> async { name to server.pictureFor(userId, null, name) } }.map { it.await() } }
            // From Next Up, as the Mac makes them: an episode 1 of a later
            // season continues the series; three or fewer left finishes one.
            val next = rows.shelves.firstOrNull { it.first == "Next Up" }?.second.orEmpty()
            val cont = next.filter { it.indexNumber == 1 && (it.parentIndexNumber ?: 1) > 1 }
            val fin = async {
                next.filter { it !in cont && it.seriesId != null }.map { e ->
                    async {
                        val left = runCatching { server.episodes(userId, e.seriesId!!, e.seasonId) }.getOrDefault(emptyList())
                            .count { !it.played }
                        e.takeIf { left in 1..3 }
                    }
                }.mapNotNull { it.await() }
            }
            // A music library has no backdrops: its most-played album's cover instead.
            val l = async { rows.libraries.map { v -> async {
                v.id to if (v.collectionType == "music")
                    runCatching { server.albums(userId, v.id, 0, 1, "PlayCount", true).firstOrNull() }.getOrNull()
                else server.pictureFor(userId, v.id, null)
            } }.map { it.await() }.toMap() }
            // "Because you watched": the two most recent finished titles, and what is like them.
            val bec = async {
                rows.shelves.firstOrNull { it.first == "Watched Lately" }?.second.orEmpty()
                    .distinctBy { it.seriesId ?: it.id }.take(2).map { w ->
                        async {
                            val seed = w.seriesId ?: w.id
                            val name = w.seriesName ?: w.name
                            "Because you watched $name" to state.visible(runCatching { server.similar(userId, seed) }.getOrDefault(emptyList()))
                        }
                    }.map { it.await() }.filter { it.second.isNotEmpty() }
            }
            // Collections with artwork; one holding anything private never shows outside the room.
            val col = async {
                server.collections(userId).filter { it.backdropTag != null || it.primaryTag != null }.take(12).map { c -> async {
                    c.takeIf { runCatching { server.children(userId, c.id) }.getOrNull()?.none { state.hides(it.libraryId) } == true }
                } }.mapNotNull { it.await() }
            }
            val ni = state.settings.notInterested
            fun List<Item>.wanted() = filter { it.id !in ni && it.seriesId !in ni }
            TvExtras(state.visible(f.await()).wanted(), state.visible(s.await()).wanted(), state.visible(a.await()).wanted(),
                g.await().filter { it.second == null || !state.hides(it.second!!.libraryId) }, fin.await().wanted(), cont.wanted(),
                bec.await().map { (t, l) -> t to l.wanted() }.filter { it.second.isNotEmpty() }, l.await(), runCatching { col.await() }.getOrDefault(emptyList()).wanted())
        }
    }

    // Titles added to Up Next by hand, after what is under way; never private ones.
    var watchlist by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(state.settings.watchlist, state.roomOpen) {
        watchlist = if (state.roomOpen) emptyList() else state.visible(runCatching {
            server.byIds(userId, state.settings.watchlist) }.getOrDefault(emptyList())).filter { it.libraryId !in state.privateLibraries }
    }
    val spotlight = remember(rows) {
        rows.shelves.firstOrNull { it.first.startsWith("Recently Added") }?.let { _ ->
            rows.shelves.filter { it.first.startsWith("Recently Added") }.flatMap { it.second }
                .filter { it.backdropTag != null && !it.isEpisode }.shuffled().take(6)
        }.orEmpty().ifEmpty { rows.shelves.flatMap { it.second }.filter { it.backdropTag != null }.take(6) }
    }
    // Something half-watched opens the spotlight, Resume selected; then the new titles.
    val resumeFirst = rows.shelves.firstOrNull { it.first == "Continue Watching" }?.second?.firstOrNull()
    val pages = remember(spotlight, resumeFirst) { listOfNotNull(resumeFirst) + spotlight.filter { it.id != resumeFirst?.id } }
    // While music plays, the spotlight says so first — Apple TV's music-aware Top Shelf.
    val nowPlaying = app.lumiere.android.music.Music.current
    var page by remember(pages) { mutableIntStateOf(0) }
    // The spotlight's pictures fetched ahead, so each page arrives drawn.
    val context = androidx.compose.ui.platform.LocalContext.current
    @Suppress("DEPRECATION") val loader = coil.compose.LocalImageLoader.current
    // Only the page after this one: two backdrops in memory, never six.
    LaunchedEffect(pages, page) {
        pages.getOrNull((page + 1) % pages.size.coerceAtLeast(1))?.let { p -> imageFor(p, server, CardShape.Wide, 1600)?.let {
            loader.enqueue(coil.request.ImageRequest.Builder(context).data(it).build()) } }
    }
    val restored = remember { state.homeScroll.first > 0 }
    var heroFocused by remember { mutableStateOf(!restored) }
    var bannerHeld by remember { mutableStateOf(false) }
    // Read by the scroll spec outside composition, so a plain holder.
    val heroRef = remember { booleanArrayOf(!restored) }
    var focused by remember { mutableStateOf<Item?>(null) }
    LaunchedEffect(pages, heroFocused) {
        // Turning by itself, except while the remote rests on More Info — the title is being read.
        while (heroFocused && pages.size > 1) { delay(9_000); if (!bannerHeld) page = (page + 1) % pages.size }
    }
    val hero = pages.getOrNull(page)
    // The picture settles a moment after the selection, so sweeping a row
    // does not load every backdrop on the way past.
    var shown by remember { mutableStateOf<Item?>(null) }
    LaunchedEffect(heroFocused, hero, focused) {
        state.focusedItem = if (heroFocused) hero else focused
        if (!heroFocused) delay(300); shown = if (heroFocused) hero else focused ?: hero
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { state.focusedItem = null } }

    // The spotlight is the page's top: back on it, the page is too.
    // Back to Home lands where it was left, not at the top.
    val list = androidx.compose.foundation.lazy.rememberLazyListState(state.homeScroll.first, state.homeScroll.second)
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { state.homeScroll = list.firstVisibleItemIndex to list.firstVisibleItemScrollOffset } }
    // Returned to a scrolled Home: the remote goes to the row on screen, not the spotlight.
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    LaunchedEffect(Unit) { if (restored) { delay(200); focusManager.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) } }
    val heroPlay = remember { FocusRequester() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    // Which row has the remote; up from the first goes back to the spotlight,
    // which a tall page has scrolled out of the list's reach.
    var row by remember { mutableIntStateOf(-1) }
    LaunchedEffect(heroFocused) { if (heroFocused) { delay(50); list.animateScrollToItem(0) } }
    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.canvas)) {
        val screenH = maxHeight
        // Only the banner has a picture, as on Apple TV; below it the ground is plain grey,
        // and nothing behind the rows changes as the remote moves.
        val heroArt by androidx.compose.animation.core.animateFloatAsState(if (heroFocused) 1f else 0f,
            tween(app.lumiere.android.Motion.ms(400)), label = "heroArt")
        // The top shelf as Apple draws it: each title's art dissolving slowly into the
        // next, a slow drift where the device can afford it, the full width of the screen.
        val drift = if (!app.lumiere.android.Device.lowMemory && !app.lumiere.android.Motion.reduced)
            androidx.compose.animation.core.rememberInfiniteTransition(label = "drift").animateFloat(1f, 1.06f,
                androidx.compose.animation.core.infiniteRepeatable(tween(14_000), androidx.compose.animation.core.RepeatMode.Reverse), label = "zoom").value
        else 1f
        if (heroArt > 0f) Crossfade(hero, animationSpec = tween(app.lumiere.android.Motion.ms(900)), label = "backdrop") { item ->
            val art = item?.let { imageFor(it, server, CardShape.Wide, 1600) }
            if (art != null) AsyncImage(art, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()
                .graphicsLayer { alpha = heroArt; scaleX = drift; scaleY = drift })
        }
        // A soft dark band under the menu bar, so its tabs read on any picture.
        Box(Modifier.fillMaxWidth().height(120.dp).graphicsLayer { alpha = heroArt }
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))))
        BannerPreview(state, hero, heroFocused && !state.tvMenuOpen)
        // Below the spotlight the rows sit on the app's own ground, as every
        // other screen does; the picture stays only as a faint wash behind them.
        val wash by androidx.compose.animation.core.animateFloatAsState(if (heroFocused) 0f else 0.82f,
            tween(app.lumiere.android.Motion.ms(350)), label = "wash")
        Box(Modifier.fillMaxSize().background(Palette.canvas.copy(alpha = wash)))
        // Shade where the title and buttons sit, lightening across; then a long fall into the grey below.
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to Palette.canvas.copy(alpha = 0.85f), 0.35f to Palette.canvas.copy(alpha = 0.4f), 0.65f to Color.Transparent)))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            (if (heroFocused) 0.4f else 0.1f) to Color.Transparent, 0.62f to Palette.canvas.copy(alpha = 0.55f), 0.8f to Palette.canvas)))

        // The clock and the room live in the menu bar, which shows over the
        // spotlight; nothing focusable sits in a corner for the remote to strand in.
        // The bar and clock fade after a few still seconds, leaving the picture; up brings them back.
        LaunchedEffect(heroFocused, page) { state.tvAtTop = heroFocused; if (heroFocused) { delay(4_000); state.tvAtTop = false } }
        if (!state.settings.tvTopBar) Row(Modifier.align(Alignment.TopEnd).padding(18.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)) { TvClock(state); RoomButton(state) }
        val spec = remember { pivot(0.08f) { heroRef[0] } }
        val across = maxWidth - (GUTTER * 2).dp
        val sizes = TvSizes(poster = (across - GAP * 5) / 6, wide = (across - GAP * 3) / 4, library = (across - GAP * 4) / 5,
            large = (across - GAP * 2) / 3)
        CompositionLocalProvider(LocalBringIntoViewSpec provides spec, LocalTvSizes provides sizes) {
            LazyColumn(Modifier.fillMaxSize().onPreviewKeyEvent { e ->
                // Up from the spotlight: the tabs come down from the top.
                if (e.nativeKeyEvent.keyCode == android.view.KeyEvent.KEYCODE_DPAD_UP &&
                    e.nativeKeyEvent.action == android.view.KeyEvent.ACTION_DOWN && heroFocused && state.settings.tvTopBar) {
                    state.tvMenuOpen = true
                    return@onPreviewKeyEvent true
                }
                if (e.nativeKeyEvent.keyCode == android.view.KeyEvent.KEYCODE_DPAD_UP &&
                    e.nativeKeyEvent.action == android.view.KeyEvent.ACTION_DOWN && row == 1) {
                    scope.launch { list.animateScrollToItem(0); delay(80); runCatching { heroPlay.requestFocus() } }
                    true
                } else false
            }, state = list, contentPadding = PaddingValues(bottom = 64.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (nowPlaying != null && app.lumiere.android.music.Music.isPlaying) item(key = "nowplaying") { NowPlayingBanner(state, nowPlaying) }
                item(key = "hero") {
                    Hero(state, hero, pages.size, page, { d -> if (pages.isNotEmpty()) page = (page + d + pages.size) % pages.size }, Modifier.height(screenH * 0.68f)
                        .onFocusChanged { heroFocused = it.hasFocus; heroRef[0] = it.hasFocus }, heroPlay) { bannerHeld = it }
                }
                var index = 0
                fun shelf(key: String, block: @Composable () -> Unit) {
                    val mine = ++index
                    item(key = key) {
                        Box(Modifier.onFocusChanged { if (it.hasFocus) row = mine }) {
                            CompositionLocalProvider(LocalBringIntoViewSpec provides pivot(0.05f)) { block() }
                        }
                    }
                }
                // In the order Settings gives, each row on or off — the Mac's Home Order.
                for (key in state.settings.tvRowOrder.filter { it !in state.settings.tvRowsHidden }
                    .let { if (state.settings.compactHome) it.take(6) else it }) when (key) {
                    // One Up Next row, as the Apple TV app shows it: what is in
                    // progress, then what comes next, then seasons nearly done.
                    "continue" -> if (state.settings.tvUpNextMerged) {
                        val items = (rows.shelves.firstOrNull { it.first == "Continue Watching" }?.second.orEmpty() + watchlist +
                            rows.shelves.firstOrNull { it.first == "Next Up" }?.second.orEmpty() + extras.finishSeason)
                            .distinctBy { it.seriesId ?: it.id }.filter { it.id !in state.justWatched }
                        state.upNextTop = items.firstOrNull()
                        if (items.isNotEmpty()) shelf("upnext") {
                            TvShelf("Up Next") { items(items, key = { it.id }) { WideCard(it, state, { focused = it }) { play(it) } } }
                        }
                    } else {
                        val items = rows.shelves.firstOrNull { it.first == "Continue Watching" }?.second.orEmpty()
                        if (items.isNotEmpty()) shelf(key) {
                            TvShelf("Continue Watching") { items(items, key = { it.id }) { WideCard(it, state, { focused = it }) { play(it) } } }
                        }
                    }
                    "nextup", "finish" -> if (!state.settings.tvUpNextMerged) {
                        val (title, items) = if (key == "nextup") "Next Up" to rows.shelves.firstOrNull { it.first == "Next Up" }?.second.orEmpty()
                            else "Finish the Season" to extras.finishSeason
                        if (items.isNotEmpty()) shelf(key) {
                            TvShelf(title) { items(items, key = { it.id }) { WideCard(it, state, { focused = it }) { play(it) } } }
                        }
                    }
                    "watched" -> {
                        val title = "Watched Lately"
                        val items = rows.shelves.firstOrNull { it.first == title }?.second.orEmpty()
                        if (items.isNotEmpty()) shelf(key) {
                            TvShelf(title) { items(items, key = { it.id }) { WideCard(it, state, { focused = it }) { open(it) } } }
                        }
                    }
                    "series" -> {
                        val (title, items) = "Continue the Series" to extras.continueSeries
                        if (items.isNotEmpty()) shelf(key) {
                            TvShelf(title) { items(items, key = { it.id }) { WideCard(it, state, { focused = it }) { open(it) } } }
                        }
                    }
                    "libraries" -> if (rows.libraries.isNotEmpty()) shelf(key) {
                        TvShelf("Libraries") {
                            items(rows.libraries, key = { it.id }) { v ->
                                PictureCard(v.name, extras.libraryArt[v.id], state, { focused = extras.libraryArt[v.id] }) {
                                    state.push(if (v.collectionType == "music") Screen.Music(v) else Screen.Library(v))
                                }
                            }
                        }
                    }
                    "recent" -> rows.shelves.filter { it.second.isNotEmpty() && it.first.startsWith("Recently Added") }.forEach { (title, items) ->
                        shelf(title) {
                            // Apple's "New Episodes": a show's new episodes as one card that opens the show.
                            val grouped = items.groupBy { if (it.isEpisode) it.seriesId ?: it.id else it.id }.values.map { it.first() to it.size }
                            TvShelf(title) { items(grouped, key = { it.first.id }) { (it, n) ->
                                PosterCard(it, state, null, { focused = it }, caption = if (it.isEpisode) (if (n > 1) "$n new episodes" else "New episode") else null) {
                                    if (it.isEpisode && it.seriesId != null) state.push(Screen.Detail(it.seriesId)) else open(it)
                                }
                            } }
                        }
                    }
                    "topfilms", "topseries", "topanime" -> {
                        val (title, items) = when (key) {
                            "topfilms" -> "Top 10 Films" to extras.topFilms
                            "topseries" -> "Top 10 Series" to extras.topSeries
                            else -> "Top 10 Anime" to extras.topAnime
                        }
                        if (items.isNotEmpty()) shelf(key) {
                            TvShelf(title, "By community rating") {
                                itemsIndexed(items, key = { _, it -> it.id }) { i, it -> PosterCard(it, state, i + 1, { focused = it }) { open(it) } }
                            }
                        }
                    }
                    "because" -> extras.because.forEach { (title, items) ->
                        shelf(title) {
                            // Recommendations as Apple shows them: three large pictures across.
                            TvShelf(title) { items(items, key = { it.id }) { WideCard(it, state, { focused = it }, large = true) { open(it) } } }
                        }
                    }
                    "collections" -> if (extras.collections.isNotEmpty()) shelf(key) {
                        TvShelf("Collections") { items(extras.collections, key = { it.id }) { WideCard(it, state, { focused = it }) { open(it) } } }
                    }
                    "genres" -> if (extras.genres.isNotEmpty()) shelf(key) {
                        TvShelf("Genres") {
                            items(extras.genres, key = { it.first }) { (name, pic) ->
                                PictureCard(name, pic, state, { focused = pic }) { state.push(Screen.Genre(name)) }
                            }
                        }
                    }
                }
            }
        }
        // Last, so it is drawn over everything and holds the remote.
        app.lumiere.android.tv.TvTour(state)
    }
}

/** The spotlight: the title's logo or name, its facts and story, Play and More Info, and the page dots. */
@Composable
private fun Hero(state: AppState, item: Item?, pages: Int, page: Int, onPage: (Int) -> Unit, modifier: Modifier, play: FocusRequester, onHold: (Boolean) -> Unit = {}) {
    var onPlay by remember { mutableStateOf(false) }
    var onInfo by remember { mutableStateOf(false) }
    val server = state.server ?: return
    LaunchedEffect(state.settings.tvTourShown) {
        if (!state.settings.tvTourShown || state.homeScroll.first > 0) return@LaunchedEffect
        delay(200); runCatching { play.requestFocus() }
    }
    Box(modifier.fillMaxWidth()) {
        if (item == null) return@Box
        // In the private room the banner says so, in the room's own colour, so the two never feel alike.
        if (state.roomOpen) Text("Private Room", style = MaterialTheme.typography.labelLarge, color = Palette.onAccent,
            modifier = Modifier.align(Alignment.TopStart).padding(start = GUTTER.dp, top = 84.dp)
                .background(Palette.accent, RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 4.dp))
        Column(Modifier.align(Alignment.BottomStart).padding(start = GUTTER.dp, bottom = 28.dp).widthIn(max = 640.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (item.logoTag != null) {
                AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 760), item.name, contentScale = ContentScale.Fit,
                    alignment = Alignment.BottomStart, modifier = Modifier.height(120.dp).widthIn(max = 420.dp))
            } else {
                Text(item.name, maxLines = 2, overflow = TextOverflow.Ellipsis, style = TextStyle(fontSize = 48.sp,
                    fontWeight = FontWeight.SemiBold, color = Color.White, shadow = Shadow(Color.Black.copy(alpha = 0.6f), blurRadius = 12f)))
            }
            app.lumiere.android.ui.FactPills(item.year?.toString(),
                item.runtimeTicks?.let { val m = it / TICKS_PER_SECOND / 60; if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m" },
                item.officialRating, listOfNotNull(item.genres.take(2).joinToString(", ").ifEmpty { null },
                    item.communityRating?.let { "★ %.1f".format(it).removeSuffix(".0") }))
            item.overview?.let {
                Text(it, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium.copy(
                    fontSize = 16.sp, lineHeight = 23.sp, color = Color.White.copy(alpha = 0.85f)))
            }
            // Left from Play and right from More Info turn the banner, as Apple TV's top shelf turns.
            Row(Modifier.onPreviewKeyEvent { e ->
                val k = e.nativeKeyEvent
                if (k.action != android.view.KeyEvent.ACTION_DOWN || pages < 2) return@onPreviewKeyEvent false
                when {
                    k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_LEFT && onPlay -> { onPage(-1); true }
                    k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_RIGHT && onInfo -> { onPage(1); true }
                    else -> false
                }
            }, horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                LButton(onClick = { state.push(Screen.Player(item.id, null)) }, modifier = Modifier.focusRequester(play).onFocusChanged { onPlay = it.isFocused }) {
                    Text(if (item.positionTicks > 0) "▶  Resume" + (item.episodeLabel?.let { " $it" } ?: "") +
                        " · ${((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60} min left" else "▶  Play")
                }
                LButton(primary = false, modifier = Modifier.onFocusChanged { onInfo = it.isFocused; onHold(it.isFocused) }, onClick = {
                    state.push(if (item.isEpisode && item.seriesId != null) Screen.Detail(item.seriesId, item.seasonId) else Screen.Detail(item.id))
                }) { Text("More Info") }
                Spacer(Modifier.width(18.dp))
                repeat(pages) { i ->
                    Box(Modifier.padding(horizontal = 3.dp).size(if (i == page) 8.dp else 6.dp).clip(CircleShape)
                        .background(if (i == page) Color.White else Color.White.copy(alpha = 0.35f)))
                }
            }
        }
    }
}

/** "1995 · 1h 28m · PG · Drama, Science Fiction · ★ 6", the Mac's line. */
private fun facts(item: Item): String = listOfNotNull(
    item.year?.toString(),
    item.runtimeTicks?.let { val m = it / TICKS_PER_SECOND / 60; if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m" },
    item.officialRating,
    item.genres.take(2).joinToString(", ").ifEmpty { null },
    item.communityRating?.let { "★ %.1f".format(it).removeSuffix(".0") },
).joinToString("  ·  ")

@Composable
private fun TvShelf(title: String, subtitle: String? = null, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    Column(Modifier.padding(top = 18.dp)) {
        Row(Modifier.padding(start = GUTTER.dp), verticalAlignment = Alignment.Bottom) {
            Text(title, style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary.copy(alpha = 0.9f)))
            subtitle?.let { Text("   $it", style = MaterialTheme.typography.labelMedium) }
        }
        // Back into a row lands on the card it was left on, not the nearest one.
        // The row's ends are walls: Right past the last card stays put
        // instead of leaping up to the spotlight.
        LazyRow(Modifier.focusRestorer().focusProperties {
                @OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
                exit = { d -> if (d == androidx.compose.ui.focus.FocusDirection.Left || d == androidx.compose.ui.focus.FocusDirection.Right)
                    androidx.compose.ui.focus.FocusRequester.Cancel else androidx.compose.ui.focus.FocusRequester.Default }
            }, contentPadding = PaddingValues(horizontal = GUTTER.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(GAP), content = content)
    }
}

/** Continue Watching and Next Up: a still with progress, the show and episode beneath. */
@Composable
private fun WideCard(item: Item, state: AppState, onFocus: () -> Unit, large: Boolean = false, onClick: () -> Unit) {
    val server = state.server ?: return
    Column(Modifier.width(if (large) LocalTvSizes.current.large else LocalTvSizes.current.wide)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard(onFocus, onClick) { state.actionsFor = item }.background(Palette.surface)) {
            AsyncImage(imageFor(item, server, CardShape.Wide, 600), item.name, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize())
            // The show's logo on its still, low on the left, as the Apple TV app does.
            if (item.isEpisode && item.seriesId != null) {
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.6f))))
                AsyncImage(server.imageUrl(item.seriesId, "Logo", null, 300), null, contentScale = ContentScale.Fit,
                    alignment = Alignment.BottomStart,
                    modifier = Modifier.align(Alignment.BottomStart).padding(10.dp).height(34.dp).fillMaxWidth(0.55f))
            }
            app.lumiere.android.ui.WatchedMark(item, Modifier.align(Alignment.TopEnd))
            item.progress?.let { p ->
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.Black.copy(alpha = 0.55f))) {
                    Box(Modifier.fillMaxWidth(p).height(4.dp).background(Palette.accent, RoundedCornerShape(topEnd = 2.dp, bottomEnd = 2.dp)))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(if (item.isEpisode) item.seriesName ?: item.name else item.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Palette.textPrimary))
        // Apple TV's Up Next line: whether it resumes or starts, and how long is left.
        val left = item.progress?.let { "${((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60} min left" }
        Text(if (item.isEpisode) listOfNotNull(if (left != null) "Resume" else if (item.isNew) "New" else if (!item.played) "Next" else null,
                item.episodeLabel, left ?: item.name).joinToString(" · ")
            else item.progress?.let { "${((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60} min left" }
                ?: item.year?.toString() ?: "",
            maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
    }
}

/** A poster; with [rank], the Top 10's big number beside it. */
@Composable
private fun PosterCard(item: Item, state: AppState, rank: Int?, onFocus: () -> Unit, caption: String? = null, onClick: () -> Unit) {
    val server = state.server ?: return
    Row(verticalAlignment = Alignment.Bottom) {
        rank?.let {
            Text("$it", style = TextStyle(fontSize = 96.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary.copy(alpha = 0.18f),
                lineHeight = 96.sp), modifier = Modifier.padding(end = 2.dp))
        }
        // Apple's quiet rows: a poster's name shows only while it is chosen.
        var chosen by remember { mutableStateOf(false) }
        Column(Modifier.width(LocalTvSizes.current.poster).onFocusChanged { chosen = it.hasFocus }) {
            Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).focusCard(onFocus, onClick) { state.actionsFor = item }.background(Palette.surface)) {
                AsyncImage(imageFor(item, server, CardShape.Poster, 300), item.name, contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize())
                app.lumiere.android.ui.WatchedMark(item, Modifier.align(Alignment.TopEnd))
            }
            Spacer(Modifier.height(8.dp))
            Text(if (caption != null) item.seriesName ?: item.name else item.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Palette.textPrimary),
                modifier = Modifier.graphicsLayer { alpha = if (chosen || caption != null) 1f else 0f })
            caption?.let { Text(it, maxLines = 1, style = MaterialTheme.typography.labelMedium) }
        }
    }
}

/** A library or genre, pictured by one of its titles, its name across it. */
@Composable
private fun PictureCard(name: String, picture: Item?, state: AppState, onFocus: () -> Unit, onClick: () -> Unit) {
    val server = state.server ?: return
    Box(Modifier.width(LocalTvSizes.current.library).aspectRatio(16f / 9f).focusCard(onFocus, onClick).background(Palette.surfaceRaised),
        contentAlignment = Alignment.Center) {
        picture?.let {
            val kind = if (it.backdropTag != null) "Backdrop" else "Primary"
            AsyncImage(server.imageUrl(it.id, kind, it.backdropTag ?: it.primaryTag, 520), null, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize())
        }
        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.45f)))
        Text(name, textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 2,
            style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White,
                shadow = Shadow(Color.Black, blurRadius = 8f)), modifier = Modifier.padding(12.dp))
    }
}


/** "Now Playing" above the spotlight while music plays: the cover, the song, a press to open it. */
@Composable
private fun NowPlayingBanner(state: AppState, track: Item) {
    val server = state.server ?: return
    Row(Modifier.padding(start = GUTTER.dp, top = 24.dp).frosted().padding(10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(64.dp).focusCard { state.push(Screen.NowPlaying) }) {
            AsyncImage(server.imageUrl(track.albumId ?: track.id, "Primary", null, 160), null, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize())
        }
        Column {
            Text("Now Playing", style = MaterialTheme.typography.labelMedium, color = Palette.accent)
            Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1)
            Text(track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" }, style = MaterialTheme.typography.labelMedium, maxLines = 1)
        }
    }
}

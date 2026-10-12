package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tv
import androidx.compose.ui.focus.focusRequester
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.Stage
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.favourites
import app.lumiere.android.changeMyList
import app.lumiere.android.player.Theater
import coil.compose.AsyncImage
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * The handset: away from your room, a small pane of glass near your hands
 * for choosing what plays on the place's big screen, as a remote and a row
 * of titles are before a TV — instead of the whole window before you, which
 * stays as you left it for your room. A shelf of posters at a time
 * (Continue Watching, Next Up, My List, what's new in each library): touch
 * one and it fills the big screen; touch it again, or Play, and it plays
 * there. A show opens its seasons and episodes in the same shelf. Down its
 * left edge: every place one touch away, search and everything else (the
 * whole window comes for those), the place's sounds, the poster wall, and
 * everything brought back before you.
 */
object Handset {
    /** Set on the Quest. */
    var enabled = false

    @Composable
    fun Panel() = WithAppImages {
        LumiereTheme {
            val state = OpenApp.state
            val server = state?.server
            Box(Modifier.fillMaxSize()) {
                // Not behind "Who's watching?": nobody's titles until someone is chosen.
                if (state != null && server != null && state.session != null && !state.choosing) Body(state, server)
            }
        }
    }
}

private data class HandsetShelf(val title: String, val items: List<Item>, val wide: Boolean)

private enum class HandsetView { SHELVES, EPISODES, PLACES, SEARCH }

/** The shelves, in Home's order, with private titles left out as Home leaves them. */
private suspend fun loadShelves(state: AppState, server: Server, userId: String): List<HandsetShelf> = coroutineScope {
    val resume = async { runCatching { server.resume(userId) }.getOrDefault(emptyList()) }
    val next = async { runCatching { server.nextUp(userId) }.getOrDefault(emptyList()) }
    val mine = async { runCatching { server.favourites(userId) }.getOrDefault(emptyList()) }
    val views = (state.views.takeIf { it.isNotEmpty() } ?: runCatching { server.views(userId) }.getOrDefault(emptyList()))
        .filter { (it.collectionType == "movies" || it.collectionType == "tvshows") && !state.hides(it.id) }
    val latest = views.map { v -> async { v to runCatching { server.latest(userId, v.id) }.getOrDefault(emptyList()) } }
    val notInterested = state.settings.notInterested
    buildList {
        add(HandsetShelf("Continue", state.visible(resume.await()).filter { it.id !in state.offContinue }, wide = true))
        add(HandsetShelf("Next Up", state.visible(next.await()), wide = true))
        add(HandsetShelf("My List", state.visible(mine.await()), wide = false))
        latest.forEach { d ->
            val (v, items) = d.await()
            add(HandsetShelf(v.name, state.visible(items).filter { it.id !in notInterested && it.seriesId !in notInterested }, wide = false))
        }
    }.filter { it.items.isNotEmpty() }
}

@Composable
private fun Body(state: AppState, server: Server) {
    val userId = state.session?.userId ?: return
    var shelves by remember { mutableStateOf<List<HandsetShelf>?>(null) }
    var shelf by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<Item?>(null) }
    var view by remember { mutableStateOf(HandsetView.SHELVES) }
    val scope = rememberCoroutineScope()
    // Fresh whenever no film is playing (what you just watched has moved on), and in or out of the private room.
    LaunchedEffect(userId, state.roomOpen, Theater.active, state.homeRefresh) {
        if (Theater.active) return@LaunchedEffect
        loadShelves(state, server, userId).let { if (it.isNotEmpty() || shelves == null) shelves = it }
        shelf = shelf.coerceIn(0, ((shelves?.size ?: 1) - 1).coerceAtLeast(0))
        if (chosen == null) chosen = shelves?.getOrNull(shelf)?.items?.firstOrNull()?.also { Marquee.show(it) }
    }
    fun choose(item: Item) { chosen = item; Marquee.show(item) }
    fun play(item: Item, fromStart: Boolean = false) {
        scope.launch {
            // A show plays where you are in it: the episode it's up to, else its first.
            val target = if (!item.isSeries) item else runCatching {
                server.nextUp(userId).firstOrNull { it.seriesId == item.id } ?: server.episodes(userId, item.id, null).firstOrNull()
            }.getOrNull() ?: return@launch
            Stage.wholeWindow = false
            Marquee.show(target)
            val nearEnd = (target.progress ?: 0f) > 0.92f
            state.push(Screen.Player(target.id, if (fromStart || nearEnd) 0.0 else null))
        }
    }

    Row(Modifier.fillMaxSize().spatialGlass(36).padding(14.dp)) {
        Rail(state, view) { view = it }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f).fillMaxHeight()) {
            when (view) {
                HandsetView.PLACES -> Places { Stage.goTo(it); view = HandsetView.SHELVES }
                HandsetView.SEARCH -> Search(state, server, userId, chosen) { item -> if (chosen?.id == item.id) play(item) else choose(item) }
                HandsetView.EPISODES -> {
                    val show = chosen?.let { if (it.isSeries) it.id else it.seriesId }
                    if (show == null) view = HandsetView.SHELVES
                    else Episodes(state, server, userId, show, chosen, ::choose, { play(it) }) { view = HandsetView.SHELVES }
                }
                HandsetView.SHELVES -> {
                    val list = shelves
                    if (list == null) Text("Loading…", color = Palette.textSecondary, modifier = Modifier.padding(8.dp))
                    else if (list.isEmpty()) Text("Nothing here yet", color = Palette.textSecondary, modifier = Modifier.padding(8.dp))
                    else {
                        Chips(list.map { it.title }, shelf) { shelf = it }
                        Spacer(Modifier.height(10.dp))
                        val current = list.getOrNull(shelf) ?: list.first()
                        Posters(current.items, server, current.wide, chosen) { item ->
                            if (chosen?.id == item.id) play(item) else choose(item)
                        }
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            chosen?.let { ChosenBar(state, it, server, onPlay = { fromStart -> play(it, fromStart) }, onEpisodes = { view = HandsetView.EPISODES }) }
        }
    }
}

/** The handset's own rail: home, the places, search and everything else, sounds, the wall, bring here. */
@Composable
private fun Rail(state: AppState, view: HandsetView, go: (HandsetView) -> Unit) {
    Column(Modifier.fillMaxHeight().width(64.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        GlassButton(Icons.Default.Home, "Titles", chosen = view == HandsetView.SHELVES, size = 54.dp) { go(HandsetView.SHELVES) }
        GlassButton(placeIcon(Stage.place), "Places: you're in ${Stage.place.label}", chosen = view == HandsetView.PLACES,
            caption = placeCaption(Stage.place), size = 54.dp) { go(HandsetView.PLACES) }
        GlassButton(Icons.Default.Search, "Search", chosen = view == HandsetView.SEARCH, size = 54.dp) { go(HandsetView.SEARCH) }
        GlassButton(Icons.Default.OpenInFull, "Everything (the whole window)", size = 54.dp) { Stage.wholeWindow = true }
        Spacer(Modifier.weight(1f))
        GlassButton(Icons.Default.GraphicEq, if (Stage.ambience) "Sounds of the place: on" else "Sounds of the place: off",
            chosen = Stage.ambience, size = 48.dp) { Stage.toggleAmbience() }
        if (PosterWall.enabled) GlassButton(Icons.Default.ViewModule, "Poster wall", chosen = PosterWall.open, size = 48.dp) {
            PosterWall.open = !PosterWall.open
        }
        if (Stage.place == Stage.Place.ROOM && Stage.mount != null)
            GlassButton(Icons.Default.Tv, "Take the screen off your wall", chosen = true, size = 48.dp) { Stage.askMount() }
        GlassButton(Icons.Default.CenterFocusStrong, "Bring everything here", size = 48.dp) { Stage.bringHere() }
        MusicGroup(state, size = 40.dp)
    }
}

/** The shelves' names, one chosen. */
@Composable
private fun Chips(names: List<String>, chosen: Int, choose: (Int) -> Unit) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(names.size) { i ->
            Pill(names[i], chosen = i == chosen) { choose(i) }
        }
    }
}

@Composable
private fun Pill(text: String, chosen: Boolean, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when { chosen -> Palette.textPrimary; hovered -> Color.White.copy(alpha = 0.18f); else -> Color.White.copy(alpha = 0.07f) }
    Text(text, color = if (chosen) Palette.canvas else Palette.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(ground).hoverable(source)
            .clickable(interactionSource = source, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 9.dp))
}

/** A shelf of posters (stills for what's in progress); the chosen one ringed, with Play on it. */
@Composable
private fun Posters(items: List<Item>, server: Server, wide: Boolean, chosen: Item?, onTap: (Item) -> Unit) {
    val list = rememberLazyListState()
    LazyRow(state = list, horizontalArrangement = Arrangement.spacedBy(12.dp), contentPadding = PaddingValues(end = 8.dp)) {
        items(items, key = { it.id }) { item -> Poster(item, server, wide, chosen?.id == item.id) { onTap(item) } }
    }
}

@Composable
private fun Poster(item: Item, server: Server, wide: Boolean, chosen: Boolean, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val width = if (wide) 236.dp else 120.dp
    Column(Modifier.width(width)) {
        Box(Modifier.fillMaxWidth().aspectRatio(if (wide) 16f / 9f else 2f / 3f).clip(RoundedCornerShape(10.dp))
            .background(Palette.surfaceRaised)
            .border(if (chosen) 3.dp else if (hovered) 2.dp else 0.dp, if (chosen) Palette.accent else Color.White.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .hoverable(source).clickable(interactionSource = source, indication = null, onClick = onClick)) {
            AsyncImage(imageFor(item, server, if (wide) CardShape.Wide else CardShape.Poster, if (wide) 480 else 240), item.name,
                contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            item.progress?.let { f ->
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp).background(Color.Black.copy(alpha = 0.5f))) {
                    Box(Modifier.fillMaxWidth(f).height(5.dp).background(Palette.accent))
                }
            }
            if (chosen) Box(Modifier.align(Alignment.Center).size(48.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Default.PlayArrow, "Play", tint = Color.White, modifier = Modifier.size(32.dp))
            }
        }
        Text(if (item.isEpisode) listOfNotNull(item.episodeLabel, item.name).joinToString(" · ") else item.name,
            color = Palette.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp))
    }
}

/**
 * Search, here on the handset: type (the headset's keyboard comes up under
 * the field) and the titles that match fill the shelf as you go; touch one
 * for the big screen, again to play — the window never needs to come.
 */
@Composable
private fun Search(state: AppState, server: Server, userId: String, chosen: Item?, onTap: (Item) -> Unit) {
    var term by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Item>?>(null) }
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    LaunchedEffect(term) {
        if (term.trim().length < 2) { results = null; return@LaunchedEffect }
        kotlinx.coroutines.delay(300)
        results = state.visible(runCatching { server.search(userId, term.trim()) }.getOrDefault(emptyList()))
            .filter { it.isPlayable || it.isSeries }
    }
    androidx.compose.material3.OutlinedTextField(term, { term = it }, singleLine = true,
        placeholder = { Text("Films, shows, people…", color = Palette.textSecondary) },
        leadingIcon = { Icon(Icons.Default.Search, null, tint = Palette.textSecondary) },
        shape = RoundedCornerShape(50),
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Palette.accent, unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
            focusedTextColor = Palette.textPrimary, unfocusedTextColor = Palette.textPrimary, cursorColor = Palette.accent),
        modifier = Modifier.fillMaxWidth().focusRequester(focus))
    Spacer(Modifier.height(10.dp))
    val list = results
    when {
        list == null -> Text("Type at least two letters", color = Palette.textSecondary, modifier = Modifier.padding(8.dp))
        list.isEmpty() -> Text("Nothing matches “${term.trim()}”", color = Palette.textSecondary, modifier = Modifier.padding(8.dp))
        else -> Posters(list, server, wide = false, chosen, onTap)
    }
}

/** A show's seasons, one chosen, and its episodes. */
@Composable
private fun Episodes(state: AppState, server: Server, userId: String, show: String, chosen: Item?, choose: (Item) -> Unit,
                     play: (Item) -> Unit, back: () -> Unit) {
    var seasons by remember(show) { mutableStateOf<List<Item>>(emptyList()) }
    var season by remember(show) { mutableIntStateOf(0) }
    var episodes by remember(show) { mutableStateOf<List<Item>?>(null) }
    LaunchedEffect(show) {
        seasons = runCatching { server.seasons(userId, show) }.getOrDefault(emptyList())
        // Open on the season of the episode chosen, if one is.
        val at = seasons.indexOfFirst { it.id == chosen?.seasonId }
        if (at >= 0) season = at
    }
    LaunchedEffect(show, season, seasons) {
        episodes = null
        episodes = runCatching { server.episodes(userId, show, seasons.getOrNull(season)?.id) }.getOrDefault(emptyList())
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Pill("‹ Titles", chosen = false, onClick = back)
        Spacer(Modifier.width(10.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(seasons.size) { i -> Pill(seasons[i].name, chosen = i == season) { season = i } }
        }
    }
    Spacer(Modifier.height(10.dp))
    val list = episodes
    if (list == null) Text("Loading…", color = Palette.textSecondary, modifier = Modifier.padding(8.dp))
    else Posters(state.visible(list), server, wide = true, chosen) { e -> if (chosen?.id == e.id) play(e) else choose(e) }
}

/** Every place, one touch away; and in the cinema, your seat (elsewhere, the screen's size). */
@Composable
private fun Places(go: (Stage.Place) -> Unit) {
    Text("Where would you like to watch?", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 12.dp))
    val places = Stage.Place.entries
    for (row in places.chunked(3)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 10.dp)) {
            row.forEach { p ->
                val here = p == Stage.place
                val source = remember { MutableInteractionSource() }
                val hovered by source.collectIsHoveredAsState()
                Row(Modifier.width(250.dp).height(64.dp).clip(RoundedCornerShape(14.dp))
                    .background(when { here -> Palette.textPrimary; hovered -> Color.White.copy(alpha = 0.16f); else -> Color.White.copy(alpha = 0.06f) })
                    .hoverable(source).clickable(interactionSource = source, indication = null) { go(p) }
                    .padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    val ink = if (here) Palette.canvas else Palette.textPrimary
                    Icon(placeIcon(p), null, tint = ink, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(p.label.replaceFirstChar { it.uppercase() }, color = ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
    if (Stage.place != Stage.Place.ROOM) {
        val cinema = Stage.place == Stage.Place.CINEMA
        Text(if (cinema) "Your seat" else "The screen", style = MaterialTheme.typography.titleMedium,
            color = Palette.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
        val names = if (cinema) Stage.SEATS else Stage.SIZES
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(names.size) { i -> Pill(names[i], chosen = i == Stage.screenSize) { Stage.sizeTo(i) } }
        }
    }
}

/** What's chosen: its name and a line about it, and Play (or Resume), Start Over, Episodes, My List. */
@Composable
private fun ChosenBar(state: AppState, item: Item, server: Server, onPlay: (Boolean) -> Unit, onEpisodes: () -> Unit) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color.White.copy(alpha = 0.05f)).padding(14.dp)) {
        Text(if (item.isEpisode) item.seriesName ?: item.name else item.name, fontSize = 22.sp, fontWeight = FontWeight.Bold,
            color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        val facts = listOfNotNull(
            item.takeIf { it.isEpisode }?.let { listOfNotNull(it.episodeLabel, it.name).joinToString(" · ") },
            item.year?.toString(),
            item.runtimeTicks?.let { "${it / TICKS_PER_SECOND / 60} min" },
            item.officialRating,
        ).joinToString("  ·  ")
        if (facts.isNotEmpty()) Text(facts, fontSize = 14.sp, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp))
        item.overview?.let {
            Text(it, fontSize = 14.sp, lineHeight = 19.sp, color = Palette.textSecondary.copy(alpha = 0.85f), maxLines = 2,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 6.dp))
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            val resumes = item.isPlayable && item.positionTicks > 0 && (item.progress ?: 0f) < 0.92f
            val left = ((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60
            Action(Icons.Default.PlayArrow, if (resumes) "Resume · $left min left" else "Play", primary = true) { onPlay(false) }
            if (resumes) Action(Icons.Default.Replay, "Start over") { onPlay(true) }
            if (item.isSeries || item.isEpisode) Action(Icons.Default.ViewList, "Episodes", onClick = onEpisodes)
            if (!item.isEpisode) {
                val listed = state.myList.has(item)
                Action(if (listed) Icons.Default.Check else Icons.Default.Add, "My List") {
                    scope.launch { runCatching { state.changeMyList(item) } }
                }
            }
        }
    }
}

@Composable
private fun Action(icon: ImageVector, label: String, primary: Boolean = false, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when { primary -> Palette.textPrimary; hovered -> Color.White.copy(alpha = 0.2f); else -> Color.White.copy(alpha = 0.09f) }
    val ink = if (primary) Palette.canvas else Palette.textPrimary
    Row(Modifier.height(48.dp).clip(RoundedCornerShape(50)).background(ground).hoverable(source)
        .clickable(interactionSource = source, indication = null, onClick = onClick).padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = ink, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, color = ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

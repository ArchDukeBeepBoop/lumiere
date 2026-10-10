@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.ui.ExperimentalComposeUiApi::class)

package app.lumiere.android.tv

import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.border
import app.lumiere.android.cache.childrenOrSaved
import app.lumiere.android.cache.episodesOrSaved
import app.lumiere.android.cache.itemOrSaved
import app.lumiere.android.cache.seasonsOrSaved

import androidx.compose.ui.focus.focusProperties
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.RemoveDone
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.focus.focusRestorer
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
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.extras
import app.lumiere.android.api.personImage
import app.lumiere.android.api.setFavorite
import app.lumiere.android.api.similar
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/**
 * A title on the TV, in the spotlight's style: the backdrop fills the screen,
 * the logo, facts and story sit low on the left, and Play or Resume has focus
 * on arrival. Below: seasons as tabs and episodes as stills with progress,
 * then the cast, Extras and More Like This.
 */
@Composable
fun TvDetailScreen(state: AppState, id: String, refreshKey: Int, startSeason: String? = null) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    var item by remember { mutableStateOf<Item?>(null) }
    var seasons by remember { mutableStateOf<List<Item>>(emptyList()) }
    var season by remember { mutableStateOf<Item?>(null) }
    var episodes by remember { mutableStateOf<List<Item>>(emptyList()) }
    var children by remember { mutableStateOf<List<Item>>(emptyList()) }
    var similar by remember { mutableStateOf<List<Item>>(emptyList()) }
    var extras by remember { mutableStateOf<List<Item>>(emptyList()) }
    var nextUp by remember { mutableStateOf<Item?>(null) }
    var missing by remember { mutableStateOf(false) }

    LaunchedEffect(id, refreshKey) {
        val found = runCatching { state.itemOrSaved(id) }.getOrElse { missing = true; null } ?: return@LaunchedEffect
        missing = false
        item = found
        app.lumiere.android.ui.Marquee.show(found)
        if (found.isSeries) {
            // Specials always last, so a show never opens on them; newest first when asked for this show.
            seasons = state.seasonsOrSaved(id).sortedWith(compareBy { (it.indexNumber ?: 0) == 0 || it.name.contains("Special", true) })
                .let { all -> if (state.settings.seasonsNewestFirst(id)) all.filter { (it.indexNumber ?: 0) != 0 }.reversed() + all.filter { (it.indexNumber ?: 0) == 0 } else all }
            season = season?.let { s -> seasons.firstOrNull { it.id == s.id } }
                ?: startSeason?.let { s -> seasons.firstOrNull { it.id == s } }
                ?: seasons.firstOrNull { (it.unplayedCount ?: 0) > 0 } ?: seasons.firstOrNull()
            nextUp = runCatching { server.nextUp(userId).firstOrNull { it.seriesId == id } }.getOrNull()
        } else if (found.isFolder) children = state.childrenOrSaved(id)
        similar = state.visible(runCatching { server.similar(userId, id) }.getOrDefault(emptyList()))
        extras = server.extras(userId, id)
    }
    LaunchedEffect(season?.id, refreshKey) {
        val s = season ?: return@LaunchedEffect
        episodes = runCatching { state.episodesOrSaved(id, s.id) }.getOrDefault(emptyList())
    }

    // A title the Mac no longer has, or can't reach: said plainly, with a way on.
    if (item == null && missing) return MissingTitle(state)
    val current = item ?: return Box(Modifier.fillMaxSize().background(Palette.canvas))
    val list = rememberLazyListState()
    var topFocused by remember { mutableStateOf(true) }
    val topFirst = remember { FocusRequester() }
    val scope2 = rememberCoroutineScope()
    var below by remember { mutableStateOf(0) }
    var section by remember { mutableStateOf(0) }
    var onlyUnwatched by remember { mutableStateOf(false) }
    LaunchedEffect(topFocused) { if (topFocused) list.animateScrollToItem(0) }

    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.canvas)) {
        AsyncImage(imageFor(current, server, CardShape.Wide, 1600), null, contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to Palette.canvas.copy(alpha = 0.95f), 0.6f to Color.Transparent)))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient((if (topFocused) 0.5f else 0.1f) to Color.Transparent, 0.95f to Palette.canvas)))
        val h = maxHeight
        // Up from the first row returns to the buttons, which the tall top has
        // scrolled out of the list's reach.
        // The page moves only when what is chosen is off screen: moving along
        // the episodes no longer nudges the whole page each time.
        val still = remember { object : androidx.compose.foundation.gestures.BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float = when {
                app.lumiere.android.ui.Pointing.byPointer -> 0f
                offset >= 0f && offset + size <= containerSize -> 0f
                offset < 0f -> offset
                else -> offset + size - containerSize
            }
        } }
        @OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides still) {
        LazyColumn(Modifier.onPreviewKeyEvent { e ->
            if (e.nativeKeyEvent.keyCode == android.view.KeyEvent.KEYCODE_DPAD_UP &&
                e.nativeKeyEvent.action == android.view.KeyEvent.ACTION_DOWN && !topFocused && below == 1) {
                scope2.launch { list.animateScrollToItem(0); kotlinx.coroutines.delay(80); runCatching { topFirst.requestFocus() } }
                true
            } else false
        }, state = list, contentPadding = PaddingValues(bottom = 60.dp)) {
            item {
                Top(state, current, nextUp, Modifier.height(h * 0.86f).onFocusChanged { topFocused = it.hasFocus }, topFirst,
                    inOrder = if (current.type == "BoxSet") children.filter { it.isPlayable }.sortedBy { it.year ?: 9999 }.let { c -> c.firstOrNull { !it.played } ?: c.firstOrNull() } else null,
                    onFavourite = { fav -> scope.launch { server.setFavorite(current.id, fav); item = current.copy(favorite = fav) } },
                    onPlayed = { p -> scope.launch { server.setPlayed(current.id, p); item = current.copy(played = p) } })
            }
            if (seasons.isNotEmpty()) {
                item {
                    LazyRow(Modifier.onFocusChanged { if (it.hasFocus) below = 1 }.focusRestorer(), contentPadding = PaddingValues(horizontal = 56.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(seasons, key = { it.id }) { s ->
                            // "Season 2 · 6 of 10": how far through each one is, at a glance.
                            val total = s.childCount; val left = s.unplayedCount
                            // How far through it, as a thin line under the name — Apple's way, no numbers.
                            val done = if (total != null && total > 0 && left != null) (total - left).toFloat() / total else null
                            LChip(s.id == season?.id, { season = s }, {
                                androidx.compose.foundation.layout.Column {
                                    Text(s.name + if (done == 1f) "  ✓" else "")
                                    if (done != null && done > 0f && done < 1f) Box(Modifier.padding(top = 3.dp).width(56.dp).height(2.dp)
                                        .background(androidx.compose.material3.LocalContentColor.current.copy(alpha = 0.25f))) {
                                        Box(Modifier.fillMaxWidth(done).height(2.dp).background(androidx.compose.material3.LocalContentColor.current))
                                    }
                                }
                            })
                        }
                        // Watched or not, one pill each: the episode row filtered, and the season marked.
                        if (seasons.size > 2) item(key = "order") {
                            LChip(state.settings.seasonsNewestFirst(id), {
                                state.settings.setSeasonsNewestFirst(id, !state.settings.seasonsNewestFirst(id)); seasons = seasons.filter { (it.indexNumber ?: 0) != 0 }.reversed() + seasons.filter { (it.indexNumber ?: 0) == 0 }
                            }, { Text("Newest First") })
                        }
                        item(key = "unwatched") { LChip(onlyUnwatched, { onlyUnwatched = !onlyUnwatched }, { Text("Unwatched") }) }
                        item(key = "markseason") {
                            LChip(false, {
                                val all = episodes; val toPlayed = all.any { !it.played }
                                scope.launch {
                                    all.forEach { e -> runCatching { server.setPlayed(e.id, toPlayed) } }
                                    episodes = all.map { it.copy(played = toPlayed, positionTicks = 0) }
                                    state.homeRefresh++
                                }
                            }, { Text(if (episodes.isNotEmpty() && episodes.all { it.played }) "Mark Season Unwatched" else "Mark Season Watched") })
                        }
                    }
                }
                item {
                    // Back on a show, the row opens where it was left.
                    val rowState = androidx.compose.foundation.lazy.rememberLazyListState()
                    LaunchedEffect(episodes) {
                        val at = episodes.indexOfFirst { it.id == state.lastEpisode[id] }
                        if (at > 0) rowState.scrollToItem(at)
                    }
                    // A long season: pills to jump along it ten at a time.
                    val shownEps = episodes.filter { !onlyUnwatched || !it.played }
                    if (shownEps.size > 20) LazyRow(contentPadding = PaddingValues(horizontal = 56.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items((shownEps.indices step 10).toList()) { from ->
                            app.lumiere.android.ui.TvPill({ scope.launch { rowState.scrollToItem(from) } }) {
                                Text("${shownEps[from].indexNumber ?: from + 1}–${shownEps[minOf(from + 9, shownEps.lastIndex)].indexNumber ?: minOf(from + 10, shownEps.size)}")
                            }
                        }
                    }
                    LazyRow(Modifier.onFocusChanged { if (it.hasFocus) below = 2 }
                        // Past either end of a season: the next or previous one, as tvOS turns them.
                        .onPreviewKeyEvent { ev ->
                            val k = ev.nativeKeyEvent
                            if (k.action != android.view.KeyEvent.ACTION_DOWN || episodes.isEmpty()) return@onPreviewKeyEvent false
                            val at = seasons.indexOfFirst { it.id == season?.id }
                            val onId = state.lastEpisode[id]
                            when {
                                k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_RIGHT && onId == episodes.last().id && at in 0 until seasons.lastIndex -> {
                                    season = seasons[at + 1]; state.lastEpisode.remove(id); true }
                                k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_LEFT && onId == episodes.first().id && at > 0 -> {
                                    season = seasons[at - 1]; state.lastEpisode.remove(id); true }
                                else -> false
                            }
                        }
                        .focusRestorer().focusProperties {
                        @OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
                        exit = { d -> if (d == androidx.compose.ui.focus.FocusDirection.Left || d == androidx.compose.ui.focus.FocusDirection.Right)
                            androidx.compose.ui.focus.FocusRequester.Cancel else androidx.compose.ui.focus.FocusRequester.Default }
                    }, state = rowState, contentPadding = PaddingValues(horizontal = 56.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                        items(episodes.filter { !onlyUnwatched || !it.played }, key = { it.id }) { e -> Box(Modifier.onFocusChanged { if (it.hasFocus) state.lastEpisode[id] = e.id }) { Episode(e, state, next = e.id == nextUp?.id) } }
                    }
                }
            }
            // Each later row: 1 when it is the first below the top (a film has no seasons).
            var next = if (seasons.isNotEmpty()) 3 else 1
            if (children.isNotEmpty()) { val n = next++; item(key = "contents") { Box(Modifier.onFocusChanged { if (it.hasFocus) below = n }) { Row("Contents", children, state) } } }
            // Cast, extras and similar titles behind one row of pills, as the
            // Apple TV app switches them — a shorter page, one section at a time.
            val sections = listOfNotNull<Pair<String, @Composable () -> Unit>>(
                if (current.people.isNotEmpty()) "Cast & Crew" to { Cast(current, state) } else null,
                if (extras.isNotEmpty()) "Extras" to { Row("Extras", extras, state, play = true) } else null,
                if (similar.isNotEmpty()) "More Like This" to { Row("More Like This", similar, state) } else null,
            )
            if (sections.isNotEmpty()) {
                val tabsAt = next++
                val blockAt = next++
                item(key = "tabs") {
                    LazyRow(Modifier.padding(top = 18.dp).onFocusChanged { if (it.hasFocus) below = tabsAt }.focusRestorer(),
                        contentPadding = PaddingValues(horizontal = 50.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(sections.size) { i ->
                            app.lumiere.android.ui.TvPill({ section = i }, Modifier.onFocusChanged { if (it.isFocused && !app.lumiere.android.ui.Pointing.byPointer) section = i },
                                selected = section == i) { Text(sections[i].first) }
                        }
                    }
                }
                item(key = "section") {
                    Box(Modifier.onFocusChanged { if (it.hasFocus) below = blockAt }) { sections.getOrNull(section)?.second?.invoke() }
                }
            }
            item(key = "info") { Information(current) }
        }
        }
    }
}

@Composable
private fun Top(state: AppState, item: Item, nextUp: Item?, modifier: Modifier, first: FocusRequester, inOrder: Item? = null,
                onFavourite: (Boolean) -> Unit, onPlayed: (Boolean) -> Unit) {
    val server = state.server ?: return
    LaunchedEffect(item.id) { kotlinx.coroutines.delay(150); runCatching { first.requestFocus() } }
    Box(modifier.fillMaxWidth()) {
        Column(Modifier.align(Alignment.BottomStart).padding(start = 56.dp, bottom = 24.dp).widthIn(max = 680.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item.seriesName?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = Palette.accent) }
            if (item.logoTag != null && !item.isEpisode) {
                AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 760), item.name, contentScale = ContentScale.Fit,
                    alignment = Alignment.BottomStart, modifier = Modifier.height(120.dp).widthIn(max = 440.dp))
            } else {
                Text(item.name, maxLines = 2, overflow = TextOverflow.Ellipsis, style = TextStyle(fontSize = 44.sp,
                    fontWeight = FontWeight.SemiBold, color = Color.White, shadow = Shadow(Color.Black.copy(alpha = 0.6f), blurRadius = 12f)))
            }
            app.lumiere.android.ui.FactPills(listOfNotNull(item.episodeLabel, item.year?.toString()).joinToString("  ·  ").ifEmpty { null },
                item.runtimeTicks?.let { val m = it / TICKS_PER_SECOND / 60; if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m" },
                item.officialRating, listOfNotNull(item.genres.take(3).joinToString(", ").ifEmpty { null },
                    item.communityRating?.let { "★ %.1f".format(it) }))
            item.overview?.let { Text(it, maxLines = 4, overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 16.sp, lineHeight = 23.sp, color = Color.White.copy(alpha = 0.85f))) }
            val target = if (item.isSeries) nextUp else item
            // A collection: its titles in release order, the first not yet watched.
            if (inOrder != null) {
                val first = inOrder
                app.lumiere.android.ui.TvPill({ state.push(Screen.Player(first.id, null)) }, selected = true) {
                    Text("▶  Play in Order · ${first.name}")
                }
            }
            // Play takes the show's own colour, lifted toward the accent so it reads as the button.
            val context = androidx.compose.ui.platform.LocalContext.current
            val showTint by androidx.compose.runtime.produceState<Color?>(null, item.id) {
                value = app.lumiere.android.ui.Ambient.average(context, app.lumiere.android.ui.imageFor(item, server, app.lumiere.android.ui.CardShape.Wide, 64))
                    ?.let { androidx.compose.ui.graphics.lerp(it, Palette.accent, 0.45f) }
            }
            // An unwatched show says where it begins, as Apple's "Start Watching" does.
            if (item.isSeries && target != null && target.positionTicks == 0L && target.indexNumber == 1 && (target.parentIndexNumber ?: 1) <= 1 && !target.played)
                Text("Start with ${target.episodeLabel ?: "the first episode"}" + (target.runtimeTicks?.let { " · ${it / TICKS_PER_SECOND / 60} min" } ?: ""),
                    style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.8f))
            // The first seconds fetched ahead while the page is read, so Play starts sooner.
            LaunchedEffect(target?.id) {
                val t = target ?: return@LaunchedEffect
                kotlinx.coroutines.delay(1500)
                state.session?.userId?.let { u -> app.lumiere.android.player.Playback.warm(server, u, t) }
            }
            // The show's languages as last chosen, as a pill: Back to default with OK.
            if (item.isSeries) state.settings.tracksFor(item.id)?.let { (a, t) ->
                fun lang(c: String?) = c?.let { java.util.Locale.forLanguageTag(it).displayLanguage.ifEmpty { it } }
                val label = listOfNotNull(lang(a), when (t) { null -> null; "off" -> "No subtitles"; else -> "${lang(t)} subtitles" })
                    .joinToString(" · ")
                if (label.isNotEmpty()) Text(label, style = MaterialTheme.typography.labelLarge, color = Palette.textSecondary,
                    modifier = Modifier.background(Color.White.copy(alpha = 0.12f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                        .padding(horizontal = 14.dp, vertical = 6.dp))
            }
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    val target = if (item.isSeries) nextUp else item
                    // Nearly over: starting again is likelier than the last minutes.
                    val nearEnd = !item.isSeries && (target?.progress ?: 0f) > 0.9f
                    val resume = target != null && target.positionTicks > 0 && !nearEnd
                    LButton(modifier = Modifier.focusRequester(first), tint = showTint, onClick = {
                        target?.let { state.push(Screen.Player(it.id, if (nearEnd) 0.0 else null)) } ?: state.push(Screen.Detail(item.id))
                    }) {
                        Text(when {
                            target == null -> "▶  Play"
                            nearEnd -> "▶  Start Over"
                            item.isSeries -> (if (resume) "▶  Resume " else "▶  Play ") + (target.episodeLabel ?: "")
                            resume -> "▶  Resume · ${((target.runtimeTicks ?: 0) - target.positionTicks) / TICKS_PER_SECOND / 60} min left"
                            else -> "▶  Play"
                        })
                    }
                }
                // A finished show: from the beginning again, the history left as it is.
                if (item.isSeries && item.played) item {
                    val scope = androidx.compose.runtime.rememberCoroutineScope()
                    Round(androidx.compose.material.icons.Icons.Default.Replay, "Watch Again") {
                        scope.launch {
                            val uid = state.session?.userId ?: return@launch
                            runCatching { server.episodes(uid, item.id, null) }.getOrNull()?.firstOrNull()
                                ?.let { state.push(Screen.Player(it.id, 0.0)) }
                        }
                    }
                }
                // Round icon buttons beside the big one, named beneath — the Apple TV app's row.
                if (item.isPlayable && item.positionTicks > 0) item {
                    Round(androidx.compose.material.icons.Icons.Default.Replay, "Start Over") { state.push(Screen.Player(item.id, 0.0)) }
                }
                if (item.isPlayable) item {
                    Round(if (item.played) androidx.compose.material.icons.Icons.Default.RemoveDone else androidx.compose.material.icons.Icons.Default.Done,
                        if (item.played) "Unwatched" else "Watched") { onPlayed(!item.played) }
                }
                item {
                    Round(if (item.favorite) androidx.compose.material.icons.Icons.Default.Star else androidx.compose.material.icons.Icons.Default.StarBorder,
                        "Favourite") { onFavourite(!item.favorite) }
                }
                item { Round(androidx.compose.material.icons.Icons.Default.MoreHoriz, "More") { state.actionsFor = item } }
            }
        }
    }
}

@Composable
private fun Episode(e: Item, state: AppState, next: Boolean = false) {
    val server = state.server ?: return
    // Apple TV's episode: a wide still, then its number, name, length and a
    // few lines of what happens, so a season reads without opening each one.
    Column(Modifier.width(320.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard({}, {
            state.push(if (state.settings.episodesOpenPage) Screen.Detail(e.id) else Screen.Player(e.id, null)) }) { state.actionsFor = e }
            // The one to watch next, outlined in gold so it is found at a glance.
            .then(if (next) Modifier.border(2.dp, Palette.accent.copy(alpha = 0.8f), RoundedCornerShape(10.dp)) else Modifier)
            .background(Palette.surface)) {
            AsyncImage(imageFor(e, server, CardShape.Wide, 560), e.name, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
            e.progress?.let { p ->
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.Black.copy(alpha = 0.55f))) {
                    Box(Modifier.fillMaxWidth(p).height(4.dp).background(Palette.accent))
                }
            }
            if (e.played) Text("✓", color = Palette.onAccent, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp)
                .background(Palette.accent, CircleShape).padding(horizontal = 6.dp))
        }
        Spacer(Modifier.height(8.dp))
        val hidden = state.settings.hidesSpoilers && !e.played && e.positionTicks == 0L
        Text(if (hidden) "Episode ${e.indexNumber ?: ""}" else listOfNotNull(e.indexNumber?.let { "$it." }, e.name).joinToString(" "), maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Palette.textPrimary))
        e.runtimeTicks?.let { Text("${it / TICKS_PER_SECOND / 60} min", style = MaterialTheme.typography.labelMedium) }
        if (!hidden) e.overview?.let { Text(it, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall,
            color = Palette.textSecondary, modifier = Modifier.padding(top = 4.dp)) }
    }
}

@Composable
private fun Row(title: String, items: List<Item>, state: AppState, play: Boolean = false) {
    val server = state.server ?: return
    Column(Modifier.padding(top = 16.dp)) {
        Text(title, style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
            modifier = Modifier.padding(start = 56.dp))
        LazyRow(Modifier.focusRestorer(), contentPadding = PaddingValues(horizontal = 56.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            items(items, key = { it.id }) { it ->
                Column(Modifier.width(if (play) 260.dp else 150.dp)) {
                    Box(Modifier.fillMaxWidth().aspectRatio(if (play) 16f / 9f else 2f / 3f)
                        .focusCard({}, { state.push(if (play) Screen.Player(it.id, 0.0) else Screen.Detail(it.id)) }) { state.actionsFor = it }
                        .background(Palette.surface)) {
                        AsyncImage(imageFor(it, server, if (play) CardShape.Wide else CardShape.Poster, 400), it.name,
                            contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(it.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium.copy(color = Palette.textPrimary))
                }
            }
        }
    }
}

@Composable
private fun Cast(item: Item, state: AppState) {
    val server = state.server ?: return
    Column(Modifier.padding(top = 16.dp)) {
        Text("Cast & Crew", style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
            modifier = Modifier.padding(start = 56.dp))
        LazyRow(Modifier.focusRestorer(), contentPadding = PaddingValues(start = 56.dp, end = 56.dp, top = 14.dp, bottom = 28.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            items(item.people.take(30), key = { it.id + (it.role ?: "") }) { p ->
                // People as Apple shows them on a TV: portrait photos with the
                // poster's own white ring, and the name kept inside the row.
                // Apple's circle: the photo round, ringed in white when chosen. The whole
                // card — photo and names — takes the remote, so scrolling to it brings the
                // names into view too and nothing is cut at the bottom of the page.
                var on by remember { mutableStateOf(false) }
                val lift by androidx.compose.animation.core.animateFloatAsState(if (on) 1.1f else 1f, label = "cast")
                Column(Modifier.width(120.dp).onFocusChanged { on = it.isFocused }
                    .clickable { state.push(Screen.Person(p.id, p.name)) }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(104.dp).graphicsLayer { scaleX = lift; scaleY = lift }.clip(CircleShape).background(Palette.surface)
                        .border(3.dp, if (on) Color.White else Color.Transparent, CircleShape), contentAlignment = Alignment.Center) {
                        Text(p.name.split(' ').mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString(""))
                        if (p.imageTag != null) AsyncImage(server.personImage(p.id, p.imageTag), p.name, contentScale = ContentScale.Crop,
                            modifier = Modifier.matchParentSize())
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(p.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium.copy(
                        color = if (on) Color.White else Palette.textPrimary))
                    Text(p.role?.takeIf { it.isNotBlank() && p.type == "Actor" }?.let { "as $it" } ?: p.role ?: p.type ?: "", maxLines = 1,
                        overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable
private fun Round(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        app.lumiere.android.ui.LIconButton(onClick = onClick, modifier = Modifier.size(52.dp)
            .background(Color.White.copy(alpha = 0.14f), CircleShape)) {
            androidx.compose.material3.Icon(icon, label, tint = app.lumiere.android.ui.pillTint(Color.White))
        }
        Text(label, style = MaterialTheme.typography.labelMedium)
    }
}

/**
 * The page's last section, as the Apple TV app ends its: the facts in quiet
 * columns — genres, studio, release, rating, length, and what the file holds.
 */
@Composable
private fun Information(item: Item) {
    val video = item.streams.firstOrNull { it.type == "Video" }
    val audio = item.streams.filter { it.type == "Audio" }
    val subs = item.streams.filter { it.type == "Subtitle" }
    fun lang(c: String?) = c?.let { java.util.Locale.forLanguageTag(it).displayLanguage.ifEmpty { it } }
    val facts = listOfNotNull(
        item.genres.takeIf { it.isNotEmpty() }?.let { "Genres" to it.joinToString(", ") },
        item.studios.takeIf { it.isNotEmpty() }?.let { "Studio" to it.joinToString(", ") },
        item.year?.let { "Released" to "$it" },
        item.officialRating?.let { "Rated" to it },
        item.communityRating?.let { "Rating" to "★ %.1f".format(it) },
        item.runtimeTicks?.let { "Length" to "${it / TICKS_PER_SECOND / 60} min" },
        video?.let { v -> "Video" to listOfNotNull(v.codec?.uppercase(), v.width?.let { w -> "${w}×${v.height}" },
            v.bitDepth?.takeIf { it > 8 }?.let { "$it-bit" }).joinToString(" · ") },
        audio.takeIf { it.isNotEmpty() }?.let { "Audio" to it.mapNotNull { a -> lang(a.language) ?: a.title }.distinct().joinToString(", ") },
        subs.takeIf { it.isNotEmpty() }?.let { "Subtitles" to it.mapNotNull { s -> lang(s.language) ?: s.title }.distinct().joinToString(", ") },
    )
    if (facts.isEmpty()) return
    Column(Modifier.padding(start = 56.dp, end = 56.dp, top = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Information", style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
        facts.chunked(3).forEach { row ->
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(40.dp)) {
                row.forEach { (k, v) ->
                    Column(Modifier.width(300.dp)) {
                        Text(k, style = MaterialTheme.typography.labelMedium)
                        Text(v, style = MaterialTheme.typography.bodyMedium.copy(color = Palette.textSecondary), maxLines = 2)
                    }
                }
            }
        }
    }
}

@Composable
private fun MissingTitle(state: AppState) {
    val back = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { back.requestFocus() } }
    Column(Modifier.fillMaxSize().background(Palette.canvas).padding(56.dp), verticalArrangement = Arrangement.Center) {
        Text("This title isn't on the Mac any more", style = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
        Text("It may have been moved or removed, or the Mac may be asleep.", style = MaterialTheme.typography.bodyMedium,
            color = Palette.textSecondary, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
        androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            app.lumiere.android.ui.TvPill({ state.pop() }, Modifier.focusRequester(back), selected = true) { Text("Back") }
            app.lumiere.android.ui.TvPill({ state.tab(Screen.Search) }) { Text("Search for it") }
        }
    }
}

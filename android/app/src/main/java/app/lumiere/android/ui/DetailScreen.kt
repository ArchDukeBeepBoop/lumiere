package app.lumiere.android.ui

import app.lumiere.android.cache.childrenOrSaved
import app.lumiere.android.cache.episodesOrSaved
import app.lumiere.android.cache.itemOrSaved
import app.lumiere.android.cache.seasonsOrSaved
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.extras
import app.lumiere.android.api.itemJson
import app.lumiere.android.api.similar
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/**
 * A title on a phone, as the Apple TV app shows one on an iPhone: the picture
 * full-bleed under the status bar, the page beneath tinted with its colour;
 * the logo, what it is, a white Play (or Resume, or the show's next episode)
 * beside "+" for Up Next and the download arrow; the story, the badges; a
 * show's seasons behind a "Season ⌄" menu with its episodes in a row; the
 * cast, bonus content, related titles, and Apple's Information and Languages
 * at the foot. "…" at the top holds everything else.
 */
@Composable
fun DetailScreen(state: AppState, id: String, refreshKey: Int) {
    val server = state.server ?: return
    val session = state.session ?: return
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var item by remember { mutableStateOf<Item?>(null) }
    var seasons by remember { mutableStateOf<List<Item>>(emptyList()) }
    var season by remember { mutableStateOf<Item?>(null) }
    var episodes by remember { mutableStateOf<List<Item>>(emptyList()) }
    var children by remember { mutableStateOf<List<Item>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var similar by remember { mutableStateOf<List<Item>>(emptyList()) }
    var extras by remember { mutableStateOf<List<Item>>(emptyList()) }
    var next by remember { mutableStateOf<Item?>(null) }
    var tint by remember { mutableStateOf<Color?>(null) }

    LaunchedEffect(id, refreshKey) {
        runCatching { state.itemOrSaved(id) }
            .onSuccess { found ->
                item = found
                when {
                    found.isSeries -> {
                        seasons = state.seasonsOrSaved(id)
                        season = season?.let { s -> seasons.firstOrNull { it.id == s.id } }
                            ?: seasons.firstOrNull { (it.unplayedCount ?: 0) > 0 } ?: seasons.firstOrNull()
                        next = runCatching { server.nextUp(session.userId).firstOrNull { it.seriesId == id } }.getOrNull()
                    }
                    found.isFolder -> children = state.childrenOrSaved(id)
                }
            }
            .onFailure { error = it.message }
        similar = state.visible(runCatching { server.similar(session.userId, id) }.getOrDefault(emptyList()))
        extras = runCatching { server.extras(session.userId, id) }.getOrDefault(emptyList())
    }
    // The page takes the picture's colour, as Apple's do.
    LaunchedEffect(item?.id) {
        val it = item ?: return@LaunchedEffect
        tint = runCatching { Ambient.average(context, imageFor(it, server, CardShape.Wide, 200)) }.getOrNull()
    }
    LaunchedEffect(season?.id, refreshKey) {
        val s = season ?: return@LaunchedEffect
        episodes = runCatching { state.episodesOrSaved(id, s.id) }.getOrDefault(emptyList())
    }

    val current = item
    val ground = tint?.let { lerp(Color.Black, it, 0.38f) } ?: Palette.canvas
    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        if (current == null) {
            if (error != null) Text(error!!, Modifier.align(Alignment.Center).padding(24.dp), color = Palette.textSecondary)
            else CircularProgressIndicator(Modifier.align(Alignment.Center), color = Palette.textSecondary)
            BackCircle(state, Modifier.statusBarsPadding().padding(10.dp))
            return@Box
        }
        // The tint, falling from behind the picture into black down the page.
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to ground, 0.55f to ground, 1f to Palette.canvas)))
        val list = rememberLazyListState()
        // The bar settles in as the picture's foot passes under it.
        val hero = heroHeight(0.9f)
        val heroPx = with(androidx.compose.ui.platform.LocalDensity.current) { hero.toPx() }
        val shown by remember { derivedStateOf {
            if (list.firstVisibleItemIndex > 0) 1f
            else ((list.firstVisibleItemScrollOffset - heroPx * 0.6f) / (heroPx * 0.2f)).coerceIn(0f, 1f)
        } }
        LazyColumn(state = list, contentPadding = PaddingValues(bottom = 48.dp)) {
            item(key = "hero") { Hero(current, state, ground, list) }
            item(key = "actions") {
                Actions(current, state, next) { played ->
                    scope.launch { state.ledger.setPlayed(server, current.id, played); item = current.copy(played = played) }
                }
            }
            item(key = "about") { About(current) }
            if (current.isSeries && seasons.isNotEmpty()) item(key = "episodes") {
                Episodes(state, current, seasons, season, episodes, next, onSeason = { season = it }) { e, played ->
                    scope.launch {
                        state.ledger.setPlayed(server, e.id, played)
                        episodes = episodes.map { if (it.id == e.id) it.copy(played = played) else it }
                    }
                }
            }
            if (children.isNotEmpty()) item(key = "contents") {
                PhoneRow("Contents") { items(children, key = { it.id }) { ItemCard(it, server, CardShape.Poster) { state.push(Screen.Detail(it.id)) } } }
            }
            if (current.people.isNotEmpty()) item(key = "cast") { Cast(current, state) }
            if (extras.isNotEmpty()) item(key = "extras") {
                PhoneRow("Bonus Content") { items(extras, key = { it.id }) { ItemCard(it, server, CardShape.Wide) { state.push(Screen.Player(it.id, 0.0)) } } }
            }
            if (similar.isNotEmpty()) item(key = "related") {
                PhoneRow("Related") { items(similar, key = { it.id }) { ItemCard(it, server, CardShape.Poster) { state.push(Screen.Detail(it.id)) } } }
            }
            item(key = "info") { Information(current, episodes.firstOrNull()) }
        }
        IosTopBar(shown, current.name,
            leading = { BackCircle(state, Modifier, filled = shown < 0.5f) },
            trailing = {
                IosCircle(Icons.Default.MoreHoriz, "More", { PhoneMenu.item = current }, size = 34,
                    modifier = Modifier.background(Color.Black.copy(alpha = 0.3f * (1f - shown)), androidx.compose.foundation.shape.CircleShape))
            })
    }
}

/** iOS's back chevron in a frosted circle over the picture. */
@Composable
private fun BackCircle(state: AppState, modifier: Modifier, filled: Boolean = true) {
    IosCircle(Icons.AutoMirrored.Filled.ArrowBack, "Back", { state.pop() }, modifier = modifier
        .background(Color.Black.copy(alpha = if (filled) 0.3f else 0f), androidx.compose.foundation.shape.CircleShape), size = 34)
}

/** The picture, moving at half the page's speed, the logo or name over its foot, what it is beneath. */
@Composable
private fun Hero(item: Item, state: AppState, ground: Color, list: androidx.compose.foundation.lazy.LazyListState) {
    val server = state.server ?: return
    Box(Modifier.fillMaxWidth().height(heroHeight(0.9f))) {
        AsyncImage(imageFor(item, server, CardShape.Wide, 1400), null, contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize().graphicsLayer {
                if (list.firstVisibleItemIndex == 0 && !app.lumiere.android.Motion.reduced) translationY = list.firstVisibleItemScrollOffset * 0.5f
            })
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(
            0f to Color.Black.copy(alpha = 0.5f), 0.2f to Color.Transparent, 0.55f to Color.Transparent,
            0.85f to ground.copy(alpha = 0.9f), 1f to ground)))
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (item.isEpisode) item.seriesName?.let { name ->
                Text(name, style = IosType.headline, color = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.clickable { item.seriesId?.let { state.push(Screen.Detail(it)) } })
            }
            if (item.logoTag != null && !item.isEpisode) {
                AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 700), item.name, contentScale = ContentScale.Fit,
                    modifier = Modifier.height(92.dp).fillMaxWidth(0.75f))
            } else {
                Text(item.name, style = IosType.largeTitle.copy(fontSize = 28.sp, lineHeight = 33.sp), color = Color.White,
                    textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            IosCaption(listOfNotNull(
                when { item.isSeries -> "TV Show"; item.isEpisode -> episodeShort(item); item.type == "Movie" -> "Movie"; else -> null },
                item.genres.take(2).joinToString(", ").ifEmpty { null }, item.year?.toString(),
                item.runtimeTicks?.takeIf { it >= TICKS_PER_SECOND * 60 }?.let { minutes(it / TICKS_PER_SECOND / 60) },
            ).joinToString(" · "), color = Color.White.copy(alpha = 0.75f))
        }
    }
}

/** Play — or Resume, or the show's next episode — with "+" for Up Next and the download arrow. */
@Composable
private fun Actions(item: Item, state: AppState, next: Item?, onPlayed: (Boolean) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            val target = if (item.isSeries) next else item.takeIf { it.isPlayable }
            val label = when {
                target == null && item.isSeries -> "Play"
                target == null -> null
                target.positionTicks > 0 -> "Resume" + (if (item.isSeries) " ${episodeShort(target) ?: ""}" else "")
                item.isSeries -> "Play ${episodeShort(target) ?: ""}"
                else -> "Play"
            }
            if (label != null) IosButton(label.trim(), {
                when {
                    target != null -> state.push(Screen.Player(target.id, null))
                    item.isSeries -> scope.launch { playSeries(state, item) }
                }
            }, Modifier.weight(1f), icon = Icons.Default.PlayArrow)
            if (!state.roomOpen && (item.isPlayable || item.isSeries) && item.positionTicks == 0L) {
                val listed = item.id in state.settings.watchlist
                IosCircle(if (listed) Icons.Default.Check else Icons.Default.Add, if (listed) "Remove from Up Next" else "Add to Up Next", {
                    val before = state.settings.watchlist
                    state.settings.watchlist = if (listed) before - item.id else listOf(item.id) + before
                    PhoneNotice.show(if (listed) "Removed from Up Next" else "Added to Up Next") { state.settings.watchlist = before }
                }, size = 48)
            }
            if (item.isPlayable) {
                val saved = state.downloads.find(item.id)
                IosCircle(if (saved != null) Icons.Default.DownloadDone else Icons.Default.Download,
                    if (saved != null) "Downloaded" else "Download", {
                        if (saved != null) state.push(Screen.Downloads)
                        else scope.launch {
                            runCatching { server.itemJson(userId, item.id) }.onSuccess {
                                if (state.downloads.start(server, userId, it, state.settings.downloadsWifiOnly)) PhoneNotice.show("Downloading")
                            }.onFailure { PhoneNotice.show("Couldn't reach the Mac") }
                        }
                    }, size = 48)
            }
        }
        if (item.isPlayable && item.positionTicks > 0) {
            val left = ((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f).height(4.dp).background(Color.White.copy(alpha = 0.25f), androidx.compose.foundation.shape.RoundedCornerShape(50))) {
                    Box(Modifier.fillMaxWidth(item.progress ?: 0f).height(4.dp).background(Color.White, androidx.compose.foundation.shape.RoundedCornerShape(50)))
                }
                Text("${minutes(left)} left", style = IosType.footnote, color = Palette.textSecondary)
                Text("Start Over", style = IosType.footnote, color = Palette.accent,
                    modifier = Modifier.clickable { state.push(Screen.Player(item.id, 0.0)) })
            }
        }
        if (item.isPlayable && item.played) Text("✓ Watched", style = IosType.footnote, color = Palette.textSecondary,
            modifier = Modifier.clickable { onPlayed(false) })
    }
}

/** The story, three lines until tapped, then the badges. */
@Composable
private fun About(item: Item) {
    var open by remember(item.id) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item.overview?.let {
            Text(it, style = IosType.body, color = Palette.textPrimary.copy(alpha = 0.9f), maxLines = if (open) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.clickable { open = !open })
        }
        Badges(item)
    }
}

/** Apple's outlined badges: the rating, 4K or HD, HDR, the sound, CC. */
@Composable
private fun Badges(item: Item) {
    val video = item.streams.firstOrNull { it.type == "Video" }
    val audio = item.streams.filter { it.type == "Audio" }
    val badges = listOfNotNull(
        item.officialRating,
        video?.width?.let { w -> if (w >= 3200) "4K" else if (w >= 1200) "HD" else null },
        if (video?.bitDepth == 10 && video.codec?.lowercase() in setOf("hevc", "h265", "av1", "vp9")) "HDR" else null,
        audio.firstNotNullOfOrNull { a ->
            when (a.codec?.lowercase()) { "truehd" -> "Dolby TrueHD"; "eac3" -> "Dolby Digital+"; "ac3" -> "Dolby Digital"; "dts", "dca" -> "DTS"; else -> null }
        },
        if (item.streams.any { it.type == "Subtitle" }) "CC" else null,
        item.communityRating?.let { "★ %.1f".format(it) },
    )
    if (badges.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        badges.forEach {
            Text(it, style = IosType.caption.copy(fontSize = 10.sp), color = Palette.textSecondary, modifier = Modifier
                .border(1.dp, Palette.textSecondary.copy(alpha = 0.7f), androidx.compose.foundation.shape.RoundedCornerShape(4.dp))
                .padding(horizontal = 5.dp, vertical = 2.dp))
        }
    }
}

@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.SettingsRemote
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.byIds
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * Home on a phone, as the Apple TV app's on an iPhone: the banner full-bleed
 * under the status bar, a bar that settles over the top as the page moves,
 * one Up Next row — what is in progress, what was added to Up Next, the next
 * episodes — then the libraries, what is new in each, the Top 10s, genres and
 * what was watched lately. Pull down to refresh.
 */
@Composable
internal fun PhoneHome(state: AppState, current: HomeRows, extras: PhoneExtras, open: (Item) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    val list = rememberLazyListState()
    val hero = heroHeight(0.84f)
    val heroPx = with(LocalDensity.current) { hero.toPx() }
    val shown by remember { derivedStateOf {
        if (list.firstVisibleItemIndex > 0) 1f else ((list.firstVisibleItemScrollOffset - heroPx * 0.55f) / (heroPx * 0.25f)).coerceIn(0f, 1f)
    } }

    // Up Next additions, never from or in the room.
    var listed by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(state.settings.watchlist, state.roomOpen) {
        listed = if (state.roomOpen) emptyList() else state.visible(runCatching { server.byIds(userId, state.settings.watchlist) }
            .getOrDefault(emptyList())).filter { it.libraryId !in state.privateLibraries }
    }
    fun keep(items: List<Item>) = state.visible(items).filter {
        it.id !in state.justWatched && it.id !in state.settings.notInterested && it.seriesId !in state.settings.notInterested
    }
    val resume = keep(current.resume)
    val nextUp = keep(current.nextUp)
    val upNext = (resume + keep(listed) + nextUp).distinctBy { it.seriesId ?: it.id }

    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(refreshing) { if (refreshing) { delay(1_200); refreshing = false } }

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        PullToRefreshBox(refreshing, onRefresh = { refreshing = true; state.homeRefresh++ }) {
            LazyColumn(state = list, contentPadding = PaddingValues(bottom = 32.dp)) {
                item(key = "hero") {
                    val pool = current.latest.filter { !state.hides(it.first.id) }.flatMap { it.second }.filter { it.backdropTag != null }
                    Featured(state, pool)
                }
                if (state.settings.phoneUpNextMerged) {
                    if (upNext.isNotEmpty()) item(key = "upnext") {
                        PhoneRow("Up Next") { items(upNext, key = { it.id }) { UpNextCard(it, state, listed) { open(it) } } }
                    }
                } else {
                    if (resume.isNotEmpty()) item(key = "resume") {
                        PhoneRow("Continue Watching") { items(resume, key = { it.id }) { UpNextCard(it, state, listed) { open(it) } } }
                    }
                    if (listed.isNotEmpty()) item(key = "listed") {
                        PhoneRow("Up Next") { items(listed, key = { it.id }) { UpNextCard(it, state, listed) { open(it) } } }
                    }
                    if (nextUp.isNotEmpty()) item(key = "nextup") {
                        PhoneRow("Next Up") { items(nextUp, key = { it.id }) { UpNextCard(it, state, listed) { open(it) } } }
                    }
                }
                item(key = "libraries") { PhoneLibraries(state.visibleViews(current.views), extras, state) }
                current.latest.filter { !state.hides(it.first.id) }.forEach { (view, all) ->
                    val items = all.filter { it.id !in state.settings.notInterested && it.seriesId !in state.settings.notInterested }
                    if (items.isNotEmpty()) item(key = "latest-${view.id}") {
                        PhoneRow("New in ${view.name}", onMore = { state.push(Screen.Library(view)) }) {
                            items(items, key = { it.id }) { ItemCard(it, server, CardShape.Poster) { open(it) } }
                        }
                    }
                }
                phoneTopTens(state, extras, open)
                phoneGenres(state, extras)
                val watched = keep(current.watched)
                if (watched.isNotEmpty()) item(key = "watched") {
                    PhoneRow("Watched Lately") { items(watched, key = { it.id }) { ItemCard(it, server, CardShape.Wide) { open(it) } } }
                }
            }
        }
        IosTopBar(shown, "Home", trailing = {
            val circle = Color.Black.copy(alpha = 0.35f * (1f - shown))
            if (app.lumiere.android.Flavor.isRemote && (app.lumiere.android.remote.RemoteClient.lastTv(context) != null ||
                    app.lumiere.android.remote.RemoteClient.found.isNotEmpty()))
                IosCircle(Icons.Default.SettingsRemote, "Remote for the TV", { state.push(Screen.Remote) }, size = 34,
                    modifier = Modifier.background(circle, androidx.compose.foundation.shape.CircleShape))
            if (state.privateLibraries.isNotEmpty()) {
                val activity = context as? android.app.Activity
                IosCircle(if (state.roomOpen) Icons.Default.LockOpen else Icons.Default.Lock,
                    if (state.roomOpen) "Leave the private room" else "Private room",
                    { activity?.let { toggleRoom(state, it) } }, size = 34,
                    tint = if (state.roomOpen) Palette.accent else Color.White,
                    modifier = Modifier.background(circle, androidx.compose.foundation.shape.CircleShape))
            }
            IosAvatar(state.session?.userName ?: "") { state.guarded { state.push(Screen.Settings) } }
        })
        // The room says where you are, since it changes what is shown.
        if (state.roomOpen) Text("Private Room", style = IosType.caption, color = Palette.accent,
            modifier = Modifier.align(Alignment.TopStart).statusBarsPadding().padding(start = 18.dp, top = 18.dp))
    }
}

/** A row with Apple's header, the chevron when it opens somewhere fuller. */
@Composable
internal fun PhoneRow(title: String, subtitle: String? = null, onMore: (() -> Unit)? = null,
                      content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    Column(Modifier.padding(top = 18.dp)) {
        IosSectionHeader(title, subtitle = subtitle, onMore = onMore)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

/**
 * Apple's Up Next card: the still with a slim progress bar, then in small
 * capitals what it is to you — RESUME · 23 MIN LEFT, NEXT EPISODE, UP NEXT —
 * the show, and the episode.
 */
@Composable
internal fun UpNextCard(item: Item, state: AppState, listed: List<Item>, onClick: () -> Unit) {
    val server = state.server ?: return
    val spoiler = state.settings.hidesSpoilers && item.isEpisode && !item.played && item.positionTicks == 0L
    Column(Modifier.width(272.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).pressScale().clip(RoundedCornerShape(10.dp))
            .combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = { PhoneMenu.item = item }, onClick = onClick)
            .background(Palette.surface)) {
            AsyncImage(imageFor(item, server, CardShape.Wide, 640), item.name, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize().then(if (spoiler) Modifier.spoilerBlur() else Modifier))
            item.progress?.let { p ->
                Box(Modifier.align(Alignment.BottomStart).padding(10.dp).fillMaxWidth(0.42f).height(4.dp)
                    .clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.35f))) {
                    Box(Modifier.fillMaxWidth(p).height(4.dp).clip(RoundedCornerShape(50)).background(Color.White))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        IosCaption(caption(item, listed))
        Text(if (item.isEpisode) item.seriesName ?: item.name else item.name, style = IosType.headline,
            color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (item.isEpisode) Text(listOfNotNull(episodeShort(item), item.name).joinToString(" · "),
            style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun caption(item: Item, listed: List<Item>): String = when {
    item.positionTicks > 0 -> {
        val left = ((item.runtimeTicks ?: 0) - item.positionTicks) / TICKS_PER_SECOND / 60
        if (left > 0) "Resume · ${minutes(left)} left" else "Resume"
    }
    listed.any { it.id == item.id } -> "Up Next"
    item.isEpisode -> if ((item.indexNumber ?: 0) == 1) "Start Watching" else "Next Episode"
    else -> "Start Watching"
}

/** "S2, E3", as Apple writes an episode. */
internal fun episodeShort(item: Item): String? = listOfNotNull(item.parentIndexNumber?.let { "S$it" }, item.indexNumber?.let { "E$it" })
    .joinToString(", ").ifEmpty { null }

/** "1 hr 5 min", "23 min": Apple's way with a length. */
internal fun minutes(total: Long): String = if (total >= 60) "${total / 60} hr ${total % 60} min".removeSuffix(" 0 min") else "$total min"

/** An unwatched episode's picture, out of focus, with Settings' Hide Spoilers on; veiled where blur is not drawn. */
internal fun Modifier.spoilerBlur(): Modifier =
    if (android.os.Build.VERSION.SDK_INT >= 31) this.blur(24.dp)
    else this.drawWithContent { drawContent(); drawRect(Color.Black.copy(alpha = 0.85f)) }

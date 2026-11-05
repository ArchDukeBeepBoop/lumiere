package app.lumiere.android.player

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.Trickplay
import app.lumiere.android.music.clock
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.holdsRemote
import app.lumiere.android.ui.ignoreHeldOk
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage

/** How tall the tabs are; the transport rises by this much while they show. */
internal val TabsHeight = 196.dp

/**
 * Apple's content tabs under the transport (TV_PLAYER_PLAN §4.4): Info, Chapters
 * when the file has them, Episodes for an episode. Text tabs along the top, the
 * chosen one's cards below; Up from the tabs, or Back, returns to the bar.
 */
@Composable
internal fun TvTabs(item: Item, server: Server, userId: String, player: ExoPlayer, clock: Clock, trickplay: Trickplay?,
                    onEpisode: (Item) -> Unit, onClose: () -> Unit) {
    val tabs = listOfNotNull("Info", "Chapters".takeIf { item.chapters.isNotEmpty() }, "Episodes".takeIf { item.isEpisode })
    var tab by remember { mutableStateOf(tabs.first()) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(40); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomStart) {
        Column(Modifier.holdsRemote().ignoreHeldOk().fillMaxWidth().height(TabsHeight)
            .background(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.55f), 1f to Color.Black.copy(alpha = 0.92f)))
            .padding(start = 52.dp, end = 52.dp, top = 8.dp)) {
            // Up from the tabs goes back to the bar, as Apple's do.
            Row(Modifier.onPreviewKeyEvent { e ->
                val k = e.nativeKeyEvent
                if (k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_UP && k.action == android.view.KeyEvent.ACTION_DOWN) { onClose(); true } else false
            }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                tabs.forEachIndexed { i, t ->
                    // A tab is chosen by moving onto it, as tvOS's are; what it holds shows at once.
                    TvPill({ tab = t }, (if (i == 0) Modifier.focusRequester(first) else Modifier).onFocusChanged { if (it.isFocused) tab = t },
                        selected = t == tab) { Text(t, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold)) }
                }
            }
            Spacer(Modifier.height(10.dp))
            when (tab) {
                "Info" -> InfoTab(item, server, player)
                "Chapters" -> ChaptersTab(item, server, clock, trickplay, onClose)
                "Episodes" -> EpisodesTab(item, server, userId, onEpisode)
            }
        }
    }
}

@Composable
private fun InfoTab(item: Item, server: Server, player: ExoPlayer) {
    Row(Modifier.padding(start = 4.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        AsyncImage(imageFor(item, server, CardShape.Poster, 220), null, contentScale = ContentScale.Crop,
            modifier = Modifier.width(88.dp).aspectRatio(2f / 3f).clip(RoundedCornerShape(8.dp)).background(Palette.surface))
        Column(Modifier.widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(if (item.isEpisode) listOfNotNull(item.episodeLabel, item.name).joinToString(" · ") else item.name,
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                val meta = listOfNotNull(item.year?.toString(), item.runtimeTicks?.let { val m = it / 600_000_000L; if (m >= 60) "${m / 60} hr ${m % 60} min" else "$m min" })
                Text(meta.joinToString(" · "), style = TextStyle(fontSize = 13.sp, color = Color.White.copy(alpha = 0.75f)))
                badges(item, player).forEach { Badge(it) }
            }
            item.overview?.let { Text(it, style = TextStyle(fontSize = 13.5.sp, lineHeight = 19.sp, color = Color.White.copy(alpha = 0.85f)), maxLines = 3, overflow = TextOverflow.Ellipsis) }
            if (item.people.isNotEmpty()) Text("With " + item.people.take(5).joinToString(", ") { it.name },
                style = TextStyle(fontSize = 12.5.sp, color = Color.White.copy(alpha = 0.6f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** What the picture and sound actually are, as the outlined badges on Apple's info card. */
private fun badges(item: Item, player: ExoPlayer): List<String> = buildList {
    item.officialRating?.let { add(it) }
    val v = player.videoFormat
    when { (v?.height ?: 0) >= 1600 -> add("4K"); (v?.height ?: 0) >= 700 -> add("HD") }
    when (v?.colorInfo?.colorTransfer) {
        androidx.media3.common.C.COLOR_TRANSFER_ST2084 -> add("HDR10"); androidx.media3.common.C.COLOR_TRANSFER_HLG -> add("HLG")
    }
    when (player.audioFormat?.channelCount) { 6 -> add("5.1"); 8 -> add("7.1") }
    if (item.streams.any { it.type == "Subtitle" }) add("CC")
}

@Composable
private fun Badge(text: String) {
    Text(text, style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.8f)),
        modifier = Modifier.border(BorderStroke(1.dp, Color.White.copy(alpha = 0.5f)), RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 1.dp))
}

@Composable
private fun ChaptersTab(item: Item, server: Server, clock: Clock, trickplay: Trickplay?, onClose: () -> Unit) {
    val now = clock.now()
    val chapters = item.chapters
    val here = chapters.indexOfLast { it.startSeconds <= now }.coerceAtLeast(0)
    val list = rememberLazyListState()
    LaunchedEffect(Unit) { list.scrollToItem((here - 1).coerceAtLeast(0)) }
    LazyRow(state = list, horizontalArrangement = Arrangement.spacedBy(20.dp), contentPadding = PaddingValues(horizontal = 4.dp, vertical = 6.dp)) {
        itemsIndexed(chapters) { i, c ->
            Column(Modifier.width(176.dp)) {
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard { clock.seek(c.startSeconds); onClose() }
                    .clip(RoundedCornerShape(8.dp)).background(Palette.surface)) {
                    val t = trickplay
                    if (t != null) TrickFrameAt(server, item.id, t, c.startSeconds.toFloat(), Modifier.fillMaxSize())
                    if (i == here) Text("Now", style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black),
                        modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Color.White, RoundedCornerShape(3.dp)).padding(horizontal = 4.dp))
                }
                Spacer(Modifier.height(5.dp))
                Text(c.name?.takeIf { it.isNotBlank() } ?: "Chapter ${i + 1}", style = TextStyle(fontSize = 13.sp, color = Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(clock(c.startSeconds), style = TextStyle(fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f), fontFeatureSettings = "tnum"))
            }
        }
    }
}

@Composable
private fun EpisodesTab(item: Item, server: Server, userId: String, onEpisode: (Item) -> Unit) {
    var episodes by remember { mutableStateOf<List<Item>>(emptyList()) }
    val list = rememberLazyListState()
    LaunchedEffect(item.id) {
        val series = item.seriesId ?: return@LaunchedEffect
        episodes = runCatching { server.episodes(userId, series, item.seasonId) }.getOrDefault(emptyList())
        list.scrollToItem((episodes.indexOfFirst { it.id == item.id } - 1).coerceAtLeast(0))
    }
    LazyRow(state = list, horizontalArrangement = Arrangement.spacedBy(20.dp), contentPadding = PaddingValues(horizontal = 4.dp, vertical = 6.dp)) {
        itemsIndexed(episodes, key = { _, e -> e.id }) { _, e ->
            val playing = e.id == item.id
            Column(Modifier.width(176.dp)) {
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard { if (!playing) onEpisode(e) }
                    .clip(RoundedCornerShape(8.dp)).background(Palette.surface)) {
                    AsyncImage(imageFor(e, server, CardShape.Wide, 400), e.name, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                    if (playing) Text("Now Playing", style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black),
                        modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Color.White, RoundedCornerShape(3.dp)).padding(horizontal = 4.dp))
                }
                Spacer(Modifier.height(5.dp))
                Text(listOfNotNull(e.indexNumber?.let { "$it." }, e.name).joinToString(" "), style = TextStyle(fontSize = 13.sp, color = Color.White),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** A trickplay frame at a time, for a chapter's card. */
@Composable
internal fun TrickFrameAt(server: Server, id: String, t: Trickplay, seconds: Float, modifier: Modifier) {
    val index = ((seconds * 1000) / t.intervalMs.coerceAtLeast(1)).toInt().coerceIn(0, (t.count - 1).coerceAtLeast(0))
    TrickFrame(server, id, t, index, modifier)
}

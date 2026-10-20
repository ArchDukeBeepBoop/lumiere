package app.lumiere.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.SettingsRemote
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.hideFromContinueWatching
import app.lumiere.android.api.itemJson
import app.lumiere.android.api.setFavorite
import app.lumiere.android.remote.RemoteClient
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The card a long press opened on the phone; see [PhoneActions]. */
object PhoneMenu {
    var item by mutableStateOf<Item?>(null)
}

/** iOS's brief notice at the top — "Added to Up Next" — with Undo when it can be taken back. */
object PhoneNotice {
    var text by mutableStateOf<String?>(null)
        private set
    var undo by mutableStateOf<(() -> Unit)?>(null)
        private set
    private var shown = 0

    fun show(message: String, takeBack: (() -> Unit)? = null) { text = message; undo = takeBack; shown++ }
    fun clear() { text = null; undo = null }
    internal val generation get() = shown
}

private data class MenuEntry(val label: String, val icon: ImageVector, val red: Boolean = false, val run: () -> Unit)

/**
 * A card's actions on a long press, as iOS's context menu: the title lifted
 * out above the page, the actions in a frosted list under it. Also the
 * brief notice after an action, at the top.
 */
@Composable
fun PhoneActions(state: AppState) {
    val item = PhoneMenu.item
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(item?.id) { if (item != null) haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
    if (item != null) BackHandler { PhoneMenu.item = null }

    AnimatedVisibility(item != null, enter = fadeIn(), exit = fadeOut()) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.62f))
            .clickable(remember { MutableInteractionSource() }, null) { PhoneMenu.item = null })
    }
    AnimatedVisibility(item != null, enter = scaleIn(initialScale = 0.88f) + fadeIn(),
        exit = scaleOut(targetScale = 0.92f) + fadeOut(), modifier = Modifier.fillMaxSize()) {
        val shown = remember { mutableStateOf(item) }
        if (item != null) shown.value = item
        shown.value?.let { Menu(state, it) }
    }
    Notice()
}

@Composable
private fun Menu(state: AppState, item: Item) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val tv = remember { if (app.lumiere.android.Flavor.isRemote) RemoteClient.lastTv(context)?.removePrefix("Lumiere on ") else null }
    fun close() { PhoneMenu.item = null }
    fun refresh() { state.homeRefresh++ }

    val groups = buildList {
        add(buildList {
            if (item.isPlayable) add(MenuEntry(if (item.positionTicks > 0) "Resume" else "Play", Icons.Default.PlayArrow) {
                close(); state.push(Screen.Player(item.id, null)) })
            if (item.isSeries) add(MenuEntry("Play", Icons.Default.PlayArrow) { close(); scope.launch { playSeries(state, item) } })
            if (item.isPlayable && item.positionTicks > 0) add(MenuEntry("Play from Beginning", Icons.Default.Replay) {
                close(); state.push(Screen.Player(item.id, 0.0)) })
            if (tv != null && (item.isPlayable || item.isSeries)) add(MenuEntry("Play on $tv", Icons.Default.SettingsRemote) {
                close(); RemoteClient.playOnTv(item.id, null); state.push(Screen.Remote) })
            if (item.isEpisode && item.seriesId != null) add(MenuEntry("Go to ${item.seriesName ?: "Show"}", Icons.Default.Tv) {
                close(); state.push(Screen.Detail(item.seriesId)) })
            if (state.top != Screen.Detail(item.id)) add(MenuEntry("Details", Icons.Default.Info) { close(); state.push(Screen.Detail(item.id)) })
        })
        add(buildList {
            if (item.isPlayable || item.isSeries) add(MenuEntry(if (item.played) "Mark as Unwatched" else "Mark as Watched",
                if (item.played) Icons.Outlined.RemoveCircleOutline else Icons.Default.CheckCircle) {
                close()
                val to = !item.played
                scope.launch {
                    runCatching { server.setPlayed(item.id, to) }.onSuccess {
                        state.justWatched = if (to) state.justWatched + item.id else state.justWatched - item.id
                        refresh()
                        PhoneNotice.show(if (to) "Marked as Watched" else "Marked as Unwatched") {
                            scope.launch { runCatching { server.setPlayed(item.id, !to) }; state.justWatched = state.justWatched - item.id; refresh() }
                        }
                    }.onFailure { PhoneNotice.show("Couldn't reach the Mac") }
                }
            })
            if (!state.roomOpen && (item.isPlayable || item.isSeries) && item.positionTicks == 0L) {
                val inList = item.id in state.settings.watchlist
                add(MenuEntry(if (inList) "Remove from Up Next" else "Add to Up Next", Icons.AutoMirrored.Filled.PlaylistAdd) {
                    close()
                    val before = state.settings.watchlist
                    state.settings.watchlist = if (inList) before - item.id else listOf(item.id) + before
                    refresh()
                    PhoneNotice.show(if (inList) "Removed from Up Next" else "Added to Up Next") { state.settings.watchlist = before; refresh() }
                })
            }
            add(MenuEntry(if (item.favorite) "Remove from Favourites" else "Add to Favourites",
                if (item.favorite) Icons.Default.StarBorder else Icons.Default.Star) {
                close()
                scope.launch {
                    runCatching { server.setFavorite(item.id, !item.favorite) }
                        .onSuccess { refresh(); PhoneNotice.show(if (item.favorite) "Removed from Favourites" else "Added to Favourites") }
                        .onFailure { PhoneNotice.show("Couldn't reach the Mac") }
                }
            })
            if (item.isPlayable && state.downloads.find(item.id) == null) add(MenuEntry("Download", Icons.Default.Download) {
                close()
                scope.launch {
                    runCatching { server.itemJson(userId, item.id) }.onSuccess {
                        if (state.downloads.start(server, userId, it, state.settings.downloadsWifiOnly)) PhoneNotice.show("Downloading")
                    }.onFailure { PhoneNotice.show("Couldn't reach the Mac") }
                }
            })
        })
        add(buildList {
            if (item.positionTicks > 0) add(MenuEntry("Hide from Up Next", Icons.Default.VisibilityOff) {
                close()
                scope.launch { runCatching { server.hideFromContinueWatching(item.id) }.onSuccess { refresh(); PhoneNotice.show("Hidden from Up Next") } }
            })
            add(MenuEntry("Edit Details", Icons.Default.Edit) { close(); state.push(Screen.Edit(item.id)) })
            add(MenuEntry("Not Interested", Icons.Outlined.Block, red = true) {
                close()
                val before = state.settings.notInterested
                state.settings.notInterested = before + item.id
                refresh()
                PhoneNotice.show("You won't see it on Home") { state.settings.notInterested = before; refresh() }
            })
        })
    }.filter { it.isNotEmpty() }

    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Preview(state, item)
        Spacer(Modifier.height(14.dp))
        Column(Modifier.width(270.dp).clip(RoundedCornerShape(14.dp)).background(Color(0xFF252527).copy(alpha = 0.97f))) {
            groups.forEachIndexed { g, entries ->
                if (g > 0) Box(Modifier.fillMaxWidth().height(7.dp).background(Color.Black.copy(alpha = 0.35f)))
                entries.forEachIndexed { i, e ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(0.5.dp).background(Color.White.copy(alpha = 0.12f)))
                    Row(Modifier.fillMaxWidth().clickable(onClick = e.run).padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        val colour = if (e.red) Color(0xFFFF453A) else Color.White
                        Text(e.label, style = IosType.body, color = colour, modifier = Modifier.weight(1f), maxLines = 1,
                            overflow = TextOverflow.Ellipsis)
                        Icon(e.icon, null, tint = colour, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
}

/** The title held up above its menu: its still or poster, its name. */
@Composable
private fun Preview(state: AppState, item: Item) {
    val server = state.server ?: return
    val wide = item.isEpisode || item.positionTicks > 0 || item.backdropTag != null
    Column(Modifier.width(if (wide) 300.dp else 180.dp).clip(RoundedCornerShape(14.dp)).background(Palette.surface)) {
        AsyncImage(imageFor(item, server, if (wide) CardShape.Wide else CardShape.Poster, 600), item.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().aspectRatio(if (wide) 16f / 9f else 2f / 3f).background(Palette.surfaceRaised))
        Column(Modifier.padding(12.dp)) {
            if (item.isEpisode) IosCaption(listOfNotNull(item.seriesName, item.episodeLabel).joinToString(" · "))
            Text(item.name, style = IosType.headline, color = Palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            item.overview?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun Notice() {
    val text = PhoneNotice.text
    LaunchedEffect(PhoneNotice.generation) { if (text != null) { delay(3_500); PhoneNotice.clear() } }
    val last = remember { mutableStateOf("") }
    if (text != null) last.value = text
    Box(Modifier.fillMaxSize().statusBarsPadding(), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(text != null, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
            Row(Modifier.padding(top = 8.dp).clip(RoundedCornerShape(50)).background(Color(0xFF2C2C2E).copy(alpha = 0.97f))
                .padding(start = 16.dp, end = if (PhoneNotice.undo != null) 6.dp else 18.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Default.CheckCircle, null, tint = Palette.accent, modifier = Modifier.size(18.dp))
                Text(last.value, style = IosType.headline, color = Color.White)
                PhoneNotice.undo?.let { undo ->
                    Text("Undo", style = IosType.headline, color = Palette.accent, modifier = Modifier.clip(RoundedCornerShape(50))
                        .clickable { undo(); PhoneNotice.clear() }.padding(horizontal = 10.dp, vertical = 4.dp))
                }
            }
        }
    }
}

/** Play on a show: its next episode, or the first not yet watched. */
suspend fun playSeries(state: AppState, series: Item) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val next = runCatching { server.nextUp(userId).firstOrNull { it.seriesId == series.id } }.getOrNull()
        ?: runCatching { server.episodes(userId, series.id, null).let { eps -> eps.firstOrNull { !it.played } ?: eps.firstOrNull() } }.getOrNull()
    if (next != null) state.push(Screen.Player(next.id, null)) else PhoneNotice.show("Nothing to play yet")
}

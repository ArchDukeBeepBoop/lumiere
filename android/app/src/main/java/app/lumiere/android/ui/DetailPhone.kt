@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.itemJson
import app.lumiere.android.api.personImage
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/**
 * A show's episodes as Apple lays them out on an iPhone: "Season 2 ⌄" opening
 * a menu of seasons (and Download Season, Mark Season as Watched), then the
 * season's episodes as a row of stills that opens on the next one to watch.
 * A tap plays; a long press opens the episode's menu.
 */
@Composable
internal fun Episodes(state: AppState, series: Item, seasons: List<Item>, season: Item?, episodes: List<Item>, next: Item?,
                      onSeason: (Item) -> Unit, onPlayed: (Item, Boolean) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.padding(top = 22.dp)) {
        Box(Modifier.padding(horizontal = 16.dp)) {
            Row(Modifier.clip(RoundedCornerShape(8.dp)).combinedClickable(onClick = { menu = true }).padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(season?.name ?: "Episodes", style = IosType.title, color = Palette.textPrimary)
                Icon(Icons.Default.KeyboardArrowDown, "Choose a season", tint = Palette.textSecondary, modifier = Modifier.size(26.dp))
            }
            DropdownMenu(menu, { menu = false }, containerColor = Palette.surfaceRaised) {
                seasons.forEach { s ->
                    DropdownMenuItem(text = {
                        Text(s.name + ((s.unplayedCount ?: 0).takeIf { it > 0 }?.let { "  ·  $it new" } ?: ""),
                            color = if (s.id == season?.id) Palette.accent else Palette.textPrimary)
                    }, onClick = { menu = false; onSeason(s) })
                }
                HorizontalDivider(color = Palette.border)
                val missing = episodes.filter { state.downloads.find(it.id) == null }
                if (missing.isNotEmpty()) DropdownMenuItem(text = { Text("Download ${season?.name ?: "Season"} (${missing.size})") }, onClick = {
                    menu = false
                    scope.launch {
                        var started = 0
                        for (e in missing) {
                            val json = runCatching { server.itemJson(userId, e.id) }.getOrNull() ?: continue
                            if (!state.downloads.start(server, userId, json, state.settings.downloadsWifiOnly)) break
                            started++
                        }
                        if (started > 0) PhoneNotice.show("Downloading $started episodes")
                    }
                })
                if (episodes.any { !it.played }) DropdownMenuItem(text = { Text("Mark ${season?.name ?: "Season"} as Watched") }, onClick = {
                    menu = false
                    episodes.filter { !it.played }.forEach { onPlayed(it, true) }
                    PhoneNotice.show("${season?.name ?: "Season"} marked as watched")
                })
            }
        }
        val row = rememberLazyListState()
        // Opens on the next episode to watch, not always the first.
        LaunchedEffect(episodes.map { it.id }) {
            val at = episodes.indexOfFirst { it.id == next?.id }.takeIf { it >= 0 }
                ?: episodes.indexOfFirst { !it.played }.takeIf { it >= 0 } ?: 0
            if (at > 0) row.scrollToItem(at)
        }
        LazyRow(state = row, contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(episodes, key = { it.id }) { e -> EpisodeCard(e, state) }
        }
    }
}

/** One episode: its still with progress or a tick, EPISODE 3, the name, the story, the length. */
@Composable
private fun EpisodeCard(e: Item, state: AppState) {
    val server = state.server ?: return
    val spoiler = state.settings.hidesSpoilers && !e.played && e.positionTicks == 0L
    Column(Modifier.width(270.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).pressScale().clip(RoundedCornerShape(10.dp))
            .combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = { PhoneMenu.item = e }) {
                state.push(Screen.Player(e.id, null))
            }.background(Palette.surface)) {
            AsyncImage(imageFor(e, server, CardShape.Wide, 600), e.name, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize().then(if (spoiler) Modifier.spoilerBlur() else Modifier))
            e.progress?.let { p ->
                Box(Modifier.align(Alignment.BottomStart).padding(10.dp).fillMaxWidth(0.42f).height(4.dp)
                    .clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.35f))) {
                    Box(Modifier.fillMaxWidth(p).height(4.dp).clip(RoundedCornerShape(50)).background(Color.White))
                }
            }
            WatchedMark(e, Modifier.align(Alignment.TopEnd))
            if (state.downloads.find(e.id) != null) Text("↓", style = IosType.caption, color = Color.White,
                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)
                    .padding(horizontal = 7.dp, vertical = 2.dp))
        }
        Spacer(Modifier.height(8.dp))
        IosCaption(e.indexNumber?.let { "Episode $it" } ?: "Special")
        Text(e.name, style = IosType.headline, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(if (spoiler) "Hidden until you watch it" else e.overview ?: "", style = IosType.footnote, color = Palette.textSecondary,
            maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.height(52.dp))
        e.runtimeTicks?.let { Text(minutes(it / TICKS_PER_SECOND / 60), style = IosType.footnote, color = Palette.textMuted) }
    }
}

/** The cast as Apple's circles, name and part beneath; a tap lists everything they are in. */
@Composable
internal fun Cast(item: Item, state: AppState) {
    val server = state.server ?: return
    Column(Modifier.padding(top = 22.dp)) {
        IosSectionHeader("Cast & Crew")
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(item.people.take(30), key = { it.id + (it.role ?: "") + (it.type ?: "") }) { p ->
                Column(Modifier.width(88.dp).iosClick { state.push(Screen.Person(p.id, p.name)) },
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(84.dp).clip(CircleShape).background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
                        Text(p.name.split(' ').mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString(""),
                            style = IosType.title, color = Palette.textSecondary)
                        if (p.imageTag != null) AsyncImage(server.personImage(p.id, p.imageTag), p.name,
                            contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(p.name, style = IosType.footnote, color = Palette.textPrimary, maxLines = 2,
                        textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
                    (p.role?.takeIf { it.isNotBlank() } ?: p.type)?.let {
                        Text(it, style = IosType.footnote, color = Palette.textSecondary, maxLines = 1,
                            textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/**
 * Apple's foot of the page: Information (released, length, rated, genres,
 * studio) and Languages (original audio, audio, subtitles), in two columns.
 * A show takes its languages from its first episode.
 */
@Composable
internal fun Information(item: Item, sample: Item?) {
    val streams = item.streams.ifEmpty { sample?.streams.orEmpty() }
    fun languages(type: String) = streams.filter { it.type == type }.mapNotNull { s -> s.language?.let(::languageName) ?: s.title }
        .distinct().joinToString(", ").ifEmpty { null }
    val info = listOfNotNull(
        item.year?.let { "Released" to "$it" },
        item.runtimeTicks?.takeIf { it >= TICKS_PER_SECOND * 60 }?.let { "Run Time" to minutes(it / TICKS_PER_SECOND / 60) },
        item.officialRating?.let { "Rated" to it },
        item.genres.takeIf { it.isNotEmpty() }?.let { "Genre" to it.joinToString(", ") },
        item.studios.takeIf { it.isNotEmpty() }?.let { (if (item.isSeries) "Network" else "Studio") to it.take(3).joinToString(", ") },
        item.communityRating?.let { "Rating" to "★ %.1f".format(it) },
    )
    val langs = listOfNotNull(
        streams.firstOrNull { it.type == "Audio" && it.isDefault }?.language?.let { "Original Audio" to languageName(it) },
        languages("Audio")?.let { "Audio" to it },
        languages("Subtitle")?.let { "Subtitles" to it },
    )
    if (info.isEmpty() && langs.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        HorizontalDivider(color = Palette.border, thickness = 0.5.dp)
        if (info.isNotEmpty()) Facts("Information", info)
        if (langs.isNotEmpty()) Facts("Languages", langs)
    }
}

@Composable
private fun Facts(title: String, facts: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = IosType.title, color = Palette.textPrimary)
        facts.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                pair.forEach { (label, value) ->
                    Column(Modifier.weight(1f)) {
                        Text(label, style = IosType.headline.copy(fontSize = 14.sp), color = Palette.textPrimary)
                        Text(value, style = IosType.footnote, color = Palette.textSecondary)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** "eng" → "English", in the phone's own language. */
internal fun languageName(code: String): String =
    runCatching { java.util.Locale.forLanguageTag(code).getDisplayLanguage().takeIf { it.isNotBlank() && it != code } }.getOrNull()
        ?: runCatching { java.util.Locale(code).displayLanguage.takeIf { it.isNotBlank() } }.getOrNull() ?: code

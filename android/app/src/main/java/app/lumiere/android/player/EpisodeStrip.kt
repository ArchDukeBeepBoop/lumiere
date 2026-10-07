package app.lumiere.android.player

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage

/**
 * The season's episodes along the bottom of the picture, the one playing
 * selected — down from the play button on a TV. OK jumps; Back closes.
 */
@Composable
fun EpisodeStrip(server: Server, userId: String, current: Item, onPick: (Item) -> Unit, onClose: () -> Unit) {
    var episodes by remember { mutableStateOf<List<Item>>(emptyList()) }
    val list = rememberLazyListState()
    val focus = remember { FocusRequester() }
    androidx.activity.compose.BackHandler(onBack = onClose)
    LaunchedEffect(current.id) {
        val series = current.seriesId ?: return@LaunchedEffect
        episodes = runCatching { server.episodes(userId, series, current.seasonId) }.getOrDefault(emptyList())
        val here = episodes.indexOfFirst { it.id == current.id }.coerceAtLeast(0)
        list.scrollToItem((here - 1).coerceAtLeast(0))
        runCatching { focus.requestFocus() }
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.4f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.9f))),
        contentAlignment = Alignment.BottomStart) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Text(current.seasonName ?: "Episodes", style = MaterialTheme.typography.titleLarge, color = Color.White,
                modifier = Modifier.padding(start = 48.dp))
            LazyRow(state = list, contentPadding = PaddingValues(horizontal = 48.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                itemsIndexed(episodes, key = { _, e -> e.id }) { _, e ->
                    val playing = e.id == current.id
                    Column(Modifier.width(240.dp)) {
                        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)
                            .then(if (playing) Modifier.focusRequester(focus) else Modifier)
                            .focusCard { if (playing) onClose() else onPick(e) }.background(Palette.surface)) {
                            AsyncImage(imageFor(e, server, CardShape.Wide, 480), e.name, contentScale = ContentScale.Crop,
                                modifier = Modifier.matchParentSize())
                            if (playing) Text("Now playing", color = Palette.onAccent, style = MaterialTheme.typography.labelMedium,
                                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Palette.accent).padding(horizontal = 6.dp))
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(listOfNotNull(e.indexNumber?.let { "$it." }, e.name).joinToString(" "), color = Color.White,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

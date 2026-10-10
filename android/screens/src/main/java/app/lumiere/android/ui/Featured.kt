package app.lumiere.android.ui

import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * The banner across the top of Home: something new, full width, with Play
 * and More Info — the Mac's spotlight. Swipe through it, or it moves on by
 * itself every ten seconds; the dots say where you are. The private-room
 * lock sits over its corner.
 */
@Composable
fun Featured(state: AppState, pool: List<Item>) {
    val server = state.server ?: return
    if (pool.isEmpty()) { Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.TopEnd) { RoomButton(state) }; return }
    val form = LocalFormFactor.current
    val picks = remember(pool) { pool.shuffled().take(6) }
    val pager = rememberPagerState { picks.size }
    val dragging by pager.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(picks, dragging, app.lumiere.android.Motion.reduced) {
        while (!dragging && !app.lumiere.android.Motion.reduced && picks.size > 1) { delay(10_000); pager.animateScrollToPage((pager.currentPage + 1) % picks.size) }
    }
    Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f)) {
        HorizontalPager(pager, Modifier.matchParentSize(), key = { picks[it].id }) { page ->
            val item = picks[page]
            Box(Modifier.fillMaxSize()) {
                AsyncImage(server.imageUrl(item.id, "Backdrop", item.backdropTag, 1600), null,
                    contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                Box(Modifier.matchParentSize().background(
                    Brush.verticalGradient(0.35f to Color.Transparent, 1f to Palette.canvas)))
                Box(Modifier.matchParentSize().background(
                    Brush.horizontalGradient(0f to Palette.canvas.copy(alpha = 0.7f), 0.6f to Color.Transparent)))
                Column(Modifier.align(Alignment.BottomStart).padding(start = form.gutter.dp, end = form.gutter.dp, bottom = 30.dp)
                    .widthIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (item.logoTag != null) {
                        AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 600), item.name,
                            contentScale = ContentScale.Fit, alignment = Alignment.BottomStart,
                            modifier = Modifier.height(70.dp).fillMaxWidth())
                    } else {
                        Text(item.name, style = MaterialTheme.typography.headlineLarge, maxLines = 2,
                            overflow = TextOverflow.Ellipsis)
                    }
                    Text(listOfNotNull(item.year?.toString(), item.officialRating,
                        item.genres.take(2).joinToString(", ").ifEmpty { null }).joinToString("  ·  "),
                        style = MaterialTheme.typography.labelMedium)
                    item.overview?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (item.isPlayable) LButton(onClick = { state.push(Screen.Player(item.id, null)) }) { Text("Play") }
                        LButton(primary = false, onClick = { state.push(Screen.Detail(item.id)) }) { Text("More Info") }
                    }
                }
            }
        }
        if (picks.size > 1) Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp)) {
            repeat(picks.size) { i ->
                val on = i == pager.currentPage
                Box(Modifier.padding(horizontal = 3.dp).size(if (on) 7.dp else 5.dp).clip(CircleShape)
                    .background(if (on) Palette.textPrimary else Palette.textPrimary.copy(alpha = 0.35f)))
            }
        }
        // Only the room says where you are, since it changes what is shown.
        if (state.privateLibraries.isNotEmpty()) Row(Modifier.align(Alignment.TopEnd).padding(6.dp).clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.35f)), verticalAlignment = Alignment.CenterVertically) {
            if (state.roomOpen) Text("Private room", style = MaterialTheme.typography.labelLarge, color = Palette.accent,
                modifier = Modifier.padding(start = 14.dp))
            RoomButton(state)
        }
    }
}

package app.lumiere.android.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The top of Home on a phone, as the Apple TV app's: new titles full-bleed
 * under the status bar, the picture drifting slowly, the title's logo and
 * kind centred over a fall into black, a white Play between "+" for Up Next
 * and ⓘ for details, and the page dots. Swipe through it, or it turns by
 * itself every eight seconds; a tap on the picture opens the title.
 */
@Composable
fun Featured(state: AppState, pool: List<Item>) {
    val server = state.server ?: return
    if (pool.isEmpty()) { Box(Modifier.fillMaxWidth().height(120.dp)); return }
    val picks = remember(pool) {
        pool.filter { !it.isEpisode && it.id !in state.settings.notInterested }.ifEmpty { pool }
            .shuffled().sortedByDescending { it.logoTag != null }.take(6).shuffled()
    }
    val pager = rememberPagerState { picks.size }
    val dragging by pager.interactionSource.collectIsDraggedAsState()
    val still = app.lumiere.android.Motion.reduced
    LaunchedEffect(picks, dragging, still) {
        while (!dragging && !still && picks.size > 1) { delay(8_000); pager.animateScrollToPage((pager.currentPage + 1) % picks.size) }
    }
    // The slow drift Apple's banner has.
    val drift = rememberInfiniteTransition(label = "drift")
    val zoom by drift.animateFloat(1f, if (still) 1f else 1.07f,
        infiniteRepeatable(tween(16_000, easing = LinearEasing), RepeatMode.Reverse), label = "zoom")
    val scope = rememberCoroutineScope()

    Box(Modifier.fillMaxWidth().height(heroHeight(0.84f))) {
        HorizontalPager(pager, Modifier.matchParentSize(), key = { picks[it].id }) { page ->
            val item = picks[page]
            // Clipped, so the drift never spills past the banner's edge or onto the next page.
            Box(Modifier.fillMaxSize().clipToBounds().clickable(remember { MutableInteractionSource() }, null) { state.push(Screen.Detail(item.id)) }) {
                AsyncImage(server.imageUrl(item.id, "Backdrop", item.backdropTag, 1600), null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize().graphicsLayer { scaleX = zoom; scaleY = zoom })
                // Dark under the status bar, then clear, then a long fall into the page's black.
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.55f), 0.18f to Color.Transparent,
                    0.45f to Color.Transparent, 0.82f to Palette.canvas.copy(alpha = 0.85f), 1f to Palette.canvas)))
            }
        }
        val item = picks[pager.currentPage.coerceIn(0, picks.lastIndex)]
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 24.dp, vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (item.logoTag != null) {
                AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 700), item.name, contentScale = ContentScale.Fit,
                    modifier = Modifier.height(84.dp).fillMaxWidth(0.72f))
            } else {
                Text(item.name, style = IosType.largeTitle.copy(fontSize = 30.sp), color = Color.White, maxLines = 2,
                    textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
            }
            IosCaption(listOfNotNull(if (item.isSeries) "TV Show" else "Movie", item.genres.firstOrNull(), item.year?.toString())
                .joinToString(" · "), color = Color.White.copy(alpha = 0.75f))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                val listed = item.id in state.settings.watchlist
                if (!state.roomOpen) IosCircle(if (listed) Icons.Default.Check else Icons.Default.Add,
                    if (listed) "Remove from Up Next" else "Add to Up Next", {
                        val before = state.settings.watchlist
                        state.settings.watchlist = if (listed) before - item.id else listOf(item.id) + before
                        state.homeRefresh++
                        PhoneNotice.show(if (listed) "Removed from Up Next" else "Added to Up Next") {
                            state.settings.watchlist = before; state.homeRefresh++
                        }
                    })
                IosButton("Play", {
                    if (item.isSeries) scope.launch { playSeries(state, item) } else state.push(Screen.Player(item.id, null))
                }, Modifier.width(170.dp), icon = Icons.Default.PlayArrow)
                IosCircle(Icons.Outlined.Info, "Details", { state.push(Screen.Detail(item.id)) })
            }
            if (picks.size > 1) Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                repeat(picks.size) { i ->
                    val on = i == pager.currentPage
                    Box(Modifier.padding(horizontal = 3.dp).size(if (on) 7.dp else 6.dp).clip(CircleShape)
                        .background(if (on) Color.White else Color.White.copy(alpha = 0.3f)))
                }
            }
        }
    }
}

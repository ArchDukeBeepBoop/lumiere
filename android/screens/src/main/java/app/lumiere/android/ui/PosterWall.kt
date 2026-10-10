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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.libraryPage
import coil.compose.AsyncImage
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * The poster wall, on a Quest: a library as a curved wall of posters around
 * you, three high, as a video shop's wall was. Turn your head to browse;
 * point and pinch to open a title, which the window then shows. Posters are
 * fetched only as they come into view, through the app's own image cache,
 * and the private room's titles appear only while the room is open, as
 * everywhere else. The headset's module puts the wall round you.
 */
object PosterWall {
    /** Set by the Quest's spatial app. */
    var enabled = false
    var open by mutableStateOf(false)
    /** Thumbstick nudges, left (-1) or right (+1); the wall scrolls a few columns each. */
    var nudges by mutableIntStateOf(0)
        private set
    var lastNudge = 0
        private set

    fun nudge(direction: Int) { lastNudge = direction; nudges++ }

    /** The libraries a wall can show: films, shows and home videos, as the app shows them now. */
    fun wallViews(state: AppState): List<Item> =
        state.visibleViews(state.views).filter { it.collectionType in setOf("movies", "tvshows", "homevideos", "mixed", null) }

    @Composable
    fun Panel() {
        LumiereTheme {
            val state = OpenApp.state
            if (!open || state?.server == null || state.session == null) return@LumiereTheme
            Wall(state)
        }
    }
}

private const val PAGE = 90

@Composable
private fun Wall(state: AppState) {
    val server = state.server ?: return
    val session = state.session ?: return
    val views = PosterWall.wallViews(state)
    var chosen by remember { mutableStateOf(views.firstOrNull()) }
    val view = chosen?.takeIf { c -> views.any { it.id == c.id } } ?: views.firstOrNull()
    val items = remember(view?.id) { mutableStateListOf<Item>() }
    var exhausted by remember(view?.id) { mutableStateOf(false) }
    var loading by remember(view?.id) { mutableStateOf(false) }
    val grid = rememberLazyGridState()

    suspend fun more() {
        val v = view ?: return
        if (loading || exhausted) return
        loading = true
        val page = runCatching { server.libraryPage(session.userId, v.id, items.size, PAGE, "SortName", false) }.getOrNull()
        if (page == null || page.size < PAGE) exhausted = true
        page?.let { items += state.visible(it) }
        loading = false
    }

    LaunchedEffect(view?.id) { grid.scrollToItem(0); more() }
    // More as you near the end of what's loaded.
    LaunchedEffect(view?.id) {
        snapshotFlow { grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
            .distinctUntilChanged()
            .collect { last -> if (last > items.size - 30) more() }
    }
    // The thumbsticks scroll it a few columns at a time.
    LaunchedEffect(PosterWall.nudges) {
        if (PosterWall.nudges == 0) return@LaunchedEffect
        val to = (grid.firstVisibleItemIndex + PosterWall.lastNudge * 12).coerceIn(0, (items.size - 1).coerceAtLeast(0))
        grid.animateScrollToItem(to)
    }

    Column(Modifier.fillMaxSize().frosted(36).padding(horizontal = 28.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Poster Wall", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.width(18.dp))
            views.forEach { v ->
                WallChip(v.name, chosen = v.id == view?.id) { chosen = v }
            }
            Spacer(Modifier.weight(1f))
            WallChip("Done", chosen = false) { PosterWall.open = false }
        }
        if (view == null) {
            Text("No libraries to show here.", color = Palette.textSecondary)
            return@Column
        }
        LazyHorizontalGrid(
            GridCells.Fixed(3), state = grid, modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            items(items, key = { it.id }) { item ->
                WallPoster(item, server) {
                    state.push(Screen.Detail(item.id))
                    PosterWall.open = false
                }
            }
        }
    }
}

/** One poster: it lifts and takes a light rim where you point, and a pinch opens it. */
@Composable
private fun WallPoster(item: Item, server: app.lumiere.android.api.Server, onOpen: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val shape = RoundedCornerShape(10.dp)
    Box(Modifier.fillMaxHeight().aspectRatio(2f / 3f)
        .graphicsLayer { val s = if (hovered) 1.07f else 1f; scaleX = s; scaleY = s }
        .clip(shape).background(Palette.surface)
        .then(if (hovered) Modifier.border(2.dp, Color.White.copy(alpha = 0.85f), shape) else Modifier)
        .hoverable(source).clickable(interactionSource = source, indication = null, onClick = onOpen)) {
        val image = imageFor(item, server, CardShape.Poster, 300)
        if (image != null) AsyncImage(image, item.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        else Text(item.name, modifier = Modifier.align(Alignment.Center).padding(10.dp), maxLines = 4, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun WallChip(label: String, chosen: Boolean, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when { chosen -> Palette.textPrimary; hovered -> Color.White.copy(alpha = 0.22f); else -> Color.White.copy(alpha = 0.08f) }
    Box(Modifier.clip(RoundedCornerShape(50)).background(ground).hoverable(source)
        .clickable(interactionSource = source, indication = null, onClick = onClick)
        .padding(horizontal = 18.dp, vertical = 9.dp)) {
        Text(label, color = if (chosen) Palette.canvas else Palette.textPrimary, maxLines = 1)
    }
}

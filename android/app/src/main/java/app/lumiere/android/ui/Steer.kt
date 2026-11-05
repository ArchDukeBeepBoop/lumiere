package app.lumiere.android.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server

/**
 * Home's scrolling, for every TV page: the page never moves by focus (provide
 * [rememberSteeredPageScroll]), and each time the chosen row changes it is put
 * on one line, [landing] of the way down the screen. The same height going down
 * as coming up, and nothing appearing or vanishing above it to push it about.
 */
@Composable
fun SteeredList(list: LazyListState, focusedIndex: Int?, landing: Float = TvSpace.landing) {
    val linePx = landingPx(landing)
    LaunchedEffect(focusedIndex) {
        val i = focusedIndex ?: return@LaunchedEffect
        val info = list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == i }
        // Going up, the row above has usually left the screen already: fetch it first, then settle it.
        if (info == null) { list.scrollToItem(i); list.animateScrollBy(-linePx, tween(app.lumiere.android.Motion.ms(260))) }
        else list.animateScrollBy(info.offset - linePx, tween(app.lumiere.android.Motion.ms(260)))
    }
}

/** The grid's form: steered by line, so moving along a line never scrolls. */
@Composable
fun SteeredGrid(grid: LazyGridState, focusedIndex: Int?, landing: Float = TvSpace.landing) {
    val linePx = landingPx(landing)
    val columns = grid.layoutInfo.visibleItemsInfo.count { it.row == grid.layoutInfo.visibleItemsInfo.firstOrNull()?.row }.coerceAtLeast(1)
    val line = focusedIndex?.let { i -> grid.layoutInfo.visibleItemsInfo.firstOrNull { it.index == i }?.row ?: (i / columns - 1_000_000) }
    LaunchedEffect(line) {
        val i = focusedIndex ?: return@LaunchedEffect
        val info = grid.layoutInfo.visibleItemsInfo.firstOrNull { it.index == i }
        if (info == null) { grid.scrollToItem(i); grid.animateScrollBy(-linePx, tween(app.lumiere.android.Motion.ms(260))) }
        else grid.animateScrollBy(info.offset.y - linePx, tween(app.lumiere.android.Motion.ms(260)))
    }
}

@Composable
private fun landingPx(landing: Float): Float {
    val config = LocalConfiguration.current
    return config.screenHeightDp * landing * LocalDensity.current.density
}

/**
 * The compact strip over the top of a page, fading in and out where it stands,
 * so the page beneath never changes size. The page keeps [TvSpace.strip] of room at its top.
 */
@Composable
fun StripOverlay(item: Item?, server: Server, shown: Boolean, modifier: Modifier = Modifier) {
    val a by animateFloatAsState(if (shown && item != null) 1f else 0f, tween(app.lumiere.android.Motion.ms(250)), label = "strip")
    if (item != null && a > 0f) InfoArea(item, server, modifier.graphicsLayer { alpha = a })
}

@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.ui.ExperimentalComposeUiApi::class)

package app.lumiere.android.tv.browse

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.ui.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The start padding every row and the hero's words share (spec §3, §6). */
val BrowseStart = 48.dp

/**
 * The immersive browse screen (spec): a hero behind a column of rows, all of it
 * driven by D-pad focus. Row 0 drives the hero; leaving Row 0 fades the hero up
 * and away; every other row settles with its top on the 22 % keyline; along a
 * row the focused card stays pinned at the start padding.
 */
@Composable
fun ImmersiveBrowse(catalog: Catalog, onOpen: (BrowseItem) -> Unit) {
    val rows by produceState<List<BrowseRow>>(emptyList(), catalog) { value = runCatching { catalog.rows() }.getOrDefault(emptyList()) }
    val state = remember { BrowseState() }
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val rowZero = remember { FocusRequester() }
    // The column scrolls only when told (§5); this spec returns 0 so focus alone never moves it.
    val noAutoScroll = remember { object : BringIntoViewSpec {
        override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float) = 0f
    } }

    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.ground)) {
        val screenH = maxHeight
        val keylinePx = with(LocalDensity.current) { (screenH * 0.22f).toPx() }

        // Row 0's focused card becomes the hero after a 250 ms pause, so scrubbing
        // along the row neither fetches nor fades for every card it passes (§3).
        val rowZeroIndex = state.focusedIndexPerRow[0] ?: 0
        LaunchedEffect(rows, rowZeroIndex) {
            val item = rows.firstOrNull()?.items?.getOrNull(rowZeroIndex) ?: return@LaunchedEffect
            if (state.heroItem != null) delay(250)
            state.heroItem = item
        }
        HeroLayer(state.heroItem, visible = state.focusedRow == 0, rows.firstOrNull()?.items, rowZeroIndex)

        // Vertical keyline, driven by focus rather than scroll position (§5).
        LaunchedEffect(state.focusedRow) {
            if (state.focusedRow == 0) list.animateScrollToItem(0)
            else { list.animateScrollToItem(state.focusedRow + 1); list.animateScrollBy(-keylinePx) }
        }
        // Back from a lower row: to the top, onto the card last chosen in Row 0 (§4).
        if (state.focusedRow >= 1) androidx.activity.compose.BackHandler {
            scope.launch { list.animateScrollToItem(0); delay(60); runCatching { rowZero.requestFocus() } }
        }

        CompositionLocalProvider(LocalBringIntoViewSpec provides noAutoScroll) {
            LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = screenH * 0.5f)) {
                item(key = "hero-spacer") { Spacer(Modifier.height(screenH * 0.58f)) }
                itemsIndexed(rows, key = { _, r -> r.id }) { r, row ->
                    // The row above the focused one stays in sight, dimmed to 40 % (§5).
                    val dim by animateFloatAsState(if (r < state.focusedRow) 0.4f else 1f, tween(300), label = "dim")
                    Column(Modifier.graphicsLayer { alpha = dim }.onFocusChanged { if (it.hasFocus) state.focusedRow = r }
                        .padding(bottom = 6.dp)) {
                        Text(row.title, color = Palette.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(start = BrowseStart, bottom = 2.dp))
                        PinnedLeftRow(row, BrowseStart, if (r == 0) Modifier.focusRequester(rowZero) else Modifier,
                            onFocus = { i -> state.focusedIndexPerRow[r] = i }, onOpen = onOpen)
                    }
                }
            }
        }
        LaunchedEffect(rows) { if (rows.isNotEmpty()) { delay(100); runCatching { rowZero.requestFocus() } } }
    }
}

/**
 * A row whose focused card keeps its leading edge on the start padding while the
 * row scrolls beneath it (§6); at the end the row clamps and focus walks on.
 * The spec is provided for this row only, never at the screen's root.
 */
@Composable
fun PinnedLeftRow(row: BrowseRow, startPadding: Dp, modifier: Modifier, onFocus: (Int) -> Unit, onOpen: (BrowseItem) -> Unit) {
    val keylinePx = with(LocalDensity.current) { startPadding.toPx() }
    val pinLeft = remember(keylinePx) { object : BringIntoViewSpec {
        override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float) = offset - keylinePx
    } }
    CompositionLocalProvider(LocalBringIntoViewSpec provides pinLeft) {
        LazyRow(modifier.focusRestorer(),
            // Room above and below for a 1.1× card and its glow (§7).
            contentPadding = PaddingValues(start = startPadding, end = startPadding, top = 18.dp, bottom = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            itemsIndexed(row.items, key = { _, it -> it.id }) { i, item ->
                BrowseCard(item, row.cardType, row.alwaysShowTitle, onFocus = { onFocus(i) }, onClick = { onOpen(item) })
            }
        }
    }
}

package app.lumiere.android.ui

import androidx.compose.foundation.gestures.BringIntoViewSpec

/**
 * How every TV page scrolls to the remote: not at all while what is chosen is
 * wholly on screen, and only as far as needed when it is not. Moving along a
 * row or down a grid no longer nudges the whole page each press.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
object CalmScroll : BringIntoViewSpec {
    override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float = when {
        offset >= 0f && offset + size <= containerSize -> 0f
        offset < 0f -> offset
        size > containerSize -> offset
        else -> offset + size - containerSize
    }
}

/**
 * How a TV page scrolls to the remote, by direction — the Leanback / Google TV
 * focus line:
 *
 *  - Down a page, the chosen row settles at one height, about a third of the
 *    way down, whichever way the remote moved. (Scrolling only "as far as
 *    needed" left a row entering from below parked at the bottom edge and the
 *    same row higher on the way back up — rows looked misaligned going down.)
 *    Things already in the upper part of the screen stay put, so a banner's
 *    buttons and the first rows under it do not jump.
 *  - Along a row, nothing moves while the next card is on screen; past the
 *    edge the row turns so the chosen card stands at the page margin, so every
 *    row's cards keep one left edge.
 *
 * A spec is told only sizes, not the direction, so it tells them apart by the
 * screen: a container as wide as the screen is a row; anything else is a page.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
class TvScroll(private val screenWidth: Float, private val screenHeight: Float,
               private val line: Float = 0.1f, private val still: () -> Boolean = { false }) : BringIntoViewSpec {
    override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
        val visible = offset >= 0f && offset + size <= containerSize
        val row = containerSize > screenHeight * 1.2f && containerSize >= screenWidth * 0.7f
        // Along a row: the chosen card pinned at the page margin, the row sliding beneath it.
        if (row) return offset - containerSize * 0.058f
        if (still()) return 0f
        // A short list — Settings, a menu, a pop-up — scrolls only as far as needed.
        if (containerSize < screenHeight * 0.75f) return when {
            visible -> 0f
            offset < 0f -> offset
            else -> offset + size - containerSize
        }
        // Down or up a page: the chosen row brought to the top, under room for its title.
        return offset - containerSize * line
    }
}

/** The focus line for this screen, sized from its configuration. */
@androidx.compose.runtime.Composable
fun rememberTvScroll(still: () -> Boolean = { false }): TvScroll {
    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    return androidx.compose.runtime.remember(config.screenWidthDp, config.screenHeightDp) {
        TvScroll(config.screenWidthDp * density, config.screenHeightDp * density, still = still)
    }
}

/**
 * For a page that steers its own vertical scroll: the page itself never moves by focus,
 * but any row inside it still pins the chosen card at the margin. (A plain "never move"
 * spec is inherited by the rows too, and they stopped scrolling sideways.)
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@androidx.compose.runtime.Composable
fun rememberSteeredPageScroll(): BringIntoViewSpec {
    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    return androidx.compose.runtime.remember(config.screenWidthDp, config.screenHeightDp) {
        val w = config.screenWidthDp * density; val h = config.screenHeightDp * density
        @OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
        object : BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
                val row = containerSize > h * 1.2f && containerSize >= w * 0.7f
                return if (row) offset - containerSize * 0.058f else 0f
            }
        }
    }
}

/**
 * For a long list of lines — tracks, an album, an artist: the page moves only as
 * far as needed to keep the chosen line in view (Apple Music's lists), while any
 * row inside it still pins the chosen card at the margin.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@androidx.compose.runtime.Composable
fun rememberCalmPageScroll(): BringIntoViewSpec {
    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    return androidx.compose.runtime.remember(config.screenWidthDp, config.screenHeightDp) {
        val w = config.screenWidthDp * density; val h = config.screenHeightDp * density
        @OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
        object : BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
                val row = containerSize > h * 1.2f && containerSize >= w * 0.7f
                return if (row) offset - containerSize * 0.058f else CalmScroll.calculateScrollDistance(offset, size, containerSize)
            }
        }
    }
}

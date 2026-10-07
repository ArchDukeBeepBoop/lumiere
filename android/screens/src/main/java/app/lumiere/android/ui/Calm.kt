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

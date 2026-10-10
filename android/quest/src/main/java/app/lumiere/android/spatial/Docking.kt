package app.lumiere.android.spatial

import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3

/**
 * Where a panel docks beside the window: the tab bar just past its left
 * edge, level with its middle, facing the same way. You face +Z, so the
 * window's left is its local +X.
 */
object Docking {
    /** How far past the window's left edge the tab bar's middle sits, for a window [windowWidthM] wide. */
    fun sideOffset(windowWidthM: Float): Float = windowWidthM / 2 + Window.SIDEBAR_GAP_M + Window.SIDEBAR_WIDTH_M / 2

    /** The tab bar's pose beside a window at [window], [windowWidthM] wide. */
    fun beside(window: Pose, windowWidthM: Float): Pose =
        Pose(window.t + window.q * Vector3(sideOffset(windowWidthM), 0f, 0f), window.q)
}

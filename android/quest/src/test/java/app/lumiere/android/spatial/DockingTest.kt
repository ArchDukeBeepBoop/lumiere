package app.lumiere.android.spatial

import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import org.junit.Assert.assertEquals
import org.junit.Test

class DockingTest {
    @Test fun theTabBarDocksJustPastTheWindowsLeftEdge() {
        val window = Pose(Vector3(0f, 1.3f, 1.4f))
        val at = Docking.beside(window, Window.WIDTH_M).t
        assertEquals(Window.WIDTH_M / 2 + Window.SIDEBAR_GAP_M + Window.SIDEBAR_WIDTH_M / 2, at.x, 1e-4f)
        assertEquals(1.3f, at.y, 1e-4f)
        assertEquals(1.4f, at.z, 1e-4f)
    }

    @Test fun itFollowsAWiderWindowAndATurnedOne() {
        assertEquals(Docking.sideOffset(1.6f) + 0.5f, Docking.sideOffset(2.6f), 1e-4f)
        // A window off to your right, turned to face you: the bar is still on its left, beside it.
        val turned = Pose(Vector3(1.4f, 1.3f, 0f), Quaternion.fromDirection(Vector3(1f, 0f, 0f)))
        val at = Docking.beside(turned, Window.WIDTH_M).t
        assertEquals("level", 1.3f, at.y, 1e-4f)
        assertEquals("same distance out", 1.4f, at.x, 1e-3f)
        assertEquals("along the window's face", Docking.sideOffset(Window.WIDTH_M), kotlin.math.abs(at.z), 1e-3f)
    }
}

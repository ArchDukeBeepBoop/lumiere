package app.lumiere.android.spatial

import app.lumiere.android.R
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.createPanelEntity

/**
 * What pops up over a film, each placed before you as it opens: the player's
 * menus just above the bar's right end (BarMenu), and Where to Watch a little
 * under your eyes (PlacePicker). Each goes when it closes.
 */
class StagePops(private val scene: Scene) {
    private var menu: Entity? = null
    private var picker: Entity? = null

    fun tick() {
        if ((BarMenu.kind != null) != (menu != null)) menu = swap(menu, BarMenu.kind != null) { head, ahead ->
            val right = Vector3(-ahead.z, 0f, ahead.x)
            R.id.lumiere_menu to (head + ahead * TheaterStage.MENU_M -
                Vector3(0f, TheaterStage.BAR_BELOW_M - BarMenu.HEIGHT_M / 2 - 0.08f, 0f) + right * (FilmBar.WIDTH_M / 2 - BarMenu.WIDTH_M / 2))
        }
        if (PlacePicker.open != (picker != null)) picker = swap(picker, PlacePicker.open) { head, ahead ->
            R.id.lumiere_places to (head + ahead * TheaterStage.PICKER_M - Vector3(0f, TheaterStage.PICKER_BELOW_M, 0f))
        }
    }

    private fun swap(old: Entity?, show: Boolean, where: (Vector3, Vector3) -> Pair<Int, Vector3>): Entity? {
        old?.let { runCatching { it.destroy() } }
        if (!show) return null
        val head = scene.getViewerPose()
        val (id, at) = where(head.t, level(head.forward()))
        return Entity.createPanelEntity(id, Transform(Pose(at, Quaternion.fromDirection((at - head.t).normalize()))))
    }
}

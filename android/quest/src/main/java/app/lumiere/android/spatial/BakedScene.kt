package app.lumiere.android.spatial

import app.lumiere.android.Stage
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3

/**
 * A place made and lit in Blender (Scripts/env): its model where it belongs
 * — the cinema's hall round its screen, the cabin round its screen wall, the
 * lakeside's pontoon round you — found by [anchor] from the floor under your
 * eyes and the size you chose; and, if it has one, what comes with you at
 * your feet ([withYou]: the cabin's sofa). If either can't be loaded, the
 * place shows its modelled blocks instead.
 */
class BakedScene(
    val place: Stage.Place,
    val room: BakedPlace,
    val withYou: BakedPlace? = null,
    private val anchor: (floor: Pose, size: Int) -> Pose = { floor, _ -> floor },
) {
    val usable: Boolean get() = room.state != BakedPlace.State.FAILED && withYou?.state != BakedPlace.State.FAILED

    fun place(floor: Pose, size: Int) {
        room.place(anchor(floor, size))
        withYou?.place(floor)
    }

    fun show(on: Boolean) { room.show(on); withYou?.show(on) }

    /** Its models unloaded (BakedPlace.release); made again when next placed. */
    fun release() { room.release(); withYou?.release() }

    fun light(level: Float, left: Triple<Float, Float, Float>?, right: Triple<Float, Float, Float>?) {
        room.light(level, left, right)
        withYou?.light(level, left, right)
    }

    /** True once, the moment either model is known not to load. */
    fun failedNow(now: Long): Boolean {
        val a = room.failedNow(now)
        val b = withYou?.failedNow(now) == true
        return a || b
    }

    companion object {
        /** [floor] moved by [offset] in its own frame (x left, y up, z ahead). */
        fun ahead(floor: Pose, offset: FloatArray): Pose = Pose(floor.t + floor.q * Vector3(offset[0], offset[1], offset[2]), floor.q)
    }
}

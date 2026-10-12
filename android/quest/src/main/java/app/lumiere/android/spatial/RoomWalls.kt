package app.lumiere.android.spatial

import com.meta.spatial.mruk.MRUKAnchor
import com.meta.spatial.mruk.MRUKFeature
import com.meta.spatial.mruk.MRUKLoadDeviceResult
import com.meta.spatial.mruk.MRUKPlane
import com.meta.spatial.toolkit.Transform

/**
 * Your room's walls, from the headset's Space Setup (the Mixed Reality
 * Utility Kit), for the film's screen to hang on (WallMount). Nothing is
 * read until you ask to mount the screen, or a mount you made before needs
 * its wall again; then Lumiere asks for the headset's "spatial data"
 * permission once, and loads the room. With no Space Setup yet, the
 * headset offers to run it.
 */
class RoomWalls(private val activity: android.app.Activity, private val mruk: MRUKFeature) {
    enum class State { UNKNOWN, LOADING, READY, NO_PERMISSION, NO_ROOM, FAILED }

    var state = State.UNKNOWN
        private set
    private val waiting = mutableListOf<(State) -> Unit>()

    /** Whether the headset has let Lumiere see the room. */
    fun allowed(): Boolean = activity.checkSelfPermission(PERMISSION) == android.content.pm.PackageManager.PERMISSION_GRANTED

    /** The room loaded (asking for the permission first if need be), then [done] with how it went. */
    fun load(done: (State) -> Unit) {
        if (state == State.READY) return done(state)
        waiting += done
        if (state == State.LOADING) return
        state = State.LOADING
        if (!allowed()) {
            app.lumiere.android.Probe.info("wall mount", "permission", "asking for spatial data ($PERMISSION)")
            activity.requestPermissions(arrayOf(PERMISSION), REQUEST); return
        }
        app.lumiere.android.Probe.ok("wall mount", "permission", "spatial data allowed")
        readRoom()
    }

    /** The answer to the permission's question (LumiereSpace.onRequestPermissionsResult). */
    fun answered(granted: Boolean) {
        if (state != State.LOADING) return
        app.lumiere.android.Probe.report("wall mount", "permission", if (granted) app.lumiere.android.Probe.Status.OK else app.lumiere.android.Probe.Status.FAIL,
            if (granted) "spatial data allowed just now" else "spatial data refused: allow it in Settings > Apps > Lumiere > Permissions")
        if (granted) readRoom() else finish(State.NO_PERMISSION)
    }

    private fun readRoom() {
        runCatching {
            mruk.loadSceneFromDevice().whenComplete { result, error ->
                activity.runOnUiThread {
                    val all = walls()
                    val rooms = runCatching { mruk.rooms.size }.getOrDefault(-1)
                    app.lumiere.android.Probe.report("wall mount", "Space Setup",
                        if (error == null && result == MRUKLoadDeviceResult.SUCCESS && all.isNotEmpty()) app.lumiere.android.Probe.Status.OK else app.lumiere.android.Probe.Status.FAIL,
                        "load result $result${if (error != null) ", error ${app.lumiere.android.Probe.why(error)}" else ""}; " +
                            "$rooms room(s), ${all.size} wall(s) with planes" +
                            (if (all.isNotEmpty()) ": " + all.joinToString { "%.1f×%.1f m".format(it.maxX - it.minX, it.maxY - it.minY) } else "") +
                            "; raw wall entities ${runCatching { mruk.rooms.sumOf { it.walls.size } }.getOrDefault(-1)}")
                    finish(when {
                        error != null -> State.FAILED
                        result == MRUKLoadDeviceResult.SUCCESS -> if (walls().isEmpty()) State.NO_ROOM else State.READY
                        result == MRUKLoadDeviceResult.ERROR_NO_ROOMS_FOUND -> State.NO_ROOM
                        result == MRUKLoadDeviceResult.ERROR_PERMISSION_INSUFFICIENT -> State.NO_PERMISSION
                        else -> State.FAILED
                    })
                }
            }
        }.onFailure { app.lumiere.android.Probe.fail("wall mount", "Space Setup", "loading the room threw ${app.lumiere.android.Probe.why(it)}"); finish(State.FAILED) }
    }

    private fun finish(s: State) {
        // A refusal or a failure can be tried again next time; a loaded room stays.
        state = if (s == State.READY) s else State.UNKNOWN
        val them = waiting.toList(); waiting.clear()
        them.forEach { runCatching { it(s) } }
    }

    /** Every wall of the rooms Space Setup knows, with its plane, as WallMount reads them. */
    fun walls(): List<WallMount.Wall> = runCatching {
        mruk.rooms.flatMap { it.walls }.mapNotNull { e ->
            if (!e.hasComponent<MRUKAnchor>() || !e.hasComponent<MRUKPlane>() || !e.hasComponent<Transform>()) return@mapNotNull null
            val anchor = e.getComponent<MRUKAnchor>()
            val plane = e.getComponent<MRUKPlane>()
            WallMount.Wall(anchor.uuid.toString(), worldPose(e), plane.min.x, plane.max.x, plane.min.y, plane.max.y)
        }
    }.getOrDefault(emptyList())

    /** [e]'s pose in the world: its own, carried by each parent's (a wall's is its room's). */
    private fun worldPose(e: com.meta.spatial.core.Entity): com.meta.spatial.core.Pose {
        var pose = e.getComponent<Transform>().transform
        var at = e
        repeat(8) {
            val parent = runCatching { at.getComponent<com.meta.spatial.toolkit.TransformParent>().entity }.getOrNull() ?: return pose
            if (parent == com.meta.spatial.core.Entity.nullEntity() || !parent.hasComponent<Transform>()) return pose
            val p = parent.getComponent<Transform>().transform
            pose = com.meta.spatial.core.Pose(p.t + p.q * pose.t, p.q * pose.q)
            at = parent
        }
        return pose
    }

    /** The wall with [id], if the room has it (Space Setup can be run again and a wall lost). */
    fun wall(id: String): WallMount.Wall? = walls().firstOrNull { it.id == id }

    companion object {
        const val PERMISSION = "com.oculus.permission.USE_SCENE"
        const val REQUEST = 4207
    }
}

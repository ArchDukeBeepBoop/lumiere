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
            log("permission", "asking for spatial data ($PERMISSION)")
            activity.requestPermissions(arrayOf(PERMISSION), REQUEST); return
        }
        log("permission", "spatial data allowed")
        readRoom()
    }

    /** The answer to the permission's question (LumiereSpace.onRequestPermissionsResult). */
    fun answered(granted: Boolean) {
        if (state != State.LOADING) return
        log("permission", if (granted) "ok" else "failed",
            if (granted) "spatial data allowed just now" else "spatial data refused: allow it in Settings > Apps > Lumiere > Permissions")
        if (granted) readRoom() else finish(State.NO_PERMISSION)
    }

    private fun readRoom(attempt: Int = 1) {
        val reading = ++reads
        log("Space Setup", "reading the room (attempt $attempt)…")
        // Not answered in time: whatever walls came anyway are used; else once more, then give up and say so.
        handler.postDelayed({
            if (reading != reads || state != State.LOADING) return@postDelayed
            val all = walls()
            if (all.isNotEmpty()) {
                log("Space Setup", "no answer in ${TIMEOUT_MS / 1000} s, but ${all.size} wall(s) arrived: using them")
                finish(State.READY)
            } else if (attempt < 2) readRoom(attempt + 1)
            else {
                log("Space Setup", "no answer from the headset's room data after $attempt tries " +
                    "(${runCatching { mruk.rooms.size }.getOrDefault(-1)} rooms known): run Space Setup in the headset's Settings > Physical space, then press Wall again")
                finish(State.FAILED)
            }
        }, TIMEOUT_MS)
        runCatching {
            // Never opens Space Setup itself (that could wait for ever): no room says so instead.
            mruk.loadSceneFromDevice(false, true, com.meta.spatial.mruk.SceneModel.V2_FALLBACK_V1).whenComplete { result, error ->
                activity.runOnUiThread {
                    if (reading != reads || state != State.LOADING) return@runOnUiThread
                    reads++
                    val all = walls()
                    val rooms = runCatching { mruk.rooms.size }.getOrDefault(-1)
                    log("Space Setup", if (error == null && result == MRUKLoadDeviceResult.SUCCESS && all.isNotEmpty()) "ok" else "failed",
                        "load result $result${if (error != null) ", error ${(error.message ?: error.javaClass.simpleName)}" else ""}; " +
                            "$rooms room(s), ${all.size} wall(s) with planes" +
                            (if (all.isNotEmpty()) ": " + all.joinToString { "%.1f×%.1f m".format(it.maxX - it.minX, it.maxY - it.minY) } else "") +
                            "; raw wall entities ${runCatching { mruk.rooms.sumOf { it.walls.size } }.getOrDefault(-1)}")
                    finish(when {
                        all.isNotEmpty() -> State.READY
                        error != null -> State.FAILED
                        result == MRUKLoadDeviceResult.SUCCESS -> State.NO_ROOM
                        result == MRUKLoadDeviceResult.ERROR_NO_ROOMS_FOUND -> State.NO_ROOM
                        result == MRUKLoadDeviceResult.ERROR_PERMISSION_INSUFFICIENT -> State.NO_PERMISSION
                        else -> State.FAILED
                    })
                }
            }
        }.onFailure { reads++; log("Space Setup", "loading the room threw ${(it.message ?: it.javaClass.simpleName)}"); finish(State.FAILED) }
    }

    private var reads = 0
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

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
            // The wall's own Transform, as Space Setup gives it, is already where it is in the room
            // (HANDOVER §3.7). Carried again through its room's, as before, every wall was turned by
            // the room's angle a second time: the screen hung at the wrong angle on the headset.
            // Both are logged, so a try on the headset settles it (docs/QUEST_PLAN.md, M4).
            val own = e.getComponent<Transform>().transform
            if (logPoses) android.util.Log.i("Lumiere", "walls: ${anchor.uuid.toString().take(8)} own ${describe(own)} " +
                "chained ${describe(worldPose(e))} plane ${"%.2f..%.2f x %.2f..%.2f".format(plane.min.x, plane.max.x, plane.min.y, plane.max.y)}")
            WallMount.Wall(anchor.uuid.toString(), if (CHAIN_PARENTS) worldPose(e) else own, plane.min.x, plane.max.x, plane.min.y, plane.max.y)
        }
    }.getOrDefault(emptyList())

    /** Log both readings of each wall's pose the next time the walls are read. */
    var logPoses = true

    private fun describe(p: com.meta.spatial.core.Pose): String {
        val n = p.q * com.meta.spatial.core.Vector3(0f, 0f, 1f)
        val up = p.q * com.meta.spatial.core.Vector3(0f, 1f, 0f)
        return "at (%.2f, %.2f, %.2f) normal (%.2f, %.2f, %.2f) up (%.2f, %.2f, %.2f)".format(p.t.x, p.t.y, p.t.z, n.x, n.y, n.z, up.x, up.y, up.z)
    }

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

    private fun log(what: String, vararg words: String) = android.util.Log.i("Lumiere", "walls: $what: ${words.joinToString(" ")}")

    companion object {
        /** Whether a wall's pose is carried through its room's (the old reading, which hung the screen askew). */
        const val CHAIN_PARENTS = false
        const val PERMISSION = "com.oculus.permission.USE_SCENE"
        const val REQUEST = 4207
        const val TIMEOUT_MS = 10_000L
    }
}

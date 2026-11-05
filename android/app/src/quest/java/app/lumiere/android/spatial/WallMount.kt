package app.lumiere.android.spatial

import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import kotlin.math.tan

/**
 * The film's screen on a wall of your own room, as a TV is: the walls come
 * from the headset's Space Setup (RoomWalls), and this works out where on
 * one the screen goes. The wall you face takes it, where your gaze meets
 * it; it hangs flush, a few centimetres proud, square to the wall, as big
 * as your chosen size from where you stand but never past the wall's edges,
 * its middle at a comfortable height. Pure, so it's tested without a
 * headset.
 *
 * A wall's plane: its middle and turn ([pose]), and its extent in its own
 * x (along the wall) and y (up), as Space Setup gives them.
 */
object WallMount {
    data class Wall(val id: String, val pose: Pose, val minX: Float, val maxX: Float, val minY: Float, val maxY: Float) {
        val width get() = maxX - minX
        val height get() = maxY - minY
        fun along(): Vector3 = pose.q * Vector3(1f, 0f, 0f)
        fun up(): Vector3 = pose.q * Vector3(0f, 1f, 0f)
        /** Its face toward [eye]: Space Setup's normal, turned round if it points away from the room. */
        fun facing(eye: Vector3): Vector3 {
            val n = pose.q * Vector3(0f, 0f, 1f)
            return if ((eye - pose.t).dot(n) < 0f) -n else n
        }
        fun point(x: Float, y: Float): Vector3 = pose.t + along() * x + up() * y
    }

    /** How far off the wall the screen hangs. */
    const val PROUD = 0.03f
    /** Clear wall left round the screen. */
    const val MARGIN = 0.08f
    /** The screen's middle is kept at least this high off the floor (a TV's height), when the wall allows. */
    const val LOWEST_MIDDLE = 1.0f

    /** Where a gaze from [eye] along [look] meets [wall], in its own (x, y); null if it misses or looks away. */
    fun hit(wall: Wall, eye: Vector3, look: Vector3): Pair<Float, Float>? {
        val n = wall.facing(eye)
        val toward = look.dot(n)
        if (toward > -1e-3f) return null
        val t = (wall.pose.t - eye).dot(n) / toward
        if (t <= 0f) return null
        val at = eye + look * t - wall.pose.t
        val x = at.dot(wall.along()); val y = at.dot(wall.up())
        if (x < wall.minX || x > wall.maxX || y < wall.minY || y > wall.maxY) return null
        return x to y
    }

    /**
     * The wall your gaze meets nearest of [walls], with where on it; failing
     * that (Space Setup's walls a little off, or your gaze just past an
     * edge), the wall you most nearly face, within 40°, at the point on it
     * nearest your gaze's line.
     */
    fun facing(walls: List<Wall>, eye: Vector3, look: Vector3): Pair<Wall, Pair<Float, Float>>? {
        walls.mapNotNull { w -> hit(w, eye, look)?.let { w to it } }
            .minByOrNull { (w, at) -> (w.point(at.first, at.second) - eye).length() }?.let { return it }
        val flat = Vector3(look.x, 0f, look.z).let { if (it.length() < 1e-3f) return null else it.normalize() }
        return walls.mapNotNull { w ->
            val n = w.facing(eye)
            val toward = -flat.dot(n)
            if (toward < kotlin.math.cos(Math.toRadians(40.0)).toFloat()) return@mapNotNull null
            val t = (w.pose.t - eye).dot(n) / flat.dot(n)
            if (t <= 0f) return@mapNotNull null
            val at = eye + flat * t - w.pose.t
            val x = at.dot(w.along()).coerceIn(w.minX, w.maxX)
            val y = (eye.y - w.pose.t.y).coerceIn(w.minY, w.maxY)
            Triple(w, x to y, toward)
        }.maxByOrNull { it.third }?.let { (w, at, _) -> w to at }
    }

    /** How far [eye] stands from [wall]'s face. */
    fun distance(wall: Wall, eye: Vector3): Float = kotlin.math.abs((eye - wall.pose.t).dot(wall.facing(eye)))

    /**
     * The screen's width for [degrees] of your view from [distance], at the
     * film's [aspect], as large as that but no larger than the wall holds.
     */
    fun width(wall: Wall, degrees: Float, distance: Float, aspect: Float): Float {
        val wanted = 2 * distance * tan(Math.toRadians(degrees / 2.0)).toFloat()
        val byWidth = wall.width - 2 * MARGIN
        val byHeight = (wall.height - 2 * MARGIN) * aspect
        return minOf(wanted, byWidth, byHeight).coerceAtLeast(0.3f)
    }

    /**
     * Where on [wall] the middle of a screen [w] × [h] goes, asked for at
     * (x, y): the whole screen kept on the wall, its middle no lower than a
     * TV's where the wall is tall enough.
     */
    fun fit(wall: Wall, x: Float, y: Float, w: Float, h: Float, floorY: Float = wall.minY): Pair<Float, Float> {
        val loX = wall.minX + MARGIN + w / 2; val hiX = wall.maxX - MARGIN - w / 2
        val loY = maxOf(wall.minY + MARGIN + h / 2, floorY + LOWEST_MIDDLE)
        val hiY = wall.maxY - MARGIN - h / 2
        val fx = if (loX > hiX) (wall.minX + wall.maxX) / 2 else x.coerceIn(loX, hiX)
        val fy = if (loY > hiY) maxOf(hiY, (wall.minY + wall.maxY) / 2) else y.coerceIn(loY, hiY)
        return fx to fy
    }

    /** The screen's pose at (x, y) on [wall]: a few centimetres proud of it, square to it, upright, facing [eye]. */
    fun pose(wall: Wall, x: Float, y: Float, eye: Vector3): Pose {
        val n = wall.facing(eye)
        val level = Vector3(-n.x, 0f, -n.z).let { if (it.length() < 1e-3f) Vector3(0f, 0f, 1f) else it.normalize() }
        return Pose(wall.point(x, y) + n * PROUD, Quaternion.fromDirection(level))
    }
}
